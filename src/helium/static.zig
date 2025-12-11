const std = @import("std");
const helium = @import("./app.zig");
const mem = std.mem;
const fs = std.fs;
const Request = helium.Request;
const Response = helium.Response;
pub const FileServer = struct {
    allocator: mem.Allocator,
    root_path: []const u8,
    canonical_root_path: []const u8,
    pub fn init(allocator: mem.Allocator, root_path: []const u8) !FileServer {
        const dupe_path = try allocator.dupe(u8, root_path);
        errdefer allocator.free(dupe_path);
        const canonical_root = try fs.realpathAlloc(allocator, root_path);
        errdefer allocator.free(canonical_root);
        return FileServer{
            .allocator = allocator,
            .root_path = dupe_path,
            .canonical_root_path = canonical_root,
        };
    }
    pub fn deinit(self: *FileServer) void {
        self.allocator.free(self.root_path);
        self.allocator.free(self.canonical_root_path);
    }
    pub fn handle(self: *FileServer, req: *Request, res: *Response) !bool {
        if (req.raw_request.head.method != .GET) {
            return false;
        }
        var path = req.raw_request.head.target;
        if (path.len > 0 and path[0] == '/') {
            path = path[1..];
        }

        // If path is empty or ends with /, try index.html
        if (path.len == 0 or (path.len > 0 and path[path.len - 1] == '/')) {
            const index_path = if (path.len == 0)
                "index.html"
            else blk: {
                const joined = fs.path.join(self.allocator, &.{ path, "index.html" }) catch return false;
                break :blk joined;
            };
            defer if (path.len > 0) self.allocator.free(index_path);

            if (try self.serveFile(index_path, res)) {
                return true;
            }
        }

        // Try serving the requested file directly
        if (try self.serveFile(path, res)) {
            return true;
        }

        // If the path is a directory, try index.html inside it
        const file_path = try fs.path.join(self.allocator, &.{ self.root_path, path });
        defer self.allocator.free(file_path);

        const canonical_file_path = fs.realpathAlloc(self.allocator, file_path) catch |err| switch (err) {
            error.FileNotFound => return false,
            else => return err,
        };
        defer self.allocator.free(canonical_file_path);

        // Check if it's a directory
        const file = fs.openFileAbsolute(canonical_file_path, .{}) catch |err| switch (err) {
            error.FileNotFound => return false,
            error.IsDir => {
                // Try serving index.html from the directory
                const index_path = fs.path.join(self.allocator, &.{ path, "index.html" }) catch return false;
                defer self.allocator.free(index_path);
                return try self.serveFile(index_path, res);
            },
            else => return err,
        };
        file.close();

        return false;
    }

    fn serveFile(self: *FileServer, path: []const u8, res: *Response) !bool {
        const file_path = try fs.path.join(self.allocator, &.{ self.root_path, path });
        defer self.allocator.free(file_path);
        const canonical_file_path = fs.realpathAlloc(self.allocator, file_path) catch |err| switch (err) {
            error.FileNotFound => return false,
            else => return err,
        };
        defer self.allocator.free(canonical_file_path);
        if (!mem.startsWith(u8, canonical_file_path, self.canonical_root_path)) {
            res.setStatus(.forbidden);
            _ = try res.send("Access denied");
            return true;
        }
        const file = fs.openFileAbsolute(canonical_file_path, .{}) catch |err| switch (err) {
            error.FileNotFound => return false,
            else => return err,
        };
        defer file.close();
        const stat = try file.stat();
        if (stat.kind == .directory) {
            return false;
        }
        const content = try file.readToEndAlloc(res.allocator, stat.size);
        try res.headers.append(res.allocator, .{ .name = "Content-Type", .value = Mime.fromPath(path) });
        res.body = content;
        res.owns_body = true;
        return true;
    }
};
const Mime = struct {
    pub fn fromPath(path: []const u8) []const u8 {
        const ext = fs.path.extension(path);
        if (ext.len > 0) {
            if (mem.eql(u8, ext, ".html")) return "text/html; charset=utf-8";
            if (mem.eql(u8, ext, ".css")) return "text/css; charset=utf-8";
            if (mem.eql(u8, ext, ".js")) return "application/javascript; charset=utf-8";
            if (mem.eql(u8, ext, ".json")) return "application/json; charset=utf-8";
            if (mem.eql(u8, ext, ".txt")) return "text/plain; charset=utf-8";
            if (mem.eql(u8, ext, ".png")) return "image/png";
            if (mem.eql(u8, ext, ".jpg")) return "image/jpeg";
            if (mem.eql(u8, ext, ".jpeg")) return "image/jpeg";
            if (mem.eql(u8, ext, ".gif")) return "image/gif";
            if (mem.eql(u8, ext, ".svg")) return "image/svg+xml";
        }
        return "application/octet-stream";
    }
};

// Regression test for memory leak fix
test "FileServer sets owns_body to true for static content" {
    const testing = std.testing;

    // Create a test file
    const test_dir = "test_static_tmp";
    fs.cwd().makeDir(test_dir) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };
    defer fs.cwd().deleteTree(test_dir) catch {};

    const test_file_path = try fs.path.join(testing.allocator, &.{ test_dir, "test.txt" });
    defer testing.allocator.free(test_file_path);

    const test_file = try fs.cwd().createFile(test_file_path, .{});
    defer test_file.close();
    try test_file.writeAll("test content");

    // Initialize FileServer
    var file_server = try FileServer.init(testing.allocator, test_dir);
    defer file_server.deinit();

    // Create a mock request
    var in_reader = std.io.Reader.fixed("");
    var write_buf: [4096]u8 = undefined;
    var out_writer = std.io.Writer.fixed(&write_buf);
    var server = std.http.Server.init(&in_reader, &out_writer);

    var raw_request = try server.receiveHead();
    raw_request.head.method = .GET;
    raw_request.head.target = "/test.txt";

    var response = Response.init(testing.allocator);
    defer response.deinit();

    var query_params = std.StringHashMap([]const u8).init(testing.allocator);
    defer query_params.deinit();

    var request = Request{
        .allocator = testing.allocator,
        .raw_request = raw_request,
        .params = std.StringHashMap([]const u8).init(testing.allocator),
        .query = query_params,
        .body_reader = null,
        .remote_address = undefined,
    };
    defer request.deinit();

    // Handle the request
    const handled = try file_server.handle(&request, &response);

    // Verify the response owns the body (preventing memory leak)
    try testing.expect(handled);
    try testing.expect(response.owns_body);
    try testing.expect(response.body != null);
}
