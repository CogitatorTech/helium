const std = @import("std");
const helium = @import("helium");
const Request = helium.Request;
const Response = helium.Response;
const ServerMode = helium.Mode;
const AppContext = struct {
    request_count: std.atomic.Value(u64),
    start_time: i64,
    mode: ServerMode,
};
fn homeHandler(ctx: *AppContext, _: *Request, res: *Response) !void {
    const count = ctx.request_count.fetchAdd(1, .monotonic) + 1;
    const uptime = std.time.timestamp() - ctx.start_time;
    const mode_str = switch (ctx.mode) {
        .thread_pool => "Thread Pool (thread-per-connection)",
        .minimal_threadpool => "Minimal Thread Pool (event-driven I/O)",
    };
    const html = try std.fmt.allocPrint(res.allocator,
        \\<!DOCTYPE html>
        \\<html>
        \\<head><title>Server Modes Demo</title></head>
        \\<body>
        \\  <h1>Helium Server Modes Demo</h1>
        \\  <h2>Current Configuration:</h2>
        \\  <ul>
        \\    <li><strong>Mode:</strong> {s}</li>
        \\    <li><strong>Requests Served:</strong> {d}</li>
        \\    <li><strong>Uptime:</strong> {d} seconds</li>
        \\  </ul>
        \\  <h2>Server Modes:</h2>
        \\  <h3>1. Thread Pool (thread_pool)</h3>
        \\  <p>Traditional thread-per-connection model. Each connection gets its own thread from a pool.</p>
        \\  <p><strong>Best for:</strong> Low to moderate concurrency, simple deployments</p>
        \\  <h3>2. Minimal Thread Pool (minimal_threadpool)</h3>
        \\  <p>Event-driven I/O with a minimal thread pool. Recommended for high concurrency.</p>
        \\  <p><strong>Best for:</strong> High concurrency, production deployments</p>
        \\  <h2>Try these endpoints:</h2>
        \\  <ul>
        \\    <li><a href="/status">Server Status</a></li>
        \\    <li><a href="/stress">Stress Test Endpoint</a></li>
        \\    <li><a href="/sleep">Slow Endpoint (1s delay)</a></li>
        \\  </ul>
        \\  <h2>Load Testing:</h2>
        \\  <pre>
        \\    # Test with Apache Bench (if installed)
        \\    ab -n 1000 -c 10 http://localhost:3000/status
        \\
        \\    # Test with curl
        \\    for i in {{1..10}}; do curl http://localhost:3000/status & done; wait
        \\  </pre>
        \\</body>
        \\</html>
    , .{ mode_str, count, uptime });
    try res.headers.append(res.allocator, .{ .name = "content-type", .value = "text/html" });
    res.body = html;
}
fn statusHandler(ctx: *AppContext, _: *Request, res: *Response) !void {
    const count = ctx.request_count.load(.monotonic);
    const uptime = std.time.timestamp() - ctx.start_time;
    try res.sendJson(.{
        .status = "healthy",
        .mode = @tagName(ctx.mode),
        .uptime_seconds = uptime,
        .total_requests = count,
        .requests_per_second = if (uptime > 0) @as(f64, @floatFromInt(count)) / @as(f64, @floatFromInt(uptime)) else 0.0,
    });
}
fn stressHandler(ctx: *AppContext, _: *Request, res: *Response) !void {
    _ = ctx.request_count.fetchAdd(1, .monotonic);
    var sum: u64 = 0;
    var i: u64 = 0;
    while (i < 10000) : (i += 1) {
        sum +%= i * i;
    }
    try res.sendJson(.{
        .message = "Stress test completed",
        .result = sum,
    });
}
fn sleepHandler(ctx: *AppContext, _: *Request, res: *Response) !void {
    _ = ctx.request_count.fetchAdd(1, .monotonic);
    std.Thread.sleep(1 * std.time.ns_per_s);
    try res.sendJson(.{
        .message = "Sleep completed (1 second)",
        .note = "In minimal_threadpool mode, other requests can be processed during this sleep",
    });
}
fn infoHandler(_: *AppContext, _: *Request, res: *Response) !void {
    const html =
        \\<!DOCTYPE html>
        \\<html>
        \\<head><title>Server Mode Information</title></head>
        \\<body>
        \\  <h1>Understanding Server Modes</h1>
        \\
        \\  <h2>Thread Pool Mode (Default)</h2>
        \\  <p>This is the traditional approach where each connection is handled by a dedicated thread from a pool.</p>
        \\  <ul>
        \\    <li><strong>Pros:</strong> Simple, predictable, good for moderate load</li>
        \\    <li><strong>Cons:</strong> Limited scalability due to thread overhead</li>
        \\    <li><strong>Use when:</strong> You have moderate concurrency needs or want simplicity</li>
        \\  </ul>
        \\
        \\  <h2>Minimal Thread Pool Mode (Recommended)</h2>
        \\  <p>This uses event-driven I/O with a small pool of worker threads.</p>
        \\  <ul>
        \\    <li><strong>Pros:</strong> High scalability, efficient resource usage</li>
        \\    <li><strong>Cons:</strong> Slightly more complex internally</li>
        \\    <li><strong>Use when:</strong> You need to handle high concurrency (1000+ connections)</li>
        \\  </ul>
        \\
        \\  <h2>How to Set the Mode</h2>
        \\  <pre>
        \\    var app = helium.App(void).init(allocator, {});
        \\    defer app.deinit();
        \\
        \\    // Set the server mode
        \\    app.setMode(.minimal_threadpool);
        \\
        \\    try app.listen(3000);
        \\  </pre>
        \\
        \\  <a href="/">Back to Home</a>
        \\</body>
        \\</html>
    ;
    try res.headers.append(res.allocator, .{ .name = "content-type", .value = "text/html" });
    res.body = html;
}
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    var server_mode: ServerMode = .thread_pool;
    if (args.len > 1) {
        if (std.mem.eql(u8, args[1], "minimal_threadpool") or std.mem.eql(u8, args[1], "minimal")) {
            server_mode = .minimal_threadpool;
        } else if (std.mem.eql(u8, args[1], "thread_pool") or std.mem.eql(u8, args[1], "pool")) {
            server_mode = .thread_pool;
        } else {
            std.log.err("Unknown server mode: {s}", .{args[1]});
            std.log.info("Available modes: thread_pool, minimal_threadpool", .{});
            return error.InvalidServerMode;
        }
    }
    const context = AppContext{
        .request_count = std.atomic.Value(u64).init(0),
        .start_time = std.time.timestamp(),
        .mode = server_mode,
    };
    var app = helium.App(AppContext).init(allocator, context);
    defer app.deinit();
    app.setMode(server_mode);
    try app.use(helium.cors.any(AppContext));
    try app.use(helium.log.common(AppContext));
    try app.get("/", homeHandler);
    try app.get("/status", statusHandler);
    try app.get("/stress", stressHandler);
    try app.get("/sleep", sleepHandler);
    try app.get("/info", infoHandler);
    const mode_str = switch (server_mode) {
        .thread_pool => "Thread Pool",
        .minimal_threadpool => "Minimal Thread Pool (Event-Driven)",
    };
    std.log.info("", .{});
    std.log.info("===========================================", .{});
    std.log.info("  Helium Server Modes Demo", .{});
    std.log.info("===========================================", .{});
    std.log.info("", .{});
    std.log.info("Server Mode: {s}", .{mode_str});
    std.log.info("Listening on: http://127.0.0.1:3000", .{});
    std.log.info("", .{});
    std.log.info("To change mode, run:", .{});
    std.log.info("  ./e9_server_modes thread_pool", .{});
    std.log.info("  ./e9_server_modes minimal_threadpool", .{});
    std.log.info("", .{});
    try app.listen(3000);
}
