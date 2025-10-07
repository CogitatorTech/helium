const std = @import("std");
const helium = @import("helium");

const Request = helium.Request;
const Response = helium.Response;

fn searchHandler(_: *void, req: *Request, res: *Response) !void {
    const query = req.query.get("q");
    const page_str = req.query.get("page");
    const limit_str = req.query.get("limit");
    const sort = req.query.get("sort");

    const page = if (page_str) |p| std.fmt.parseInt(u32, p, 10) catch 1 else 1;
    const limit = if (limit_str) |l| std.fmt.parseInt(u32, l, 10) catch 10 else 10;

    try res.sendJson(.{
        .query = query orelse "",
        .page = page,
        .limit = limit,
        .sort = sort orelse "relevance",
        .total_results = 42,
        .message = "Search results would appear here",
    });
}

fn customHeadersHandler(_: *void, _: *Request, res: *Response) !void {
    try res.headers.append(res.allocator, .{ .name = "X-Custom-Header", .value = "Helium-Framework" });
    try res.headers.append(res.allocator, .{ .name = "X-Request-Id", .value = "12345-abcde" });
    try res.headers.append(res.allocator, .{ .name = "X-Rate-Limit", .value = "100" });
    try res.headers.append(res.allocator, .{ .name = "X-Rate-Limit-Remaining", .value = "99" });

    try res.sendJson(.{
        .message = "Check the response headers!",
        .hint = "Use curl -v to see response headers",
    });
}

fn filterHandler(_: *void, req: *Request, res: *Response) !void {
    const category = req.query.get("category");
    const min_price_str = req.query.get("min_price");
    const max_price_str = req.query.get("max_price");
    const in_stock_str = req.query.get("in_stock");

    const min_price = if (min_price_str) |p| std.fmt.parseFloat(f32, p) catch 0.0 else 0.0;
    const max_price = if (max_price_str) |p| std.fmt.parseFloat(f32, p) catch 99999.0 else 99999.0;
    const in_stock = if (in_stock_str) |s| std.mem.eql(u8, s, "true") else false;

    try res.sendJson(.{
        .filters = .{
            .category = category orelse "all",
            .price_range = .{
                .min = min_price,
                .max = max_price,
            },
            .in_stock = in_stock,
        },
        .message = "Filters applied successfully",
    });
}

fn headersInfoHandler(_: *void, req: *Request, res: *Response) !void {
    try res.sendJson(.{
        .message = "Request information",
        .method = @tagName(req.raw_request.head.method),
        .path = req.raw_request.head.target,
        .version = @tagName(req.raw_request.head.version),
        .remote_address = try std.fmt.allocPrint(res.allocator, "{any}", .{req.remote_address}),
        .note = "Request headers are processed internally by the server",
    });
}

fn homeHandler(_: *void, _: *Request, res: *Response) !void {
    const html =
        \\<!DOCTYPE html>
        \\<html>
        \\<head><title>Query Parameters and Headers Demo</title></head>
        \\<body>
        \\  <h1>Helium Query Parameters and Headers Demo</h1>
        \\  <h2>Try these endpoints:</h2>
        \\  <ul>
        \\    <li><a href="/search?q=helium&page=1&limit=20&sort=date">Search with parameters</a></li>
        \\    <li><a href="/custom-headers">Get custom response headers</a></li>
        \\    <li><a href="/filter?category=electronics&min_price=10&max_price=100&in_stock=true">Filter example</a></li>
        \\    <li><a href="/headers-info">View your request headers</a></li>
        \\  </ul>
        \\  <h2>Try with curl:</h2>
        \\  <pre>
        \\    curl 'http://localhost:3000/search?q=helium&page=2&limit=5'
        \\    curl -v 'http://localhost:3000/custom-headers'
        \\    curl -H "User-Agent: MyApp/1.0" 'http://localhost:3000/headers-info'
        \\  </pre>
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

    var app = helium.App(void).init(allocator, {});
    defer app.deinit();

    try app.use(helium.cors.any(void));
    try app.use(helium.log.common(void));

    try app.get("/", homeHandler);
    try app.get("/search", searchHandler);
    try app.get("/custom-headers", customHeadersHandler);
    try app.get("/filter", filterHandler);
    try app.get("/headers-info", headersInfoHandler);

    std.log.info("Server starting on http://127.0.0.1:3000", .{});
    std.log.info("Example: curl 'http://localhost:3000/search?q=helium&page=2&limit=5'", .{});

    try app.listen(3000);
}
