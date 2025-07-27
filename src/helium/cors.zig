const std = @import("std");
const mw = @import("./middleware.zig");
const http_types = @import("./http_types.zig");

const Request = http_types.Request;
const Response = http_types.Response;

pub fn any(comptime ContextType: type) mw.Types(ContextType).MiddlewareFn {
    return struct {
        fn handler(ctx: *ContextType, req: *Request, res: *Response, next_opaque: *anyopaque) !void {
            const Next = mw.Types(ContextType).Next;
            const next = @as(*Next, @ptrCast(@alignCast(next_opaque)));

            try res.headers.append(.{ .name = "Access-Control-Allow-Origin", .value = "*" });
            try res.headers.append(.{ .name = "Access-Control-Allow-Methods", .value = "GET, POST, PUT, DELETE, OPTIONS" });
            try res.headers.append(.{ .name = "Access-Control-Allow-Headers", .value = "Content-Type, Authorization" });

            if (req.raw_request.head.method == .OPTIONS) {
                res.status = .no_content;
                return;
            }

            try next.call(ctx, req, res);
        }
    }.handler;
}
