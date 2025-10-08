const std = @import("std");
const helium = @import("helium");
const Request = helium.Request;
const Response = helium.Response;
const AppContext = struct {
    file_server: helium.static.FileServer,
    allocator: std.mem.Allocator,
};
fn staticMiddleware(ctx: *AppContext, req: *Request, res: *Response, next: *anyopaque) !void {
    if (try ctx.file_server.handle(req, res)) {
        return;
    }
    const Next = helium.App(AppContext).Next;
    const next_fn = @as(*Next, @ptrCast(@alignCast(next)));
    try next_fn.call(ctx, req, res);
}
fn homeHandler(_: *AppContext, _: *Request, res: *Response) !void {
    const html =
        \\<!DOCTYPE html>
        \\<html>
        \\<head>
        \\  <title>Static Files Demo</title>
        \\  <link rel="stylesheet" href="/styles.css">
        \\</head>
        \\<body>
        \\  <div class="container">
        \\    <h1>Helium Static Files Demo</h1>
        \\    <p>This page demonstrates serving static files with Helium.</p>
        \\
        \\    <h2>Available Static Files:</h2>
        \\    <ul>
        \\      <li><a href="/styles.css">styles.css</a> - CSS stylesheet</li>
        \\      <li><a href="/script.js">script.js</a> - JavaScript file</li>
        \\      <li><a href="/logo.txt">logo.txt</a> - Text file with ASCII art</li>
        \\      <li><a href="/data.json">data.json</a> - JSON data file</li>
        \\    </ul>
        \\
        \\    <h2>Features:</h2>
        \\    <ul>
        \\      <li>Automatic MIME type detection</li>
        \\      <li>Efficient file serving</li>
        \\      <li>Fallback to dynamic routes</li>
        \\      <li>Security: Prevents directory traversal</li>
        \\    </ul>
        \\
        \\    <button onclick="testScript()">Test JavaScript</button>
        \\    <div id="output"></div>
        \\
        \\    <h2>API Endpoints:</h2>
        \\    <ul>
        \\      <li><a href="/api/hello">GET /api/hello</a> - Dynamic API endpoint</li>
        \\      <li><a href="/api/data">GET /api/data</a> - Dynamic JSON endpoint</li>
        \\    </ul>
        \\  </div>
        \\  <script src="/script.js"></script>
        \\</body>
        \\</html>
    ;
    try res.headers.append(res.allocator, .{ .name = "content-type", .value = "text/html" });
    res.body = html;
}
fn apiHelloHandler(_: *AppContext, _: *Request, res: *Response) !void {
    try res.sendJson(.{
        .message = "Hello from dynamic API endpoint!",
        .note = "This is a dynamic route, not a static file",
    });
}
fn apiDataHandler(_: *AppContext, _: *Request, res: *Response) !void {
    try res.sendJson(.{
        .users = [_]struct { id: u32, name: []const u8 }{
            .{ .id = 1, .name = "Alice" },
            .{ .id = 2, .name = "Bob" },
            .{ .id = 3, .name = "Charlie" },
        },
        .timestamp = std.time.timestamp(),
    });
}
fn setupStaticFiles(allocator: std.mem.Allocator, dir: []const u8) !void {
    std.fs.cwd().makeDir(dir) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };
    const css_content =
        \\body {
        \\  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
        \\  line-height: 1.6;
        \\  margin: 0;
        \\  padding: 20px;
        \\  background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
        \\  color: #333;
        \\}
        \\
        \\.container {
        \\  max-width: 800px;
        \\  margin: 0 auto;
        \\  background: white;
        \\  padding: 30px;
        \\  border-radius: 10px;
        \\  box-shadow: 0 10px 40px rgba(0,0,0,0.2);
        \\}
        \\
        \\h1 {
        \\  color: #667eea;
        \\  border-bottom: 3px solid #667eea;
        \\  padding-bottom: 10px;
        \\}
        \\
        \\h2 {
        \\  color: #764ba2;
        \\  margin-top: 30px;
        \\}
        \\
        \\a {
        \\  color: #667eea;
        \\  text-decoration: none;
        \\}
        \\
        \\a:hover {
        \\  text-decoration: underline;
        \\}
        \\
        \\button {
        \\  background: #667eea;
        \\  color: white;
        \\  border: none;
        \\  padding: 10px 20px;
        \\  border-radius: 5px;
        \\  cursor: pointer;
        \\  font-size: 16px;
        \\  margin: 20px 0;
        \\}
        \\
        \\button:hover {
        \\  background: #764ba2;
        \\}
        \\
        \\#output {
        \\  margin-top: 20px;
        \\  padding: 15px;
        \\  background: #f0f0f0;
        \\  border-radius: 5px;
        \\  min-height: 50px;
        \\}
        \\
        \\ul {
        \\  line-height: 2;
        \\}
    ;
    const css_path = try std.fs.path.join(allocator, &[_][]const u8{ dir, "styles.css" });
    defer allocator.free(css_path);
    try std.fs.cwd().writeFile(.{ .sub_path = css_path, .data = css_content });
    const js_content =
        \\function testScript() {
        \\  const output = document.getElementById('output');
        \\  output.innerHTML = '<strong>JavaScript is working!</strong><br>' +
        \\    'File served from: /script.js<br>' +
        \\    'Current time: ' + new Date().toLocaleString();
        \\  output.style.background = '#d4edda';
        \\  output.style.color = '#155724';
        \\  output.style.border = '1px solid #c3e6cb';
        \\}
        \\
        \\console.log('Static JavaScript file loaded successfully!');
    ;
    const js_path = try std.fs.path.join(allocator, &[_][]const u8{ dir, "script.js" });
    defer allocator.free(js_path);
    try std.fs.cwd().writeFile(.{ .sub_path = js_path, .data = js_content });
    const logo_content =
        \\
        \\  _   _      _ _
        \\ | | | | ___| (_)_   _ _ __ ___
        \\ | |_| |/ _ \ | | | | | '_ ` _ \
        \\ |  _  |  __/ | | |_| | | | | | |
        \\ |_| |_|\___|_|_|\__,_|_| |_| |_|
        \\
        \\ A lightweight HTTP framework for Zig
        \\
        \\ This is a static text file being served by Helium!
        \\
    ;
    const logo_path = try std.fs.path.join(allocator, &[_][]const u8{ dir, "logo.txt" });
    defer allocator.free(logo_path);
    try std.fs.cwd().writeFile(.{ .sub_path = logo_path, .data = logo_content });
    const json_content =
        \\{
        \\  "name": "Static JSON File",
        \\  "served_by": "Helium Framework",
        \\  "features": [
        \\    "Fast file serving",
        \\    "Automatic MIME types",
        \\    "Security built-in"
        \\  ],
        \\  "version": "1.0.0"
        \\}
    ;
    const json_path = try std.fs.path.join(allocator, &[_][]const u8{ dir, "data.json" });
    defer allocator.free(json_path);
    try std.fs.cwd().writeFile(.{ .sub_path = json_path, .data = json_content });
}
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    const static_dir = "static_demo";
    try setupStaticFiles(allocator, static_dir);
    std.log.info("Created static files in ./{s}/ directory", .{static_dir});
    const file_server = try helium.static.FileServer.init(allocator, static_dir);
    const context = AppContext{
        .file_server = file_server,
        .allocator = allocator,
    };
    var app = helium.App(AppContext).init(allocator, context);
    defer {
        app.context.file_server.deinit();
        app.deinit();
    }
    try app.use(helium.cors.any(AppContext));
    try app.use(helium.log.common(AppContext));
    try app.use(staticMiddleware);
    try app.get("/", homeHandler);
    try app.get("/api/hello", apiHelloHandler);
    try app.get("/api/data", apiDataHandler);
    std.log.info("", .{});
    std.log.info("===========================================", .{});
    std.log.info("  Helium Static Files Demo", .{});
    std.log.info("===========================================", .{});
    std.log.info("", .{});
    std.log.info("Server listening on: http://127.0.0.1:3000", .{});
    std.log.info("Static files served from: ./{s}/", .{static_dir});
    std.log.info("", .{});
    std.log.info("Try these URLs:", .{});
    std.log.info("  http://localhost:3000/          - Dynamic home page", .{});
    std.log.info("  http://localhost:3000/styles.css - Static CSS", .{});
    std.log.info("  http://localhost:3000/script.js  - Static JS", .{});
    std.log.info("  http://localhost:3000/logo.txt   - Static text", .{});
    std.log.info("  http://localhost:3000/data.json  - Static JSON", .{});
    std.log.info("", .{});
    try app.listen(3000);
}
