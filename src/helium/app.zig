const std = @import("std");
const mem = std.mem;
const http = std.http;
const mw = @import("./middleware.zig");
const Server = @import("./server.zig").Server;
const ServerMode = @import("./server.zig").ServerMode;
const Router = @import("./router.zig").Router;

pub const Request = @import("./http_types.zig").Request;
pub const Response = @import("./http_types.zig").Response;
pub const cors = @import("./cors.zig");
pub const log = @import("./log.zig");
pub const static = @import("./static.zig");

pub const ErrorHandlerFn = @import("./server.zig").ErrorHandlerFn;

pub const Mode = ServerMode;

pub fn App(comptime ContextType: type) type {
    const HandlerTypes = mw.chain.Types(ContextType);

    return struct {
        allocator: mem.Allocator,
        router: Router,
        context: ContextType,
        error_handler: ?ErrorHandlerFn = null,
        server_mode: ServerMode = .thread_pool,

        const Self = @This();
        pub const Next = HandlerTypes.Next;
        pub const Handler = HandlerTypes.Handler;
        pub const HandlerFn = HandlerTypes.HandlerFn;
        pub const MiddlewareFn = HandlerTypes.MiddlewareFn;

        const ErasedHandler = mw.chain.Types(anyopaque).Handler;

        pub const Group = struct {
            app: *Self,
            prefix: []const u8,
            middleware: std.ArrayListUnmanaged(MiddlewareFn),

            pub fn use(self: *Group, middleware: MiddlewareFn) !void {
                try self.middleware.append(self.app.allocator, middleware);
            }

            pub fn get(self: *Group, path: []const u8, handler: HandlerFn) !void {
                const full_path = try self.buildPath(path);
                defer self.app.allocator.free(full_path);
                try self.addRouteWithMiddleware(.GET, full_path, handler);
            }

            pub fn post(self: *Group, path: []const u8, handler: HandlerFn) !void {
                const full_path = try self.buildPath(path);
                defer self.app.allocator.free(full_path);
                try self.addRouteWithMiddleware(.POST, full_path, handler);
            }

            pub fn put(self: *Group, path: []const u8, handler: HandlerFn) !void {
                const full_path = try self.buildPath(path);
                defer self.app.allocator.free(full_path);
                try self.addRouteWithMiddleware(.PUT, full_path, handler);
            }

            pub fn delete(self: *Group, path: []const u8, handler: HandlerFn) !void {
                const full_path = try self.buildPath(path);
                defer self.app.allocator.free(full_path);
                try self.addRouteWithMiddleware(.DELETE, full_path, handler);
            }

            pub fn patch(self: *Group, path: []const u8, handler: HandlerFn) !void {
                const full_path = try self.buildPath(path);
                defer self.app.allocator.free(full_path);
                try self.addRouteWithMiddleware(.PATCH, full_path, handler);
            }

            pub fn head(self: *Group, path: []const u8, handler: HandlerFn) !void {
                const full_path = try self.buildPath(path);
                defer self.app.allocator.free(full_path);
                try self.addRouteWithMiddleware(.HEAD, full_path, handler);
            }

            pub fn options(self: *Group, path: []const u8, handler: HandlerFn) !void {
                const full_path = try self.buildPath(path);
                defer self.app.allocator.free(full_path);
                try self.addRouteWithMiddleware(.OPTIONS, full_path, handler);
            }

            fn buildPath(self: *Group, path: []const u8) ![]const u8 {
                const needs_slash = self.prefix.len > 0 and self.prefix[self.prefix.len - 1] != '/' and (path.len == 0 or path[0] != '/');

                if (path.len == 0 or (path.len == 1 and path[0] == '/')) {
                    return self.app.allocator.dupe(u8, self.prefix);
                }

                const total_len = self.prefix.len + path.len + (if (needs_slash) @as(usize, 1) else 0);
                const full_path = try self.app.allocator.alloc(u8, total_len);

                @memcpy(full_path[0..self.prefix.len], self.prefix);
                var offset = self.prefix.len;

                if (needs_slash) {
                    full_path[offset] = '/';
                    offset += 1;
                }

                @memcpy(full_path[offset..], path);
                return full_path;
            }

            fn addRouteWithMiddleware(self: *Group, method: http.Method, path: []const u8, handler: HandlerFn) !void {
                const total_handlers = self.middleware.items.len + 1;
                var handlers = try self.app.allocator.alloc(Handler, total_handlers);

                for (self.middleware.items, 0..) |mw_fn, i| {
                    handlers[i] = .{ .middleware = mw_fn };
                }

                handlers[self.middleware.items.len] = .{ .endpoint = handler };

                var erased_handlers = try self.app.allocator.alloc(ErasedHandler, handlers.len);
                for (handlers, 0..) |h, i| {
                    erased_handlers[i] = switch (h) {
                        .endpoint => |f| .{ .endpoint = @as(*const fn (*anyopaque, *Request, *Response) anyerror!void, @ptrCast(f)) },
                        .middleware => |f| .{ .middleware = @as(*const fn (*anyopaque, *Request, *Response, *anyopaque) anyerror!void, @ptrCast(f)) },
                    };
                }

                self.app.allocator.free(handlers);
                try self.app.router.add(method, path, erased_handlers);
            }
        };

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

        pub fn setMode(self: *Self, mode: ServerMode) void {
            self.server_mode = mode;
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

        pub fn group(self: *Self, prefix: []const u8, configureFn: *const fn (*Group) anyerror!void) !void {
            var grp = Group{
                .app = self,
                .prefix = prefix,
                .middleware = .{},
            };
            defer grp.middleware.deinit(self.allocator);

            try configureFn(&grp);
        }

        pub fn setErrorHandler(self: *Self, handler: *const fn (err: anyerror, *Request, *Response, *ContextType) anyerror!void) void {
            const erased_handler = @as(ErrorHandlerFn, @ptrCast(handler));
            self.error_handler = erased_handler;
        }

        pub fn listen(self: *Self, port: u16) !void {
            var server = Server{
                .router = &self.router,
                .context = &self.context,
                .allocator = self.allocator,
                .port = port,
                .error_handler = self.error_handler,
                .mode = self.server_mode,
            };
            try server.listen();
        }
    };
}
