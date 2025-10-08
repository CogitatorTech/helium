const std = @import("std");
const mw = @import("./middleware.zig");
const http_types = @import("./http_types.zig");
const Request = http_types.Request;
const Response = http_types.Response;
pub fn common(comptime ContextType: type) mw.chain.Types(ContextType).MiddlewareFn {
    return struct {
        fn handler(ctx: *ContextType, req: *Request, res: *Response, next_opaque: *anyopaque) !void {
            const Next = mw.chain.Types(ContextType).Next;
            const next = @as(*Next, @ptrCast(@alignCast(next_opaque)));
            const start_time = std.time.nanoTimestamp();
            try next.call(ctx, req, res);
            const end_time = std.time.nanoTimestamp();
            const duration_ns = end_time - start_time;
            const duration_ms = @as(f64, @floatFromInt(duration_ns)) / 1_000_000.0;
            var remote_addr_buffer: [256]u8 = undefined;
            const remote_addr_str = std.fmt.bufPrint(&remote_addr_buffer, "{any}", .{req.remote_address}) catch "unknown";
            const status = @intFromEnum(res.status);
            const method = @tagName(req.raw_request.head.method);
            const target = req.raw_request.head.target;
            const version = @tagName(req.raw_request.head.version);
            std.log.info("{s} \"{s} {s} {s}\" {d} {d:.2}ms", .{
                remote_addr_str,
                method,
                target,
                version,
                status,
                duration_ms,
            });
        }
    }.handler;
}
