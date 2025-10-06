const std = @import("std");
const http_types = @import("./http_types.zig");

pub const Request = http_types.Request;
pub const Response = http_types.Response;

pub const chain = struct {
    pub fn Types(comptime ContextType: type) type {
        return struct {
            const Self = @This();
            pub const Next = Self.NextStruct;

            pub const HandlerFn = *const fn (*ContextType, *Request, *Response) anyerror!void;
            pub const MiddlewareFn = *const fn (*ContextType, *Request, *Response, *anyopaque) anyerror!void;

            pub const Handler = union(enum) {
                endpoint: HandlerFn,
                middleware: MiddlewareFn,
            };

            pub const NextStruct = struct {
                handlers: []const Handler,
                index: usize = 0,

                pub fn call(self: *NextStruct, ctx: *ContextType, req: *Request, res: *Response) !void {
                    if (self.index >= self.handlers.len) {
                        return;
                    }

                    const current_handler = self.handlers[self.index];
                    var next_caller = NextStruct{
                        .handlers = self.handlers,
                        .index = self.index + 1,
                    };

                    switch (current_handler) {
                        .endpoint => |f| try f(ctx, req, res),
                        .middleware => |f| try f(ctx, req, res, &next_caller),
                    }
                }
            };
        };
    }
};
