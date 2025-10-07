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

pub const ErrorHandlerFn = *const fn (err: anyerror, *Request, *Response, *anyopaque) anyerror!void;

pub const ServerMode = enum {
    thread_pool,
    minimal_threadpool,
};

pub const Server = struct {
    router: *Router,
    context: *anyopaque,
    allocator: mem.Allocator,
    port: u16,
    error_handler: ?ErrorHandlerFn = null,
    mode: ServerMode = .thread_pool,
    num_workers: usize = 2,

    const MAX_HEADERS_SIZE = 8192;
    const MAX_BODY_SIZE = 100 * 1024 * 1024; // Increase limit but enforce streaming
    const NUM_WORKERS = 4;

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

    fn listenMinimalThreadPool(self: *Server) !void {
        const address = try net.Address.parseIp("127.0.0.1", self.port);
        var tcp_server = try address.listen(.{ .reuse_address = true });
        defer tcp_server.deinit();

        std.log.info("Server listening on http://127.0.0.1:{d} (minimal thread pool mode)", .{self.port});
        std.log.info("Using {d} worker threads with epoll-based event loop", .{self.num_workers});

        var shared_state = try WorkerSharedState.init(self.allocator, tcp_server.stream.handle);
        defer shared_state.deinit();

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
            const flags = try posix.fcntl(server_fd, posix.F.GETFL, 0);
            const nonblock_flag = std.os.linux.O{ .NONBLOCK = true };
            _ = try posix.fcntl(server_fd, posix.F.SETFL, flags | @as(u32, @bitCast(nonblock_flag)));

            const epoll_fd = try posix.epoll_create1(0);

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
                    acceptConnections(ctx) catch |err| {
                        std.log.err("Failed to accept connection: {any}", .{err});
                    };
                } else {
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
        const server_stream = net.Stream{ .handle = ctx.shared_state.server_fd };
        var tcp_server = net.Server{ .stream = server_stream, .listen_address = undefined };

        while (true) {
            const conn = tcp_server.accept() catch |err| switch (err) {
                error.WouldBlock => return,
                else => return err,
            };

            const fd = conn.stream.handle;

            const flags = try posix.fcntl(fd, posix.F.GETFL, 0);
            const nonblock_flag = std.os.linux.O{ .NONBLOCK = true };
            _ = try posix.fcntl(fd, posix.F.SETFL, flags | @as(u32, @bitCast(nonblock_flag)));

            const state = try ConnectionState.init(ctx.allocator, fd, conn.stream, conn.address);

            ctx.shared_state.connections_mutex.lock();
            defer ctx.shared_state.connections_mutex.unlock();

            try ctx.shared_state.connections.put(fd, state);

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

        var in_reader = std.io.Reader.fixed(connection.read_buffer.items);

        var write_buf: [4096]u8 = undefined;
        var out_writer = std.io.Writer.fixed(&write_buf);

        var server = http.Server.init(&in_reader, &out_writer);

        var raw_request = server.receiveHead() catch |err| {
            std.log.err("Failed to parse request: {any}", .{err});
            closeConnection(ctx, fd);
            return;
        };

        const path = try req_allocator.dupe(u8, raw_request.head.target);
        const method = raw_request.head.method;
        connection.keep_alive = raw_request.head.keep_alive;

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

        // Set up body reader with streaming support
        var body_reader: ?http_types.BodyReader = null;
        const tmp_buf = req_allocator.alloc(u8, 4096) catch {
            std.log.err("failed to allocate temp buffer", .{});
            closeConnection(ctx, fd);
            return;
        };

        var raw_reader_storage: ?@TypeOf(raw_request.readerExpectNone(tmp_buf)) = null;
        if (method == .POST or method == .PUT or method == .PATCH) {
            raw_reader_storage = raw_request.readerExpectNone(tmp_buf);
            body_reader = http_types.BodyReader.initFromReader(raw_reader_storage.?.any(), MAX_BODY_SIZE);
        } else {
            _ = raw_request.readerExpectNone(tmp_buf);
        }

        var response = Response.init(req_allocator);
        defer response.deinit();

        var request = Request{
            .allocator = req_allocator,
            .raw_request = raw_request,
            .params = std.StringHashMap([]const u8).init(req_allocator),
            .query = query_params,
            .body_reader = body_reader,
            .remote_address = connection.address,
        };
        defer request.deinit();

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

        var response_builder: std.ArrayList(u8) = .{};
        defer response_builder.deinit(ctx.allocator);

        const status_line = try std.fmt.allocPrint(
            ctx.allocator,
            "HTTP/1.1 {d} {s}\r\n",
            .{ @intFromEnum(response.status), response.status.phrase() orelse "Unknown" },
        );
        defer ctx.allocator.free(status_line);
        try response_builder.appendSlice(ctx.allocator, status_line);

        for (response.headers.items) |header| {
            const header_line = try std.fmt.allocPrint(
                ctx.allocator,
                "{s}: {s}\r\n",
                .{ header.name, header.value },
            );
            defer ctx.allocator.free(header_line);
            try response_builder.appendSlice(ctx.allocator, header_line);
        }

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

        try connection.write_buffer.appendSlice(connection.allocator, response_builder.items);

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
        const req_allocator = arena.allocator();

        var read_buffer: [MAX_HEADERS_SIZE]u8 = undefined;
        var write_buffer: [4096]u8 = undefined;

        var in_reader = conn.stream.reader(&read_buffer);
        var out_writer = conn.stream.writer(&write_buffer);
        var server = http.Server.init(in_reader.any(), &out_writer.any());

        var raw_request = server.receiveHead() catch |err| {
            std.log.err("Failed to parse request: {any}", .{err});
            return;
        };

        const path = req_allocator.dupe(u8, raw_request.head.target) catch {
            std.log.err("Failed to allocate path", .{});
            return;
        };
        const method = raw_request.head.method;

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

        // Set up body reader with streaming support
        var body_reader: ?http_types.BodyReader = null;
        const tmp_buf = req_allocator.alloc(u8, 4096) catch {
            std.log.err("failed to allocate temp buffer", .{});
            _ = raw_request.respond("", .{ .status = .internal_server_error }) catch {};
            return;
        };

        var raw_reader_storage: ?@TypeOf(raw_request.readerExpectNone(tmp_buf)) = null;
        if (method == .POST or method == .PUT or method == .PATCH) {
            raw_reader_storage = raw_request.readerExpectNone(tmp_buf);
            body_reader = http_types.BodyReader.initFromReader(raw_reader_storage.?.any(), MAX_BODY_SIZE);
        } else {
            _ = raw_request.readerExpectNone(tmp_buf);
        }

        var response = Response.init(req_allocator);
        defer response.deinit();

        var request = Request{
            .allocator = req_allocator,
            .raw_request = raw_request,
            .params = std.StringHashMap([]const u8).init(req_allocator),
            .query = query_params,
            .body_reader = body_reader,
            .remote_address = conn.address,
        };
        defer request.deinit();

        const route_match = router.findRoute(req_allocator, method, path) catch |err| {
            std.log.err("router error: {any}", .{err});
            _ = raw_request.respond("", .{ .status = .internal_server_error }) catch {};
            return;
        };

        if (route_match) |match| {
            var mut_match = match;
            defer mut_match.handlers.deinit(req_allocator);
            request.params = match.params;

            const HandlerTypes = mw.chain.Types(anyopaque);
            var chain = HandlerTypes.Next{ .handlers = match.handlers.items };
            chain.call(context, &request, &response) catch |err| {
                std.log.err("handler error: {any}", .{err});

                if (error_handler) |handler| {
                    handler(err, &request, &response, context) catch |handler_err| {
                        std.log.err("error handler failed: {any}", .{handler_err});
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

        _ = raw_request.respond(response.body orelse "", .{
            .status = response.status,
            .extra_headers = response.headers.items,
        }) catch |err| {
            std.log.err("failed to send response: {any}", .{err});
        };
    }
};
