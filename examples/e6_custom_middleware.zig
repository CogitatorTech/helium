const std = @import("std");
const helium = @import("helium");
const Request = helium.Request;
const Response = helium.Response;
const App = helium.App(AppContext);
const AppContext = struct {
    request_count: std.atomic.Value(u64),
    start_time: i64,
};
fn timingMiddleware(ctx: *AppContext, req: *Request, res: *Response, next: *anyopaque) !void {
    const start = std.time.milliTimestamp();
    const Next = App.Next;
    const next_fn = @as(*Next, @ptrCast(@alignCast(next)));
    try next_fn.call(ctx, req, res);
    const duration = std.time.milliTimestamp() - start;
    std.log.info("[Timing] {s} {s} completed in {}ms", .{ @tagName(req.raw_request.head.method), req.raw_request.head.target, duration });
    const timing_header = try std.fmt.allocPrint(res.allocator, "{d}ms", .{duration});
    try res.headers.append(res.allocator, .{ .name = "X-Response-Time", .value = timing_header });
}
fn requestCounterMiddleware(ctx: *AppContext, req: *Request, res: *Response, next: *anyopaque) !void {
    const count = ctx.request_count.fetchAdd(1, .monotonic) + 1;
    std.log.info("[Counter] Request #{d}: {s} {s}", .{ count, @tagName(req.raw_request.head.method), req.raw_request.head.target });
    const Next = App.Next;
    const next_fn = @as(*Next, @ptrCast(@alignCast(next)));
    try next_fn.call(ctx, req, res);
    const count_header = try std.fmt.allocPrint(res.allocator, "{d}", .{count});
    try res.headers.append(res.allocator, .{ .name = "X-Request-Count", .value = count_header });
}
fn requestIdMiddleware(ctx: *AppContext, req: *Request, res: *Response, next: *anyopaque) !void {
    var prng = std.Random.DefaultPrng.init(@intCast(std.time.microTimestamp()));
    const random = prng.random();
    const request_id = random.int(u32);
    const id_str = try std.fmt.allocPrint(res.allocator, "req-{x}", .{request_id});
    try res.headers.append(res.allocator, .{ .name = "X-Request-Id", .value = id_str });
    const Next = App.Next;
    const next_fn = @as(*Next, @ptrCast(@alignCast(next)));
    try next_fn.call(ctx, req, res);
}
fn securityHeadersMiddleware(ctx: *AppContext, req: *Request, res: *Response, next: *anyopaque) !void {
    const Next = App.Next;
    const next_fn = @as(*Next, @ptrCast(@alignCast(next)));
    try next_fn.call(ctx, req, res);
    try res.headers.append(res.allocator, .{ .name = "X-Content-Type-Options", .value = "nosniff" });
    try res.headers.append(res.allocator, .{ .name = "X-Frame-Options", .value = "DENY" });
    try res.headers.append(res.allocator, .{ .name = "X-XSS-Protection", .value = "1; mode=block" });
}
fn homeHandler(_: *AppContext, _: *Request, res: *Response) !void {
    try res.sendJson(.{
        .message = "Welcome to Custom Middleware Demo",
        .note = "Check response headers to see middleware in action",
    });
}
fn statsHandler(ctx: *AppContext, _: *Request, res: *Response) !void {
    const uptime = std.time.timestamp() - ctx.start_time;
    const total_requests = ctx.request_count.load(.monotonic);
    try res.sendJson(.{
        .uptime_seconds = uptime,
        .total_requests = total_requests,
        .average_requests_per_second = if (uptime > 0) @as(f64, @floatFromInt(total_requests)) / @as(f64, @floatFromInt(uptime)) else 0.0,
    });
}
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    const context = AppContext{
        .request_count = std.atomic.Value(u64).init(0),
        .start_time = std.time.timestamp(),
    };
    var app = App.init(allocator, context);
    defer app.deinit();
    try app.use(requestIdMiddleware);
    try app.use(requestCounterMiddleware);
    try app.use(timingMiddleware);
    try app.use(securityHeadersMiddleware);
    try app.use(helium.cors.any(AppContext));
    try app.use(helium.log.common(AppContext));
    try app.get("/", homeHandler);
    try app.get("/stats", statsHandler);
    std.log.info("Server starting on http://127.0.0.1:3000", .{});
    std.log.info("Try: curl -v http://localhost:3000/", .{});
    try app.listen(3000);
}
