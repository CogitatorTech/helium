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

pub const AsyncServer = struct {
    router: *Router,
    context: *anyopaque,
    allocator: mem.Allocator,
    port: u16,
    error_handler: ?ErrorHandlerFn = null,
    epoll_fd: i32,
    running: bool,
    connections: std.AutoHashMap(i32, *ConnectionState),

    const MAX_HEADERS_SIZE = 8192;
    const MAX_BODY_SIZE = 10 * 1024 * 1024;
    const MAX_EVENTS = 128;

    const ConnectionState = struct {
        fd: i32,
        stream: net.Stream,
        address: net.Address,
        read_buffer: std.ArrayList(u8),
        write_buffer: std.ArrayList(u8),
        parser_state: ParserState,
        keep_alive: bool,
        allocator: mem.Allocator,

        const ParserState = enum {
            reading_headers,
            reading_body,
            ready_to_process,
            writing_response,
        };

        fn init(allocator: mem.Allocator, fd: i32, stream: net.Stream, address: net.Address) !*ConnectionState {
            const state = try allocator.create(ConnectionState);
            state.* = .{
                .fd = fd,
                .stream = stream,
                .address = address,
                .read_buffer = .{},
                .write_buffer = .{},
                .parser_state = .reading_headers,
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

    pub fn init(allocator: mem.Allocator, router: *Router, context: *anyopaque, port: u16) !AsyncServer {
        const epoll_fd = try posix.epoll_create1(0);

        return AsyncServer{
            .allocator = allocator,
            .router = router,
            .context = context,
            .port = port,
            .error_handler = null,
            .epoll_fd = epoll_fd,
            .running = false,
            .connections = std.AutoHashMap(i32, *ConnectionState).init(allocator),
        };
    }

    pub fn deinit(self: *AsyncServer) void {
        posix.close(self.epoll_fd);

        var it = self.connections.valueIterator();
        while (it.next()) |conn| {
            conn.*.deinit(self.allocator);
        }
        self.connections.deinit();
    }

    pub fn listen(self: *AsyncServer) !void {
        const address = try net.Address.parseIp("127.0.0.1", self.port);
        var tcp_server = try address.listen(.{ .reuse_address = true });
        defer tcp_server.deinit();

        const server_fd = tcp_server.stream.handle;
        const flags = try posix.fcntl(server_fd, posix.F.GETFL, 0);
        _ = try posix.fcntl(server_fd, posix.F.SETFL, flags | @as(u32, posix.O.NONBLOCK));

        var server_event = std.os.linux.epoll_event{
            .events = std.os.linux.EPOLL.IN | std.os.linux.EPOLL.ET,
            .data = .{ .fd = server_fd },
        };
        try posix.epoll_ctl(self.epoll_fd, std.os.linux.EPOLL.CTL_ADD, server_fd, &server_event);

        std.log.info("Async server listening on http://127.0.0.1:{d}", .{self.port});
        std.log.info("Using event-driven I/O model (epoll)", .{});

        self.running = true;
        var events: [MAX_EVENTS]std.os.linux.epoll_event = undefined;

        while (self.running) {
            const num_events = posix.epoll_wait(self.epoll_fd, &events, -1);

            for (events[0..num_events]) |event| {
                const fd = event.data.fd;

                if (fd == server_fd) {
                    self.acceptConnections(tcp_server) catch |err| {
                        std.log.err("Failed to accept connection: {}", .{err});
                    };
                } else {
                    if (event.events & std.os.linux.EPOLL.IN != 0) {
                        self.handleRead(fd) catch |err| {
                            std.log.err("Read error on fd {d}: {}", .{ fd, err });
                            self.closeConnection(fd);
                        };
                    }

                    if (event.events & std.os.linux.EPOLL.OUT != 0) {
                        self.handleWrite(fd) catch |err| {
                            std.log.err("Write error on fd {d}: {}", .{ fd, err });
                            self.closeConnection(fd);
                        };
                    }

                    if (event.events & (std.os.linux.EPOLL.ERR | std.os.linux.EPOLL.HUP) != 0) {
                        self.closeConnection(fd);
                    }
                }
            }
        }
    }

    fn acceptConnections(self: *AsyncServer, tcp_server: net.Server) !void {
        while (true) {
            const conn = tcp_server.accept() catch |err| switch (err) {
                error.WouldBlock => return,
                else => return err,
            };

            const fd = conn.stream.handle;

            const flags = try posix.fcntl(fd, posix.F.GETFL, 0);
            _ = try posix.fcntl(fd, posix.F.SETFL, flags | @as(u32, posix.O.NONBLOCK));

            const state = try ConnectionState.init(self.allocator, fd, conn.stream, conn.address);
            try self.connections.put(fd, state);

            var event = std.os.linux.epoll_event{
                .events = std.os.linux.EPOLL.IN | std.os.linux.EPOLL.ET,
                .data = .{ .fd = fd },
            };
            try posix.epoll_ctl(self.epoll_fd, std.os.linux.EPOLL.CTL_ADD, fd, &event);

            std.log.debug("Accepted connection from {}", .{conn.address});
        }
    }

    fn handleRead(self: *AsyncServer, fd: i32) !void {
        const conn = self.connections.get(fd) orelse return error.ConnectionNotFound;

        var buffer: [4096]u8 = undefined;
        while (true) {
            const bytes_read = conn.stream.read(&buffer) catch |err| switch (err) {
                error.WouldBlock => break,
                else => return err,
            };

            if (bytes_read == 0) {
                self.closeConnection(fd);
                return;
            }

            try conn.read_buffer.appendSlice(conn.allocator, buffer[0..bytes_read]);

            if (conn.parser_state == .reading_headers) {
                if (self.hasCompleteHeaders(conn.read_buffer.items)) {
                    conn.parser_state = .ready_to_process;
                    try self.processRequest(fd);
                    break;
                }
            }
        }
    }

    fn hasCompleteHeaders(self: *AsyncServer, data: []const u8) bool {
        _ = self;
        return mem.indexOf(u8, data, "\r\n\r\n") != null;
    }

    fn processRequest(self: *AsyncServer, fd: i32) !void {
        const conn = self.connections.get(fd) orelse return error.ConnectionNotFound;

        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const req_allocator = arena.allocator();

        const read_data = conn.read_buffer.items;

        var read_buf = try req_allocator.alloc(u8, MAX_HEADERS_SIZE);
        @memcpy(read_buf[0..@min(read_data.len, read_buf.len)], read_data[0..@min(read_data.len, read_buf.len)]);

        var write_buffer: std.ArrayList(u8) = .{};
        var in_reader = std.io.fixedBufferStream(read_buf);
        var out_writer = write_buffer.writer(req_allocator);

        var server = http.Server.init(in_reader.reader().any(), &out_writer.any());

        const raw_request = server.receiveHead() catch |err| {
            std.log.err("Failed to parse request: {}", .{err});
            self.closeConnection(fd);
            return;
        };

        const path = try req_allocator.dupe(u8, raw_request.head.target);
        const method = raw_request.head.method;
        conn.keep_alive = raw_request.head.keep_alive;

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

        const body: ?[]const u8 = null;

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

        const route_match = self.router.findRoute(req_allocator, method, path) catch |err| {
            std.log.err("Router error: {}", .{err});
            response.setStatus(.internal_server_error);
            _ = response.send("Internal Server Error") catch {};
            try self.sendResponse(fd, &response);
            return;
        };

        if (route_match) |match| {
            var mut_match = match;
            defer mut_match.handlers.deinit(req_allocator);
            request.params = match.params;

            const HandlerTypes = mw.chain.Types(anyopaque);
            var chain = HandlerTypes.Next{ .handlers = match.handlers.items };
            chain.call(self.context, &request, &response) catch |err| {
                std.log.err("Handler error: {}", .{err});

                if (self.error_handler) |handler| {
                    handler(err, &request, &response, self.context) catch |handler_err| {
                        std.log.err("Error handler failed: {}", .{handler_err});
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

        try self.sendResponse(fd, &response);
    }

    fn sendResponse(self: *AsyncServer, fd: i32, response: *Response) !void {
        const conn = self.connections.get(fd) orelse return error.ConnectionNotFound;

        var response_builder: std.ArrayList(u8) = .{};
        defer response_builder.deinit(self.allocator);

        const status_line = try std.fmt.allocPrint(
            self.allocator,
            "HTTP/1.1 {d} {s}\r\n",
            .{ @intFromEnum(response.status), response.status.phrase() orelse "Unknown" },
        );
        defer self.allocator.free(status_line);
        try response_builder.appendSlice(self.allocator, status_line);

        for (response.headers.items) |header| {
            const header_line = try std.fmt.allocPrint(
                self.allocator,
                "{s}: {s}\r\n",
                .{ header.name, header.value },
            );
            defer self.allocator.free(header_line);
            try response_builder.appendSlice(self.allocator, header_line);
        }

        if (response.body) |body| {
            const content_length = try std.fmt.allocPrint(
                self.allocator,
                "Content-Length: {d}\r\n",
                .{body.len},
            );
            defer self.allocator.free(content_length);
            try response_builder.appendSlice(self.allocator, content_length);
        }

        try response_builder.appendSlice(self.allocator, "\r\n");

        if (response.body) |body| {
            try response_builder.appendSlice(self.allocator, body);
        }

        try conn.write_buffer.appendSlice(conn.allocator, response_builder.items);
        conn.parser_state = .writing_response;

        var event = std.os.linux.epoll_event{
            .events = std.os.linux.EPOLL.OUT | std.os.linux.EPOLL.ET,
            .data = .{ .fd = fd },
        };
        try posix.epoll_ctl(self.epoll_fd, std.os.linux.EPOLL.CTL_MOD, fd, &event);
    }

    fn handleWrite(self: *AsyncServer, fd: i32) !void {
        const conn = self.connections.get(fd) orelse return error.ConnectionNotFound;

        while (conn.write_buffer.items.len > 0) {
            const bytes_written = conn.stream.write(conn.write_buffer.items) catch |err| switch (err) {
                error.WouldBlock => break,
                else => return err,
            };

            if (bytes_written == 0) break;

            std.mem.copyForwards(
                u8,
                conn.write_buffer.items,
                conn.write_buffer.items[bytes_written..],
            );
            conn.write_buffer.shrinkRetainingCapacity(conn.write_buffer.items.len - bytes_written);
        }

        if (conn.write_buffer.items.len == 0) {
            if (conn.keep_alive) {
                conn.read_buffer.clearRetainingCapacity();
                conn.parser_state = .reading_headers;

                var event = std.os.linux.epoll_event{
                    .events = std.os.linux.EPOLL.IN | std.os.linux.EPOLL.ET,
                    .data = .{ .fd = fd },
                };
                try posix.epoll_ctl(self.epoll_fd, std.os.linux.EPOLL.CTL_MOD, fd, &event);
            } else {
                self.closeConnection(fd);
            }
        }
    }

    fn closeConnection(self: *AsyncServer, fd: i32) void {
        if (self.connections.fetchRemove(fd)) |kv| {
            const conn = kv.value;
            _ = posix.epoll_ctl(self.epoll_fd, std.os.linux.EPOLL.CTL_DEL, fd, null) catch {};
            conn.deinit(self.allocator);
            std.log.debug("Closed connection fd={d}", .{fd});
        }
    }

    pub fn stop(self: *AsyncServer) void {
        self.running = false;
    }
};
