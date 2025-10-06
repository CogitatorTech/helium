const std = @import("std");
const helium = @import("helium");

const App = helium.App(void);
const Request = helium.Request;
const Response = helium.Response;

// Example middleware that logs requests
fn loggerMiddleware(ctx: *void, req: *Request, res: *Response, next: *anyopaque) !void {
    std.debug.print("[Logger] {s} {s}\n", .{ @tagName(req.raw_request.head.method), req.raw_request.head.target });
    const Next = App.Next;
    const next_fn = @as(*Next, @ptrCast(@alignCast(next)));
    try next_fn.call(ctx, req, res);
}

// Authentication middleware (group-scoped)
// In a real app, you would check the Authorization header from the request
fn authMiddleware(ctx: *void, req: *Request, res: *Response, next: *anyopaque) !void {
    // Simplified example: check if path contains a query param "token"
    const has_auth = req.query.contains("token");

    if (!has_auth) {
        std.debug.print("[Auth] Unauthorized request to {s}\n", .{req.raw_request.head.target});
        res.setStatus(.unauthorized);
        try res.sendJson(.{ .@"error" = "Unauthorized - missing token parameter" });
        return;
    }

    std.debug.print("[Auth] Request authorized\n", .{});
    const Next = App.Next;
    const next_fn = @as(*Next, @ptrCast(@alignCast(next)));
    try next_fn.call(ctx, req, res);
}

// Rate limiting middleware (group-scoped)
fn rateLimitMiddleware(ctx: *void, req: *Request, res: *Response, next: *anyopaque) !void {
    std.debug.print("[RateLimit] Checking rate limit for {s}\n", .{req.raw_request.head.target});
    const Next = App.Next;
    const next_fn = @as(*Next, @ptrCast(@alignCast(next)));
    try next_fn.call(ctx, req, res);
}

// Route handlers
fn homeHandler(_: *void, _: *Request, res: *Response) !void {
    try res.sendJson(.{ .message = "Welcome to Helium API" });
}

fn apiV1StatusHandler(_: *void, _: *Request, res: *Response) !void {
    try res.sendJson(.{ .version = "1.0", .status = "ok" });
}

fn getUsersHandler(_: *void, _: *Request, res: *Response) !void {
    try res.sendJson(.{
        .users = [_]struct { id: u32, name: []const u8 }{
            .{ .id = 1, .name = "Alice" },
            .{ .id = 2, .name = "Bob" },
        },
    });
}

fn getUserByIdHandler(_: *void, req: *Request, res: *Response) !void {
    const user_id = req.params.get("id") orelse "unknown";
    try res.sendJson(.{ .id = user_id, .name = "Sample User" });
}

fn createUserHandler(_: *void, _: *Request, res: *Response) !void {
    res.setStatus(.created);
    try res.sendJson(.{ .message = "User created", .id = 123 });
}

fn getPostsHandler(_: *void, _: *Request, res: *Response) !void {
    try res.sendJson(.{
        .posts = [_]struct { id: u32, title: []const u8 }{
            .{ .id = 1, .title = "First Post" },
            .{ .id = 2, .title = "Second Post" },
        },
    });
}

fn adminDashboardHandler(_: *void, _: *Request, res: *Response) !void {
    try res.sendJson(.{ .message = "Admin Dashboard - requires auth" });
}

fn adminUsersHandler(_: *void, _: *Request, res: *Response) !void {
    try res.sendJson(.{ .message = "Admin Users Management - requires auth" });
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var app = App.init(allocator, {});
    defer app.deinit();

    // Global middleware - applies to all routes
    try app.use(loggerMiddleware);

    // Root route
    try app.get("/", homeHandler);

    // API v1 group with rate limiting
    try app.group("/api/v1", struct {
        fn configure(group: *App.Group) !void {
            // Add rate limiting middleware to all /api/v1 routes
            try group.use(rateLimitMiddleware);

            // Routes in this group
            try group.get("/status", apiV1StatusHandler);

            // Nested users endpoints
            try group.get("/users", getUsersHandler);
            try group.get("/users/:id", getUserByIdHandler);
            try group.post("/users", createUserHandler);

            // Posts endpoints
            try group.get("/posts", getPostsHandler);
        }
    }.configure);

    // Admin group with authentication
    try app.group("/admin", struct {
        fn configure(group: *App.Group) !void {
            // Add authentication middleware to all /admin routes
            try group.use(authMiddleware);

            // Admin routes
            try group.get("/dashboard", adminDashboardHandler);
            try group.get("/users", adminUsersHandler);
        }
    }.configure);

    std.debug.print("🚀 Server starting on http://localhost:3000\n", .{});
    std.debug.print("\nExample routes:\n", .{});
    std.debug.print("  GET  /                    - Home\n", .{});
    std.debug.print("  GET  /api/v1/status       - API Status (with rate limiting)\n", .{});
    std.debug.print("  GET  /api/v1/users        - Get Users (with rate limiting)\n", .{});
    std.debug.print("  GET  /api/v1/users/:id    - Get User by ID (with rate limiting)\n", .{});
    std.debug.print("  POST /api/v1/users        - Create User (with rate limiting)\n", .{});
    std.debug.print("  GET  /api/v1/posts        - Get Posts (with rate limiting)\n", .{});
    std.debug.print("  GET  /admin/dashboard     - Admin Dashboard (requires token query param)\n", .{});
    std.debug.print("  GET  /admin/users         - Admin Users (requires token query param)\n", .{});
    std.debug.print("\nTry with curl:\n", .{});
    std.debug.print("  curl http://localhost:3000/api/v1/users\n", .{});
    std.debug.print("  curl 'http://localhost:3000/admin/dashboard?token=secret'\n", .{});
    std.debug.print("\n", .{});

    try app.listen(3000);
}
