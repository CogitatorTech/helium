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

        // Get the canonical (absolute, normalized) path of the root directory
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

    /// Tries to handle the request. Returns `true` if it was handled,
    /// `false` if it was skipped (e.g., not a GET request, or file not found).
    pub fn handle(self: *FileServer, req: *Request, res: *Response) !bool {
        if (req.raw_request.head.method != .GET) {
            return false;
        }

        var path = req.raw_request.head.target;

        // Strip the leading slash to make the path relative.
        if (path.len > 0 and path[0] == '/') {
            path = path[1..];
        }

        // Join the trusted root path with the user-provided path
        const file_path = try fs.path.join(self.allocator, &.{ self.root_path, path });
        defer self.allocator.free(file_path);

        // Canonicalize the requested path to resolve all . and .. segments
        const canonical_file_path = fs.realpathAlloc(self.allocator, file_path) catch |err| switch (err) {
            error.FileNotFound => return false,
            else => return err,
        };
        defer self.allocator.free(canonical_file_path);

        // CRITICAL SECURITY CHECK: Verify the canonical path starts with the canonical root
        // This prevents path traversal attacks (e.g., ../../etc/passwd)
        if (!mem.startsWith(u8, canonical_file_path, self.canonical_root_path)) {
            res.setStatus(.forbidden);
            _ = try res.send("Access denied");
            return true; // Handled with an error.
        }

        const file = fs.openFileAbsolute(canonical_file_path, .{}) catch |err| switch (err) {
            error.FileNotFound => return false,
            else => return err,
        };
        defer file.close();

        const stat = try file.stat();
        if (stat.kind == .directory) {
            // Treat directories as "not found" to allow other routes to match.
            return false;
        }

        const content = try file.readToEndAlloc(res.allocator, stat.size);
        try res.headers.append(res.allocator, .{ .name = "Content-Type", .value = Mime.fromPath(path) });
        try res.send(content);
        return true; // Handled successfully.
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
