const std = @import("std");
const mem = std.mem;
const net = std.net;
const http = std.http;

const Router = @import("./router.zig").Router;
const http_types = @import("./http_types.zig");
const mw = @import("./middleware.zig");

const Request = http_types.Request;
const Response = http_types.Response;

pub const Server = struct {
    router: *Router,
    context: *anyopaque,
    allocator: mem.Allocator,
    port: u16,

    const MAX_HEADERS_SIZE = 8192;
    const NUM_WORKERS = 4;

    pub fn listen(self: *Server) !void {
        const address = try net.Address.parseIp("127.0.0.1", self.port);
        var tcp_server = try net.Address.listen(address, .{ .reuse_address = true });
        defer tcp_server.deinit();

        std.log.info("Server listening on http://127.0.0.1:{d}", .{self.port});

        var thread_pool: std.Thread.Pool = undefined;
        try thread_pool.init(.{
            .allocator = self.allocator,
            .n_jobs = NUM_WORKERS,
        });
        defer thread_pool.deinit();

        while (true) {
            const conn = try tcp_server.accept();
            try thread_pool.spawn(handleConnection, .{ conn, self.router, self.context });
        }
    }

    fn handleConnection(conn: net.Server.Connection, router: *Router, context: *anyopaque) void {
        const gpa = std.heap.page_allocator;
        var arena = std.heap.ArenaAllocator.init(gpa);
        defer arena.deinit();
        const allocator = arena.allocator();

        var server = http.Server.init(conn, allocator.alloc(u8, MAX_HEADERS_SIZE) catch @panic("oom"));
        defer allocator.free(server.read_buffer);

        while (true) {
            var req_arena = std.heap.ArenaAllocator.init(gpa);
            defer req_arena.deinit();
            const req_allocator = req_arena.allocator();

            var raw_request = server.receiveHead() catch |err| switch (err) {
                error.HttpConnectionClosing, error.HttpRequestTruncated => break,
                else => {
                    std.log.err("failed to receive request head: {}", .{err});
                    break;
                },
            };

            const body = blk: {
                var reader = raw_request.reader() catch |err| {
                    std.log.err("Failed to get request reader: {}", .{err});
                    break :blk null;
                };
                var body_buf = std.ArrayList(u8).init(req_allocator);
                _ = reader.readAllArrayList(&body_buf, std.math.maxInt(usize)) catch {
                    break :blk null;
                };
                break :blk body_buf.toOwnedSlice() catch null;
            };

            var response = Response.init(req_allocator);
            defer response.deinit();

            var request = Request{
                .allocator = req_allocator,
                .raw_request = raw_request,
                .params = std.StringHashMap([]const u8).init(req_allocator),
                .body_str = body,
                .remote_address = conn.address,
            };
            defer request.deinit();

            const path = raw_request.head.target;
            const method = raw_request.head.method;

            const route_match = router.findRoute(req_allocator, method, path) catch |err| {
                std.log.err("router error: {}", .{err});
                _ = raw_request.respond("", .{ .status = .internal_server_error }) catch {};
                continue;
            };

            if (route_match) |match| {
                defer match.handlers.deinit();
                request.params = match.params;

                // Corrected line: Use the `anyopaque` version of the middleware types.
                const HandlerTypes = mw.Types(anyopaque);
                var chain = HandlerTypes.Next{ .handlers = match.handlers.items };
                chain.call(context, &request, &response) catch |err| {
                    std.log.err("handler error: {}", .{err});
                    response.setStatus(.internal_server_error);
                    _ = response.send("Internal Server Error") catch {};
                };
            } else {
                response.setStatus(.not_found);
                _ = response.send("Not Found") catch {};
            }

            raw_request.respond(response.body orelse "", .{
                .status = response.status,
                .extra_headers = response.headers.items,
            }) catch |err| {
                std.log.err("failed to send response: {}", .{err});
            };

            if (!raw_request.head.keep_alive) break;
        }
    }
};
