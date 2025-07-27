const std = @import("std");
const mw = @import("./middleware.zig");
const http_types = @import("./http_types.zig");

const Request = http_types.Request;
const Response = http_types.Response;

pub fn common(comptime ContextType: type) mw.Types(ContextType).MiddlewareFn {
    return struct {
        fn handler(ctx: *ContextType, req: *Request, res: *Response, next_opaque: *anyopaque) !void {
            const Next = mw.Types(ContextType).Next;
            const next = @as(*Next, @ptrCast(@alignCast(next_opaque)));

            const start_time = std.time.timestamp();
            try next.call(ctx, req, res);
            const end_time = std.time.timestamp();
            const duration_ms = (end_time - start_time) * 1000;

            const remote_addr = req.remote_address;
            const status = @intFromEnum(res.status);
            const method = @tagName(req.raw_request.head.method);
            const target = req.raw_request.head.target;
            const version = @tagName(req.raw_request.head.version);

            std.log.info("{any} \"{s} {s} {s}\" {d} {d}ms", .{
                remote_addr,
                method,
                target,
                version,
                status,
                duration_ms,
            });
        }
    }.handler;
}
