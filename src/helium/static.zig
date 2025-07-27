const std = @import("std");
const kryten = @import("./app.zig");
const mem = std.mem;
const fs = std.fs;

const Request = kryten.Request;
const Response = kryten.Response;

pub const FileServer = struct {
    allocator: mem.Allocator,
    root_path: []const u8,

    pub fn init(allocator: mem.Allocator, root_path: []const u8) !FileServer {
        const dupe_path = try allocator.dupe(u8, root_path);
        return FileServer{
            .allocator = allocator,
            .root_path = dupe_path,
        };
    }

    pub fn deinit(self: *FileServer) void {
        self.allocator.free(self.root_path);
    }

    /// Tries to handle the request. Returns `true` if it was handled,
    /// `false` if it was skipped (e.g., not a GET request, or file not found).
    pub fn handle(self: *FileServer, req: *Request, res: *Response) !bool {
        if (req.raw_request.head.method != .GET) {
            return false;
        }

        var path = req.raw_request.head.target;

        // ✨ FIX: Strip the leading slash to make the path relative.
        if (path.len > 0 and path[0] == '/') {
            path = path[1..];
        }

        // WARNING: This security check is still insufficient.
        if (mem.indexOf(u8, path, "..") != null) {
            res.setStatus(.bad_request);
            _ = try res.send("Invalid path");
            return true; // Handled with an error.
        }

        const file_path = try fs.path.join(self.allocator, &.{ self.root_path, path });
        defer self.allocator.free(file_path);

        const file = fs.openFileAbsolute(file_path, .{}) catch |err| switch (err) {
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
        try res.headers.append(.{ .name = "Content-Type", .value = Mime.fromPath(path) });
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
