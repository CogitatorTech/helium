const std = @import("std");
const mem = std.mem;
const http = std.http;
const mw = @import("./middleware.zig");
const Server = @import("./server.zig").Server;
const Router = @import("./router.zig").Router;

pub const Request = @import("./http_types.zig").Request;
pub const Response = @import("./http_types.zig").Response;
pub const cors = @import("./cors.zig");
pub const log = @import("./log.zig");
pub const static = @import("./static.zig");

pub fn App(comptime ContextType: type) type {
    const HandlerTypes = mw.Types(ContextType);

    return struct {
        allocator: mem.Allocator,
        router: Router,
        context: ContextType,

        const Self = @This();
        pub const Next = HandlerTypes.Next;
        pub const Handler = HandlerTypes.Handler;
        pub const HandlerFn = HandlerTypes.HandlerFn;
        pub const MiddlewareFn = HandlerTypes.MiddlewareFn;

        const ErasedHandler = mw.Types(anyopaque).Handler;

        pub fn init(allocator: mem.Allocator, context: ContextType) Self {
            return Self{
                .allocator = allocator,
                .router = Router.init(allocator),
                .context = context,
            };
        }

        pub fn deinit(self: *Self) void {
            self.router.deinit();
        }

        pub fn use(self: *Self, middleware: MiddlewareFn) !void {
            const erased_fn = @as(*const fn (*anyopaque, *Request, *Response, *anyopaque) anyerror!void, @ptrCast(middleware));
            try self.router.use(erased_fn);
        }

        pub fn get(self: *Self, path: []const u8, handler: HandlerFn) !void {
            try self.addRoute(.GET, path, &[_]Handler{.{ .endpoint = handler }});
        }

        pub fn post(self: *Self, path: []const u8, handler: HandlerFn) !void {
            try self.addRoute(.POST, path, &[_]Handler{.{ .endpoint = handler }});
        }

        pub fn put(self: *Self, path: []const u8, handler: HandlerFn) !void {
            try self.addRoute(.PUT, path, &[_]Handler{.{ .endpoint = handler }});
        }

        pub fn delete(self: *Self, path: []const u8, handler: HandlerFn) !void {
            try self.addRoute(.DELETE, path, &[_]Handler{.{ .endpoint = handler }});
        }

        pub fn patch(self: *Self, path: []const u8, handler: HandlerFn) !void {
            try self.addRoute(.PATCH, path, &[_]Handler{.{ .endpoint = handler }});
        }

        pub fn head(self: *Self, path: []const u8, handler: HandlerFn) !void {
            try self.addRoute(.HEAD, path, &[_]Handler{.{ .endpoint = handler }});
        }

        pub fn options(self: *Self, path: []const u8, handler: HandlerFn) !void {
            try self.addRoute(.OPTIONS, path, &[_]Handler{.{ .endpoint = handler }});
        }

        fn addRoute(self: *Self, method: http.Method, path: []const u8, handlers: []const Handler) !void {
            var erased_handlers = try self.allocator.alloc(ErasedHandler, handlers.len);
            for (handlers, 0..) |h, i| {
                erased_handlers[i] = switch (h) {
                    .endpoint => |f| .{ .endpoint = @as(*const fn (*anyopaque, *Request, *Response) anyerror!void, @ptrCast(f)) },
                    .middleware => |f| .{ .middleware = @as(*const fn (*anyopaque, *Request, *Response, *anyopaque) anyerror!void, @ptrCast(f)) },
                };
            }
            try self.router.add(method, path, erased_handlers);
        }

        pub fn listen(self: *Self, port: u16) !void {
            var server = Server{
                .router = &self.router,
                .context = &self.context,
                .allocator = self.allocator,
                .port = port,
            };
            try server.listen();
        }
    };
}
