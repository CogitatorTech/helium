const std = @import("std");
const helium = @import("helium");
const Request = helium.Request;
const Response = helium.Response;

const AppContext = struct {
    name: []const u8,
};

/// API handler that returns data
fn apiDataHandler(_: *AppContext, _: *Request, res: *Response) !void {
    try res.sendJson(.{
        .message = "Hello from the API!",
        .data = .{
            .items = [_]u32{ 1, 2, 3, 4, 5 },
            .count = 5,
        },
    });
}

/// Health check endpoint
fn healthHandler(_: *AppContext, _: *Request, res: *Response) !void {
    try res.sendJson(.{ .status = "healthy" });
}

/// Home page with CORS testing info
fn homeHandler(_: *AppContext, _: *Request, res: *Response) !void {
    const html =
        \\<!DOCTYPE html>
        \\<html>
        \\<head><title>CORS Configuration Demo</title></head>
        \\<body>
        \\  <h1>Helium CORS Configuration Demo</h1>
        \\  
        \\  <h2>Configured CORS Policy:</h2>
        \\  <ul>
        \\    <li><strong>Allowed Origins:</strong> http://localhost:8080, http://example.com</li>
        \\    <li><strong>Allowed Methods:</strong> GET, POST, PUT, DELETE, OPTIONS</li>
        \\    <li><strong>Allowed Headers:</strong> Content-Type, Authorization, X-Custom-Header</li>
        \\    <li><strong>Allow Credentials:</strong> true</li>
        \\    <li><strong>Max Age:</strong> 3600 seconds (1 hour)</li>
        \\  </ul>
        \\  
        \\  <h2>Test with curl:</h2>
        \\  <pre>
        \\    # Test from allowed origin
        \\    curl -i -H "Origin: http://localhost:8080" http://localhost:3000/api/data
        \\    
        \\    # Test from disallowed origin (no CORS headers)
        \\    curl -i -H "Origin: http://evil.com" http://localhost:3000/api/data
        \\    
        \\    # Test preflight OPTIONS request
        \\    curl -i -X OPTIONS \
        \\      -H "Origin: http://localhost:8080" \
        \\      -H "Access-Control-Request-Method: POST" \
        \\      http://localhost:3000/api/data
        \\    
        \\    # Test without origin (no CORS headers needed)
        \\    curl -i http://localhost:3000/api/data
        \\  </pre>
        \\  
        \\  <h2>API Endpoints:</h2>
        \\  <ul>
        \\    <li><a href="/api/data">GET /api/data</a> - Returns JSON data</li>
        \\    <li><a href="/health">GET /health</a> - Health check</li>
        \\  </ul>
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

    const context = AppContext{ .name = "CORS Demo" };
    var app = helium.App(AppContext).init(allocator, context);
    defer app.deinit();

    // Configure CORS with specific settings
    // Note: Currently sets the first origin in the list as the allowed origin
    // because Zig 0.15.2's HTTP server doesn't expose request headers for validation
    try app.use(helium.cors.configured(AppContext, .{
        // Specify the allowed origin
        .allowed_origins = &.{"http://localhost:8080"},
        // Specify allowed methods
        .allowed_methods = "GET, POST, PUT, DELETE, OPTIONS",
        // Include custom headers
        .allowed_headers = "Content-Type, Authorization, X-Custom-Header",
        // Allow credentials (cookies)
        .allow_credentials = true,
        // Cache preflight for 1 hour
        .max_age = 3600,
        // Expose custom response headers
        .expose_headers = "X-Request-Id",
    }));

    try app.use(helium.log.common(AppContext));

    try app.get("/", homeHandler);
    try app.get("/api/data", apiDataHandler);
    try app.get("/health", healthHandler);

    std.log.info("", .{});
    std.log.info("===========================================", .{});
    std.log.info("  CORS Configuration Demo", .{});
    std.log.info("===========================================", .{});
    std.log.info("", .{});
    std.log.info("Server listening on: http://127.0.0.1:3000", .{});
    std.log.info("", .{});
    std.log.info("Allowed origins: http://localhost:8080, http://example.com", .{});
    std.log.info("", .{});
    std.log.info("Try these commands:", .{});
    std.log.info("  curl -i -H 'Origin: http://localhost:8080' http://localhost:3000/api/data", .{});
    std.log.info("  curl -i -H 'Origin: http://evil.com' http://localhost:3000/api/data", .{});
    std.log.info("", .{});

    try app.listen(3000);
}
