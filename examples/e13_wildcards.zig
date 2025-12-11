const std = @import("std");
const helium = @import("helium");
const Request = helium.Request;
const Response = helium.Response;

const AppContext = struct {
    start_time: i64,
};

/// Catch-all files handler - matches /files/*
fn filesHandler(_: *AppContext, req: *Request, res: *Response) !void {
    // The wildcard path is captured in the "*" parameter
    const wildcard_path = req.params.get("*") orelse "index.html";

    try res.sendJson(.{
        .endpoint = "files",
        .captured_path = wildcard_path,
        .message = "This would serve a file from the captured path",
        .example_uses = [_][]const u8{
            "GET /files/docs/readme.txt",
            "GET /files/images/logo.png",
            "GET /files/js/app.min.js",
        },
    });
}

/// Catch-all API handler - matches /api/v1/*
fn apiV1Handler(_: *AppContext, req: *Request, res: *Response) !void {
    const wildcard_path = req.params.get("*") orelse "";

    try res.sendJson(.{
        .endpoint = "api-v1",
        .captured_path = wildcard_path,
        .message = "API v1 catch-all route",
        .note = "This can be used for proxying or catch-all API routes",
    });
}

/// Catch-all handler for any unmatched routes
fn catchAllHandler(_: *AppContext, req: *Request, res: *Response) !void {
    const wildcard_path = req.params.get("*") orelse "/";

    res.status = .not_found;
    try res.sendJson(.{
        .@"error" = "Not Found",
        .path = wildcard_path,
        .message = "The requested resource was not found",
        .available_routes = [_][]const u8{
            "/",
            "/files/*",
            "/api/v1/*",
        },
    });
}

/// Home page with wildcard info
fn homeHandler(_: *AppContext, _: *Request, res: *Response) !void {
    const html =
        \\<!DOCTYPE html>
        \\<html>
        \\<head><title>Helium Wildcard Routes Demo</title></head>
        \\<body>
        \\  <h1>Wildcard Routes Demo</h1>
        \\  
        \\  <h2>Wildcard Pattern: <code>*</code></h2>
        \\  <p>Wildcard routes match any remaining path segments and capture them in the <code>"*"</code> parameter.</p>
        \\  
        \\  <h2>Available Routes:</h2>
        \\  <ul>
        \\    <li><strong>GET /</strong> - This home page</li>
        \\    <li><strong>GET /files/*</strong> - Catch-all for file serving</li>
        \\    <li><strong>GET /api/v1/*</strong> - Catch-all for API v1</li>
        \\  </ul>
        \\  
        \\  <h2>Test with curl:</h2>
        \\  <pre>
        \\    # File serving wildcard
        \\    curl http://localhost:3000/files/docs/readme.txt
        \\    curl http://localhost:3000/files/images/logo.png
        \\    
        \\    # API catch-all
        \\    curl http://localhost:3000/api/v1/users/123
        \\    curl http://localhost:3000/api/v1/products/search?q=test
        \\    
        \\    # Unknown routes (will hit catch-all)
        \\    curl http://localhost:3000/unknown/path
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

    const context = AppContext{ .start_time = std.time.timestamp() };
    var app = helium.App(AppContext).init(allocator, context);
    defer app.deinit();

    try app.use(helium.log.common(AppContext));

    // Regular route
    try app.get("/", homeHandler);

    // Wildcard routes - captures remaining path in "*" parameter
    try app.get("/files/*", filesHandler);
    try app.get("/api/v1/*", apiV1Handler);

    std.log.info("", .{});
    std.log.info("===========================================", .{});
    std.log.info("  Wildcard Routes Demo", .{});
    std.log.info("===========================================", .{});
    std.log.info("", .{});
    std.log.info("Server listening on: http://127.0.0.1:3000", .{});
    std.log.info("", .{});
    std.log.info("Try these routes:", .{});
    std.log.info("  curl http://localhost:3000/files/docs/readme.txt", .{});
    std.log.info("  curl http://localhost:3000/api/v1/users/123", .{});
    std.log.info("", .{});

    try app.listen(3000);
}
