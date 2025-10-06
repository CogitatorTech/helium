const std = @import("std");
const mem = std.mem;
const http = std.http;
const mw = @import("./middleware.zig");

const HandlerUnion = mw.chain.Types(anyopaque).Handler;

const Node = struct {
    allocator: mem.Allocator,
    children: std.StringHashMap(*Node),
    param_child: ?*Node,
    param_name: ?[]const u8,
    handlers: ?[]const HandlerUnion,

    fn init(allocator: mem.Allocator) !*Node {
        const node = try allocator.create(Node);
        node.* = .{
            .allocator = allocator,
            .children = std.StringHashMap(*Node).init(allocator),
            .param_child = null,
            .param_name = null,
            .handlers = null,
        };
        return node;
    }

    fn deinit(self: *Node) void {
        // Free the string keys that were duplicated
        var key_it = self.children.keyIterator();
        while (key_it.next()) |key| {
            self.allocator.free(key.*);
        }

        var it = self.children.valueIterator();
        while (it.next()) |child| {
            child.*.deinit();
        }
        self.children.deinit();
        if (self.param_child) |child| {
            child.deinit();
        }

        // Free the param_name if it was duplicated
        if (self.param_name) |name| {
            self.allocator.free(name);
        }

        // Free the handlers array if it exists
        if (self.handlers) |handlers| {
            self.allocator.free(handlers);
        }

        self.allocator.destroy(self);
    }
};

pub const Router = struct {
    allocator: mem.Allocator,
    trees: std.AutoHashMap(http.Method, *Node),
    global_middleware: std.ArrayListUnmanaged(HandlerUnion),

    pub const RouteMatch = struct {
        handlers: std.ArrayListUnmanaged(HandlerUnion),
        params: std.StringHashMap([]const u8),
    };

    pub fn init(allocator: mem.Allocator) Router {
        return .{
            .allocator = allocator,
            .trees = std.AutoHashMap(http.Method, *Node).init(allocator),
            .global_middleware = .{},
        };
    }

    pub fn deinit(self: *Router) void {
        var it = self.trees.valueIterator();
        while (it.next()) |tree| {
            tree.*.deinit();
        }
        self.trees.deinit();
        self.global_middleware.deinit(self.allocator);
    }

    pub fn use(self: *Router, middleware: anytype) !void {
        try self.global_middleware.append(self.allocator, .{ .middleware = middleware });
    }

    pub fn add(self: *Router, method: http.Method, path: []const u8, handlers: []const HandlerUnion) !void {
        const gop = try self.trees.getOrPut(method);
        if (!gop.found_existing) {
            gop.value_ptr.* = try Node.init(self.allocator);
        }
        var current = gop.value_ptr.*;

        if (path.len == 1 and path[0] == '/') {
            current.handlers = handlers;
            return;
        }

        var it = mem.splitScalar(u8, path, '/');
        while (it.next()) |segment| {
            if (segment.len == 0) continue;

            if (segment[0] == ':') {
                const param_name = segment[1..];
                if (current.param_child == null) {
                    current.param_child = try Node.init(self.allocator);
                    current.param_name = try self.allocator.dupe(u8, param_name);
                }
                current = current.param_child.?;
            } else {
                if (!current.children.contains(segment)) {
                    const dupe_segment = try self.allocator.dupe(u8, segment);
                    try current.children.put(dupe_segment, try Node.init(self.allocator));
                }
                current = current.children.get(segment).?;
            }
        }
        current.handlers = handlers;
    }

    pub fn findRoute(self: *Router, req_allocator: mem.Allocator, method: http.Method, path: []const u8) !?RouteMatch {
        const root = self.trees.get(method) orelse return null;
        var current = root;
        var params = std.StringHashMap([]const u8).init(req_allocator);

        if (path.len == 1 and path[0] == '/') {
            if (current.handlers) |h| return self.prepareMatch(h, params);
            return null;
        }

        var it = mem.splitScalar(u8, path, '/');
        while (it.next()) |segment| {
            if (segment.len == 0) continue;

            if (current.children.get(segment)) |next_node| {
                current = next_node;
            } else if (current.param_child) |param_node| {
                try params.put(current.param_name.?, segment);
                current = param_node;
            } else {
                params.deinit();
                return null;
            }
        }

        if (current.handlers) |h| return self.prepareMatch(h, params);

        params.deinit();
        return null;
    }

    fn prepareMatch(self: *Router, handlers: []const HandlerUnion, params: std.StringHashMap([]const u8)) !?RouteMatch {
        var all_handlers: std.ArrayListUnmanaged(HandlerUnion) = .{};
        try all_handlers.appendSlice(params.allocator, self.global_middleware.items);
        try all_handlers.appendSlice(params.allocator, handlers);

        return RouteMatch{
            .handlers = all_handlers,
            .params = params,
        };
    }
};
