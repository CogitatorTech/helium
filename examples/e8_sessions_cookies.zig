const std = @import("std");
const helium = @import("helium");

const Request = helium.Request;
const Response = helium.Response;

const Session = struct {
    id: []const u8,
    user_id: ?u32,
    username: ?[]const u8,
    created_at: i64,
    last_accessed: i64,
};

const AppContext = struct {
    sessions: std.StringHashMap(Session),
    mutex: std.Thread.Mutex,
    allocator: std.mem.Allocator,
};

fn generateSessionId(allocator: std.mem.Allocator) ![]const u8 {
    var prng = std.Random.DefaultPrng.init(@intCast(std.time.microTimestamp()));
    const random = prng.random();

    const id = random.int(u64);
    return try std.fmt.allocPrint(allocator, "sess_{x:0>16}", .{id});
}

fn getOrCreateSession(ctx: *AppContext, req: *Request, res: *Response) !*Session {
    ctx.mutex.lock();
    defer ctx.mutex.unlock();

    const addr_str = try std.fmt.allocPrint(ctx.allocator, "{any}", .{req.remote_address});
    defer ctx.allocator.free(addr_str);

    if (ctx.sessions.getPtr(addr_str)) |session| {
        session.last_accessed = std.time.timestamp();
        return session;
    }

    const session_id = try generateSessionId(ctx.allocator);
    const now = std.time.timestamp();

    const persistent_addr = try ctx.allocator.dupe(u8, addr_str);
    try ctx.sessions.put(persistent_addr, Session{
        .id = session_id,
        .user_id = null,
        .username = null,
        .created_at = now,
        .last_accessed = now,
    });

    const cookie = try std.fmt.allocPrint(res.allocator, "session_id={s}; Path=/; HttpOnly; Max-Age=3600", .{session_id});
    try res.headers.append(res.allocator, .{ .name = "set-cookie", .value = cookie });

    return ctx.sessions.getPtr(persistent_addr).?;
}

fn homeHandler(_: *AppContext, _: *Request, res: *Response) !void {
    const html =
        \\<!DOCTYPE html>
        \\<html>
        \\<head><title>Sessions and Cookies Demo</title></head>
        \\<body>
        \\  <h1>Helium Sessions and Cookies Demo</h1>
        \\  <h2>Endpoints:</h2>
        \\  <ul>
        \\    <li><a href="/session">View Session</a></li>
        \\    <li><a href="/login">Login (sets session)</a></li>
        \\    <li><a href="/profile">Profile (requires login)</a></li>
        \\    <li><a href="/logout">Logout</a></li>
        \\    <li><a href="/set-cookie">Set Custom Cookie</a></li>
        \\  </ul>
        \\  <h2>Note:</h2>
        \\  <p>This demo uses your IP address to track sessions (simplified approach).
        \\     In production, you would parse Cookie headers to identify sessions.</p>
        \\  <h2>Try with curl:</h2>
        \\  <pre>
        \\    # Get a session (your session is based on your IP)
        \\    curl http://localhost:3000/session
        \\
        \\    # Login
        \\    curl http://localhost:3000/login
        \\
        \\    # Access profile
        \\    curl http://localhost:3000/profile
        \\
        \\    # Logout
        \\    curl http://localhost:3000/logout
        \\  </pre>
        \\</body>
        \\</html>
    ;

    try res.headers.append(res.allocator, .{ .name = "content-type", .value = "text/html" });
    res.body = html;
}

fn sessionHandler(ctx: *AppContext, req: *Request, res: *Response) !void {
    const session = try getOrCreateSession(ctx, req, res);

    try res.sendJson(.{
        .session_id = session.id,
        .user_id = session.user_id,
        .username = session.username,
        .created_at = session.created_at,
        .last_accessed = session.last_accessed,
    });
}

fn loginHandler(ctx: *AppContext, req: *Request, res: *Response) !void {
    const session = try getOrCreateSession(ctx, req, res);

    ctx.mutex.lock();
    defer ctx.mutex.unlock();

    session.user_id = 123;

    const username = try ctx.allocator.dupe(u8, "john_doe");
    if (session.username) |old_username| {
        ctx.allocator.free(old_username);
    }
    session.username = username;

    std.log.info("User logged in: session_id={s}", .{session.id});

    try res.sendJson(.{
        .success = true,
        .message = "Logged in successfully",
        .user_id = session.user_id,
        .username = session.username,
    });
}

fn profileHandler(ctx: *AppContext, req: *Request, res: *Response) !void {
    const session = try getOrCreateSession(ctx, req, res);

    if (session.user_id == null) {
        res.setStatus(.unauthorized);
        try res.sendJson(.{
            .success = false,
            .message = "Not logged in. Please visit /login first",
        });
        return;
    }

    try res.sendJson(.{
        .success = true,
        .user_id = session.user_id,
        .username = session.username,
        .session_age_seconds = std.time.timestamp() - session.created_at,
    });
}

fn logoutHandler(ctx: *AppContext, req: *Request, res: *Response) !void {
    const addr_str = try std.fmt.allocPrint(ctx.allocator, "{any}", .{req.remote_address});
    defer ctx.allocator.free(addr_str);

    ctx.mutex.lock();
    defer ctx.mutex.unlock();

    if (ctx.sessions.fetchRemove(addr_str)) |kv| {
        ctx.allocator.free(kv.key);
        if (kv.value.username) |username| {
            ctx.allocator.free(username);
        }
    }

    const cookie = "session_id=; Path=/; HttpOnly; Max-Age=0";
    try res.headers.append(res.allocator, .{ .name = "set-cookie", .value = cookie });

    try res.sendJson(.{
        .success = true,
        .message = "Logged out successfully",
    });
}

fn setCookieHandler(_: *AppContext, _: *Request, res: *Response) !void {
    try res.headers.append(res.allocator, .{ .name = "set-cookie", .value = "user_preference=dark_mode; Path=/; Max-Age=86400" });
    try res.headers.append(res.allocator, .{ .name = "set-cookie", .value = "language=en; Path=/; Max-Age=86400" });

    try res.sendJson(.{
        .success = true,
        .message = "Cookies set successfully",
        .cookies = [_][]const u8{ "user_preference=dark_mode", "language=en" },
    });
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const context = AppContext{
        .sessions = std.StringHashMap(Session).init(allocator),
        .mutex = .{},
        .allocator = allocator,
    };

    var app = helium.App(AppContext).init(allocator, context);
    defer {
        var iter = app.context.sessions.iterator();
        while (iter.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            if (entry.value_ptr.username) |username| {
                allocator.free(username);
            }
        }
        app.context.sessions.deinit();
        app.deinit();
    }

    try app.use(helium.cors.any(AppContext));
    try app.use(helium.log.common(AppContext));

    try app.get("/", homeHandler);
    try app.get("/session", sessionHandler);
    try app.get("/login", loginHandler);
    try app.get("/profile", profileHandler);
    try app.get("/logout", logoutHandler);
    try app.get("/set-cookie", setCookieHandler);

    std.log.info("Server starting on http://127.0.0.1:3000", .{});
    std.log.info("", .{});
    std.log.info("This example demonstrates session management and cookies.", .{});
    std.log.info("Each visitor gets a unique session tracked via cookies.", .{});

    try app.listen(3000);
}
