const std = @import("std");
const mem = std.mem;
const net = std.net;
const http = std.http;
const posix = std.posix;

const Router = @import("./router.zig").Router;
const http_types = @import("./http_types.zig");
const mw = @import("./middleware.zig");

const Request = http_types.Request;
const Response = http_types.Response;

/// Error handler function signature
/// Allows users to customize error responses based on the error type
pub const ErrorHandlerFn = *const fn (err: anyerror, *Request, *Response, *anyopaque) anyerror!void;

/// Server mode selection
pub const ServerMode = enum {
    thread_pool, // Original thread-per-connection model
    minimal_threadpool, // Minimal thread pool with event-driven I/O (recommended for high concurrency)
};

pub const Server = struct {
    router: *Router,
    context: *anyopaque,
    allocator: mem.Allocator,
    port: u16,
    error_handler: ?ErrorHandlerFn = null,
    mode: ServerMode = .thread_pool, // Default to original mode for backward compatibility
    num_workers: usize = 2, // Number of worker threads for minimal_threadpool mode

    const MAX_HEADERS_SIZE = 8192;
    const MAX_BODY_SIZE = 10 * 1024 * 1024; // 10 MB limit to prevent DoS attacks
    const NUM_WORKERS = 4; // For legacy thread-pool mode

    const ConnectionState = struct {
        fd: i32,
        stream: net.Stream,
        address: net.Address,
        read_buffer: std.ArrayList(u8),
        write_buffer: std.ArrayList(u8),
        keep_alive: bool,
        allocator: mem.Allocator,

        fn init(allocator: mem.Allocator, fd: i32, stream: net.Stream, address: net.Address) !*ConnectionState {
            const state = try allocator.create(ConnectionState);
            state.* = .{
                .fd = fd,
                .stream = stream,
                .address = address,
                .read_buffer = .{},
                .write_buffer = .{},
                .keep_alive = true,
                .allocator = allocator,
            };
            return state;
        }

        fn deinit(self: *ConnectionState, allocator: mem.Allocator) void {
            self.read_buffer.deinit(self.allocator);
            self.write_buffer.deinit(self.allocator);
            self.stream.close();
            allocator.destroy(self);
        }
    };

    pub fn listen(self: *Server) !void {
        switch (self.mode) {
            .thread_pool => try self.listenThreadPool(),
            .minimal_threadpool => try self.listenMinimalThreadPool(),
        }
    }

    /// Original thread-pool based implementation
    fn listenThreadPool(self: *Server) !void {
        const address = try net.Address.parseIp("127.0.0.1", self.port);
        var tcp_server = try address.listen(.{ .reuse_address = true });
        defer tcp_server.deinit();

        std.log.info("Server listening on http://127.0.0.1:{d} (thread-pool mode)", .{self.port});

        var thread_pool: std.Thread.Pool = undefined;
        try thread_pool.init(.{
            .allocator = self.allocator,
            .n_jobs = NUM_WORKERS,
        });
        defer thread_pool.deinit();

        while (true) {
            const conn = try tcp_server.accept();
            try thread_pool.spawn(handleConnection, .{ conn, self.router, self.context, self.error_handler });
        }
    }

    /// Minimal thread pool architecture with event-driven I/O
    /// Uses epoll with a small number of worker threads for optimal performance
    fn listenMinimalThreadPool(self: *Server) !void {
        const address = try net.Address.parseIp("127.0.0.1", self.port);
        var tcp_server = try address.listen(.{ .reuse_address = true });
        defer tcp_server.deinit();

        std.log.info("Server listening on http://127.0.0.1:{d} (minimal thread pool mode)", .{self.port});
        std.log.info("Using {d} worker threads with epoll-based event loop", .{self.num_workers});

        // Create shared state for workers
        var shared_state = try WorkerSharedState.init(self.allocator, tcp_server.stream.handle);
        defer shared_state.deinit();

        // Start worker threads
        const workers = try self.allocator.alloc(std.Thread, self.num_workers);
        defer self.allocator.free(workers);

        const worker_context = WorkerContext{
            .shared_state = &shared_state,
            .router = self.router,
            .context = self.context,
            .error_handler = self.error_handler,
            .allocator = self.allocator,
        };

        for (workers) |*worker| {
            worker.* = try std.Thread.spawn(.{}, workerThreadMain, .{worker_context});
        }

        // Wait for all workers to complete (they run indefinitely)
        for (workers) |worker| {
            worker.join();
        }
    }

    const WorkerSharedState = struct {
        epoll_fd: i32,
        server_fd: i32,
        connections: std.AutoHashMap(i32, *ConnectionState),
        connections_mutex: std.Thread.Mutex,
        allocator: mem.Allocator,

        fn init(allocator: mem.Allocator, server_fd: i32) !WorkerSharedState {
            // Set server socket to non-blocking
            const flags = try posix.fcntl(server_fd, posix.F.GETFL, 0);
            const nonblock_flag = std.os.linux.O{ .NONBLOCK = true };
            _ = try posix.fcntl(server_fd, posix.F.SETFL, flags | @as(u32, @bitCast(nonblock_flag)));

            // Create epoll instance
            const epoll_fd = try posix.epoll_create1(0);

            // Register server socket with epoll
            var server_event = std.os.linux.epoll_event{
                .events = std.os.linux.EPOLL.IN | std.os.linux.EPOLL.ET,
                .data = .{ .fd = server_fd },
            };
            try posix.epoll_ctl(epoll_fd, std.os.linux.EPOLL.CTL_ADD, server_fd, &server_event);

            return WorkerSharedState{
                .epoll_fd = epoll_fd,
                .server_fd = server_fd,
                .connections = std.AutoHashMap(i32, *ConnectionState).init(allocator),
                .connections_mutex = .{},
                .allocator = allocator,
            };
        }

        fn deinit(self: *WorkerSharedState) void {
            posix.close(self.epoll_fd);

            self.connections_mutex.lock();
            defer self.connections_mutex.unlock();

            var it = self.connections.valueIterator();
            while (it.next()) |conn| {
                conn.*.deinit(self.allocator);
            }
            self.connections.deinit();
        }
    };

    const WorkerContext = struct {
        shared_state: *WorkerSharedState,
        router: *Router,
        context: *anyopaque,
        error_handler: ?ErrorHandlerFn,
        allocator: mem.Allocator,
    };

    fn workerThreadMain(ctx: WorkerContext) !void {
        const MAX_EVENTS = 64;
        var events: [MAX_EVENTS]std.os.linux.epoll_event = undefined;

        while (true) {
            const num_events = posix.epoll_wait(ctx.shared_state.epoll_fd, &events, 100);

            for (events[0..num_events]) |event| {
                const fd = event.data.fd;

                if (fd == ctx.shared_state.server_fd) {
                    // Accept new connections
                    acceptConnections(ctx) catch |err| {
                        std.log.err("Failed to accept connection: {any}", .{err});
                    };
                } else {
                    // Handle existing connection
                    if (event.events & std.os.linux.EPOLL.IN != 0) {
                        handleRead(ctx, fd) catch |err| {
                            std.log.err("Read error on fd {d}: {any}", .{ fd, err });
                            closeConnection(ctx, fd);
                        };
                    }

                    if (event.events & std.os.linux.EPOLL.OUT != 0) {
                        handleWrite(ctx, fd) catch |err| {
                            std.log.err("Write error on fd {d}: {any}", .{ fd, err });
                            closeConnection(ctx, fd);
                        };
                    }

                    if (event.events & (std.os.linux.EPOLL.ERR | std.os.linux.EPOLL.HUP) != 0) {
                        closeConnection(ctx, fd);
                    }
                }
            }
        }
    }

    fn acceptConnections(ctx: WorkerContext) !void {
        // Reconstruct a net.Server from the fd to accept connections
        const server_stream = net.Stream{ .handle = ctx.shared_state.server_fd };
        var tcp_server = net.Server{ .stream = server_stream, .listen_address = undefined };

        while (true) {
            const conn = tcp_server.accept() catch |err| switch (err) {
                error.WouldBlock => return,
                else => return err,
            };

            const fd = conn.stream.handle;

            // Set to non-blocking
            const flags = try posix.fcntl(fd, posix.F.GETFL, 0);
            const nonblock_flag = std.os.linux.O{ .NONBLOCK = true };
            _ = try posix.fcntl(fd, posix.F.SETFL, flags | @as(u32, @bitCast(nonblock_flag)));

            // Create connection state
            const state = try ConnectionState.init(ctx.allocator, fd, conn.stream, conn.address);

            ctx.shared_state.connections_mutex.lock();
            defer ctx.shared_state.connections_mutex.unlock();

            try ctx.shared_state.connections.put(fd, state);

            // Register with epoll
            var event = std.os.linux.epoll_event{
                .events = std.os.linux.EPOLL.IN | std.os.linux.EPOLL.ET,
                .data = .{ .fd = fd },
            };
            try posix.epoll_ctl(ctx.shared_state.epoll_fd, std.os.linux.EPOLL.CTL_ADD, fd, &event);

            std.log.debug("Worker accepted connection from {any}", .{conn.address});
        }
    }

    fn handleRead(ctx: WorkerContext, fd: i32) !void {
        ctx.shared_state.connections_mutex.lock();
        const conn = ctx.shared_state.connections.get(fd);
        ctx.shared_state.connections_mutex.unlock();

        const connection = conn orelse return error.ConnectionNotFound;

        var buffer: [4096]u8 = undefined;
        while (true) {
            const bytes_read = connection.stream.read(&buffer) catch |err| switch (err) {
                error.WouldBlock => break,
                else => return err,
            };

            if (bytes_read == 0) {
                closeConnection(ctx, fd);
                return;
            }

            try connection.read_buffer.appendSlice(connection.allocator, buffer[0..bytes_read]);

            // Check for complete HTTP request (double CRLF)
            if (mem.indexOf(u8, connection.read_buffer.items, "\r\n\r\n")) |_| {
                try processRequest(ctx, fd);
                break;
            }
        }
    }

    fn processRequest(ctx: WorkerContext, fd: i32) !void {
        ctx.shared_state.connections_mutex.lock();
        const conn = ctx.shared_state.connections.get(fd);
        ctx.shared_state.connections_mutex.unlock();

        const connection = conn orelse return error.ConnectionNotFound;

        var arena = std.heap.ArenaAllocator.init(ctx.allocator);
        defer arena.deinit();
        const req_allocator = arena.allocator();

        // Parse HTTP request
        var in_reader = std.io.Reader.fixed(connection.read_buffer.items);

        var write_buf: [4096]u8 = undefined;
        var out_writer = std.io.Writer.fixed(&write_buf);

        var server = http.Server.init(&in_reader, &out_writer);

        const raw_request = server.receiveHead() catch |err| {
            std.log.err("Failed to parse request: {any}", .{err});
            closeConnection(ctx, fd);
            return;
        };

        const path = try req_allocator.dupe(u8, raw_request.head.target);
        const method = raw_request.head.method;
        connection.keep_alive = raw_request.head.keep_alive;

        // Parse query parameters
        var query_params = std.StringHashMap([]const u8).init(req_allocator);
        if (mem.indexOfScalar(u8, path, '?')) |query_start| {
            const query_string = path[query_start + 1 ..];
            var param_iter = mem.splitScalar(u8, query_string, '&');
            while (param_iter.next()) |pair| {
                if (mem.indexOfScalar(u8, pair, '=')) |eq_pos| {
                    const key = pair[0..eq_pos];
                    const value = pair[eq_pos + 1 ..];

                    const key_buf = req_allocator.alloc(u8, key.len) catch continue;
                    const decoded_key = std.Uri.percentDecodeBackwards(key_buf, key);

                    const value_buf = req_allocator.alloc(u8, value.len) catch continue;
                    const decoded_value = std.Uri.percentDecodeBackwards(value_buf, value);

                    query_params.put(decoded_key, decoded_value) catch continue;
                }
            }
        }

        // TODO: Parse body for POST/PUT/PATCH
        const body: ?[]const u8 = null;

        var response = Response.init(req_allocator);
        defer response.deinit();

        var request = Request{
            .allocator = req_allocator,
            .raw_request = raw_request,
            .params = std.StringHashMap([]const u8).init(req_allocator),
            .query = query_params,
            .body_str = body,
            .remote_address = connection.address,
        };
        defer request.deinit();

        // Route the request
        const route_match = ctx.router.findRoute(req_allocator, method, path) catch |err| {
            std.log.err("Router error: {any}", .{err});
            response.setStatus(.internal_server_error);
            _ = response.send("Internal Server Error") catch {};
            try sendResponse(ctx, fd, &response);
            return;
        };

        if (route_match) |match| {
            var mut_match = match;
            defer mut_match.handlers.deinit(req_allocator);
            request.params = match.params;

            const HandlerTypes = mw.chain.Types(anyopaque);
            var chain = HandlerTypes.Next{ .handlers = match.handlers.items };
            chain.call(ctx.context, &request, &response) catch |err| {
                std.log.err("Handler error: {any}", .{err});

                if (ctx.error_handler) |handler| {
                    handler(err, &request, &response, ctx.context) catch |handler_err| {
                        std.log.err("Error handler failed: {any}", .{handler_err});
                        response.setStatus(.internal_server_error);
                        _ = response.send("Internal Server Error") catch {};
                    };
                } else {
                    response.setStatus(.internal_server_error);
                    _ = response.send("Internal Server Error") catch {};
                }
            };
        } else {
            response.setStatus(.not_found);
            _ = response.send("Not Found") catch {};
        }

        try sendResponse(ctx, fd, &response);
    }

    fn sendResponse(ctx: WorkerContext, fd: i32, response: *Response) !void {
        ctx.shared_state.connections_mutex.lock();
        const conn = ctx.shared_state.connections.get(fd);
        ctx.shared_state.connections_mutex.unlock();

        const connection = conn orelse return error.ConnectionNotFound;

        // Build HTTP response
        var response_builder: std.ArrayList(u8) = .{};
        defer response_builder.deinit(ctx.allocator);

        const status_line = try std.fmt.allocPrint(
            ctx.allocator,
            "HTTP/1.1 {d} {s}\r\n",
            .{ @intFromEnum(response.status), response.status.phrase() orelse "Unknown" },
        );
        defer ctx.allocator.free(status_line);
        try response_builder.appendSlice(ctx.allocator, status_line);

        // Add headers
        for (response.headers.items) |header| {
            const header_line = try std.fmt.allocPrint(
                ctx.allocator,
                "{s}: {s}\r\n",
                .{ header.name, header.value },
            );
            defer ctx.allocator.free(header_line);
            try response_builder.appendSlice(ctx.allocator, header_line);
        }

        // Add content-length
        if (response.body) |body| {
            const content_length = try std.fmt.allocPrint(
                ctx.allocator,
                "Content-Length: {d}\r\n",
                .{body.len},
            );
            defer ctx.allocator.free(content_length);
            try response_builder.appendSlice(ctx.allocator, content_length);
        }

        try response_builder.appendSlice(ctx.allocator, "\r\n");

        if (response.body) |body| {
            try response_builder.appendSlice(ctx.allocator, body);
        }

        // Queue for writing
        try connection.write_buffer.appendSlice(connection.allocator, response_builder.items);

        // Switch to write mode
        var event = std.os.linux.epoll_event{
            .events = std.os.linux.EPOLL.OUT | std.os.linux.EPOLL.ET,
            .data = .{ .fd = fd },
        };
        try posix.epoll_ctl(ctx.shared_state.epoll_fd, std.os.linux.EPOLL.CTL_MOD, fd, &event);
    }

    fn handleWrite(ctx: WorkerContext, fd: i32) !void {
        ctx.shared_state.connections_mutex.lock();
        const conn = ctx.shared_state.connections.get(fd);
        ctx.shared_state.connections_mutex.unlock();

        const connection = conn orelse return error.ConnectionNotFound;

        while (connection.write_buffer.items.len > 0) {
            const bytes_written = connection.stream.write(connection.write_buffer.items) catch |err| switch (err) {
                error.WouldBlock => break,
                else => return err,
            };

            if (bytes_written == 0) break;

            mem.copyForwards(u8, connection.write_buffer.items, connection.write_buffer.items[bytes_written..]);
            connection.write_buffer.shrinkRetainingCapacity(connection.write_buffer.items.len - bytes_written);
        }

        if (connection.write_buffer.items.len == 0) {
            if (connection.keep_alive) {
                // Reset for next request
                connection.read_buffer.clearRetainingCapacity();

                var event = std.os.linux.epoll_event{
                    .events = std.os.linux.EPOLL.IN | std.os.linux.EPOLL.ET,
                    .data = .{ .fd = fd },
                };
                try posix.epoll_ctl(ctx.shared_state.epoll_fd, std.os.linux.EPOLL.CTL_MOD, fd, &event);
            } else {
                closeConnection(ctx, fd);
            }
        }
    }

    fn closeConnection(ctx: WorkerContext, fd: i32) void {
        ctx.shared_state.connections_mutex.lock();
        defer ctx.shared_state.connections_mutex.unlock();

        if (ctx.shared_state.connections.fetchRemove(fd)) |kv| {
            const conn = kv.value;
            _ = posix.epoll_ctl(ctx.shared_state.epoll_fd, std.os.linux.EPOLL.CTL_DEL, fd, null) catch {};
            conn.deinit(ctx.allocator);
        }
    }

    fn handleConnection(conn: net.Server.Connection, router: *Router, context: *anyopaque, error_handler: ?ErrorHandlerFn) void {
        defer conn.stream.close();
        const gpa = std.heap.page_allocator;

        var arena = std.heap.ArenaAllocator.init(gpa);
        defer arena.deinit();
        _ = arena.allocator();

        var read_buffer: [MAX_HEADERS_SIZE]u8 = undefined;
        var write_buffer: [4096]u8 = undefined;

        var in_reader = conn.stream.reader(&read_buffer);
        var out_writer = conn.stream.writer(&write_buffer);
        var server = http.Server.init(in_reader.interface(), &out_writer.interface);

        while (true) {
            var req_arena = std.heap.ArenaAllocator.init(gpa);
            defer req_arena.deinit();
            const req_allocator = req_arena.allocator();

            var raw_request = server.receiveHead() catch |err| switch (err) {
                error.HttpConnectionClosing, error.HttpRequestTruncated => break,
                else => {
                    std.log.err("failed to receive request head: {any}", .{err});
                    break;
                },
            };

            // Copy the target path immediately to prevent corruption from buffer reuse
            const path = req_allocator.dupe(u8, raw_request.head.target) catch |err| {
                std.log.err("failed to copy path: {any}", .{err});
                _ = raw_request.respond("", .{ .status = .internal_server_error }) catch {};
                continue;
            };
            const method = raw_request.head.method;

            // Parse query string from the target path
            var query_params = std.StringHashMap([]const u8).init(req_allocator);
            if (mem.indexOfScalar(u8, path, '?')) |query_start| {
                const query_string = path[query_start + 1 ..];
                var param_iter = mem.splitScalar(u8, query_string, '&');
                while (param_iter.next()) |pair| {
                    if (mem.indexOfScalar(u8, pair, '=')) |eq_pos| {
                        const key = pair[0..eq_pos];
                        const value = pair[eq_pos + 1 ..];

                        // Allocate buffers for decoded strings
                        const key_buf = req_allocator.alloc(u8, key.len) catch continue;
                        const decoded_key = std.Uri.percentDecodeBackwards(key_buf, key);

                        const value_buf = req_allocator.alloc(u8, value.len) catch continue;
                        const decoded_value = std.Uri.percentDecodeBackwards(value_buf, value);

                        query_params.put(decoded_key, decoded_value) catch continue;
                    }
                }
            }

            // Conditionally read the request body based on HTTP method
            const body = blk: {
                // Allocate a temporary buffer for the reader
                const tmp_buf = req_allocator.alloc(u8, 4096) catch break :blk null;

                // Check if the method is designed to carry a body
                if (method == .POST or method == .PUT or method == .PATCH) {
                    // Use readerExpectNone to get the body reader for methods with bodies
                    var reader = raw_request.readerExpectNone(tmp_buf);

                    // Read the body with size limit to prevent DoS attacks
                    break :blk reader.allocRemaining(req_allocator, .limited(MAX_BODY_SIZE)) catch |err| {
                        std.log.err("failed to read request body: {any}", .{err});
                        break :blk null;
                    };
                } else {
                    // For GET, HEAD, DELETE, etc., don't read the body
                    _ = raw_request.readerExpectNone(tmp_buf);
                    break :blk null;
                }
            };

            var response = Response.init(req_allocator);
            defer response.deinit();

            var request = Request{
                .allocator = req_allocator,
                .raw_request = raw_request,
                .params = std.StringHashMap([]const u8).init(req_allocator),
                .query = query_params,
                .body_str = body,
                .remote_address = conn.address,
            };
            defer request.deinit();

            const route_match = router.findRoute(req_allocator, method, path) catch |err| {
                std.log.err("router error: {any}", .{err});
                _ = raw_request.respond("", .{ .status = .internal_server_error }) catch {};
                continue;
            };

            if (route_match) |match| {
                var mut_match = match;
                defer mut_match.handlers.deinit(req_allocator);
                request.params = match.params;

                const HandlerTypes = mw.chain.Types(anyopaque);
                var chain = HandlerTypes.Next{ .handlers = match.handlers.items };
                chain.call(context, &request, &response) catch |err| {
                    std.log.err("handler error: {any}", .{err});

                    // Call custom error handler if provided, otherwise use default behavior
                    if (error_handler) |handler| {
                        handler(err, &request, &response, context) catch |handler_err| {
                            std.log.err("error handler failed: {any}", .{handler_err});
                            response.setStatus(.internal_server_error);
                            _ = response.send("Internal Server Error") catch {};
                        };
                    } else {
                        // Default error handling
                        response.setStatus(.internal_server_error);
                        _ = response.send("Internal Server Error") catch {};
                    }
                };
            } else {
                response.setStatus(.not_found);
                _ = response.send("Not Found") catch {};
            }

            raw_request.respond(response.body orelse "", .{
                .status = response.status,
                .extra_headers = response.headers.items,
            }) catch |err| {
                std.log.err("failed to send response: {any}", .{err});
            };

            if (!raw_request.head.keep_alive) break;
        }
    }
};
