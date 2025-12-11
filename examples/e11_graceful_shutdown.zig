const std = @import("std");
const helium = @import("helium");
const Request = helium.Request;
const Response = helium.Response;

const AppContext = struct {
    start_time: i64,
    request_count: std.atomic.Value(u64),
};

/// Simple endpoint
fn homeHandler(_: *AppContext, _: *Request, res: *Response) !void {
    const html =
        \\<!DOCTYPE html>
        \\<html>
        \\<head><title>Graceful Shutdown Demo</title></head>
        \\<body>
        \\  <h1>Graceful Shutdown Demo</h1>
        \\  
        \\  <h2>Features:</h2>
        \\  <ul>
        \\    <li>Server tracks active connections</li>
        \\    <li>Shutdown can be requested via <code>requestShutdown()</code></li>
        \\    <li>Active connections complete before server exits</li>
        \\  </ul>
        \\  
        \\  <h2>Endpoints:</h2>
        \\  <ul>
        \\    <li><a href="/">GET /</a> - This page</li>
        \\    <li><a href="/slow">GET /slow</a> - Simulates a slow request (2 seconds)</li>
        \\    <li><a href="/status">GET /status</a> - Server status</li>
        \\  </ul>
        \\  
        \\  <h2>Testing Graceful Shutdown:</h2>
        \\  <pre>
        \\    # In terminal 1: Start the server
        \\    zig build run-e11_graceful_shutdown
        \\    
        \\    # In terminal 2: Start a slow request
        \\    curl http://localhost:3000/slow &
        \\    
        \\    # In terminal 2: Send SIGINT to server (Ctrl+C)
        \\    # The slow request should complete before server exits
        \\  </pre>
        \\</body>
        \\</html>
    ;
    try res.headers.append(res.allocator, .{ .name = "content-type", .value = "text/html" });
    res.body = html;
}

/// Slow endpoint to test graceful shutdown
fn slowHandler(ctx: *AppContext, _: *Request, res: *Response) !void {
    _ = ctx.request_count.fetchAdd(1, .monotonic);

    // Simulate a slow operation
    std.Thread.sleep(2 * std.time.ns_per_s);

    try res.sendJson(.{
        .message = "Slow request completed!",
        .duration = "2 seconds",
    });
}

/// Status endpoint
fn statusHandler(ctx: *AppContext, _: *Request, res: *Response) !void {
    const uptime = std.time.timestamp() - ctx.start_time;
    const requests = ctx.request_count.load(.monotonic);

    try res.sendJson(.{
        .status = "running",
        .uptime_seconds = uptime,
        .total_requests = requests,
    });
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const context = AppContext{
        .start_time = std.time.timestamp(),
        .request_count = std.atomic.Value(u64).init(0),
    };

    var app = helium.App(AppContext).init(allocator, context);
    defer app.deinit();

    try app.use(helium.log.common(AppContext));

    try app.get("/", homeHandler);
    try app.get("/slow", slowHandler);
    try app.get("/status", statusHandler);

    std.log.info("", .{});
    std.log.info("===========================================", .{});
    std.log.info("  Graceful Shutdown Demo", .{});
    std.log.info("===========================================", .{});
    std.log.info("", .{});
    std.log.info("Server listening on: http://127.0.0.1:3000", .{});
    std.log.info("", .{});
    std.log.info("Press Ctrl+C to initiate graceful shutdown", .{});
    std.log.info("", .{});
    std.log.info("Test with:", .{});
    std.log.info("  curl http://localhost:3000/slow &", .{});
    std.log.info("  # Then press Ctrl+C to shutdown", .{});
    std.log.info("  # The slow request should complete first", .{});
    std.log.info("", .{});

    try app.listen(3000);
}
