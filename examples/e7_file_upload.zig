const std = @import("std");
const helium = @import("helium");

const Request = helium.Request;
const Response = helium.Response;
const MultipartParser = helium.multipart.MultipartParser;
const FileUploadHandler = helium.multipart.FileUploadHandler;

const AppContext = struct {
    upload_dir: []const u8,
    allocator: std.mem.Allocator,
    mutex: std.Thread.Mutex,
};

fn uploadFormHandler(_: *AppContext, _: *Request, res: *Response) !void {
    const html =
        \\<!DOCTYPE html>
        \\<html>
        \\<head><title>File Upload Demo</title></head>
        \\<body>
        \\  <h1>Helium File Upload Demo - Secure Streaming</h1>
        \\  <h2>Upload a file</h2>
        \\  <form action="/upload" method="POST" enctype="multipart/form-data">
        \\    <input type="file" name="file" required>
        \\    <button type="submit">Upload</button>
        \\  </form>
        \\  <h2>Note:</h2>
        \\  <p>This example uses secure streaming to handle file uploads. Files are written
        \\     directly to disk without loading the entire file into memory, protecting
        \\     against memory exhaustion attacks.</p>
        \\  <h2>Upload via curl:</h2>
        \\  <pre>curl -X POST -F "file=@/path/to/file.txt" http://localhost:3000/upload</pre>
        \\  <h2>List uploaded files:</h2>
        \\  <a href="/uploads">View uploaded files</a>
        \\</body>
        \\</html>
    ;

    try res.headers.append(res.allocator, .{ .name = "content-type", .value = "text/html" });
    res.body = html;
}

fn uploadHandler(ctx: *AppContext, req: *Request, res: *Response) !void {
    // Get the body reader for streaming
    const body_reader = req.getBodyReader() orelse {
        res.setStatus(.bad_request);
        try res.sendJson(.{ .success = false, .message = "No request body" });
        return;
    };

    // Extract Content-Type header to get the boundary
    const content_type = req.raw_request.head.content_type orelse {
        res.setStatus(.bad_request);
        try res.sendJson(.{ .success = false, .message = "Missing Content-Type header" });
        return;
    };

    // Extract boundary from Content-Type
    const boundary = MultipartParser.extractBoundary(req.allocator, content_type) catch {
        res.setStatus(.bad_request);
        try res.sendJson(.{ .success = false, .message = "Invalid multipart boundary" });
        return;
    };
    defer req.allocator.free(boundary);

    // Create multipart parser with streaming reader
    var parser = try MultipartParser.init(req.allocator, boundary, body_reader);

    // Create file upload handler
    var upload_handler = FileUploadHandler.init(ctx.allocator, ctx.upload_dir);
    upload_handler.max_file_size = 50 * 1024 * 1024; // 50MB max per file

    // Handle the upload with streaming to disk
    ctx.mutex.lock();
    defer ctx.mutex.unlock();

    var uploaded_files = upload_handler.handleUpload(&parser) catch |err| {
        std.log.err("Upload failed: {any}", .{err});
        res.setStatus(.internal_server_error);
        try res.sendJson(.{ .success = false, .message = "Upload failed" });
        return;
    };
    defer {
        for (uploaded_files.items) |*file| {
            file.deinit(ctx.allocator);
        }
        uploaded_files.deinit(ctx.allocator);
    }

    if (uploaded_files.items.len == 0) {
        res.setStatus(.bad_request);
        try res.sendJson(.{ .success = false, .message = "No files uploaded" });
        return;
    }

    // Build response with uploaded file info
    var files_info: std.ArrayList(struct {
        filename: []const u8,
        size: usize,
        path: []const u8,
    }) = .{};
    defer files_info.deinit(res.allocator);

    for (uploaded_files.items) |file| {
        try files_info.append(res.allocator, .{
            .filename = try res.allocator.dupe(u8, file.filename),
            .size = file.size,
            .path = try res.allocator.dupe(u8, file.filepath),
        });
    }

    try res.sendJson(.{
        .success = true,
        .message = "Files uploaded successfully",
        .count = files_info.items.len,
        .files = files_info.items,
    });
}

fn listUploadsHandler(ctx: *AppContext, _: *Request, res: *Response) !void {
    ctx.mutex.lock();
    defer ctx.mutex.unlock();

    var dir = std.fs.cwd().openDir(ctx.upload_dir, .{ .iterate = true }) catch |err| {
        if (err == error.FileNotFound) {
            try res.sendJson(.{
                .success = true,
                .files = &[_]void{},
                .count = 0,
                .message = "No uploads directory yet",
            });
            return;
        }
        return err;
    };
    defer dir.close();

    var files_list: std.ArrayList(struct { name: []const u8, size: u64 }) = .{};
    defer {
        for (files_list.items) |item| {
            res.allocator.free(item.name);
        }
        files_list.deinit(res.allocator);
    }

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        if (entry.kind == .file) {
            const name_copy = try res.allocator.dupe(u8, entry.name);
            const file_stat = try dir.statFile(entry.name);
            try files_list.append(res.allocator, .{
                .name = name_copy,
                .size = file_stat.size,
            });
        }
    }

    try res.sendJson(.{
        .success = true,
        .count = files_list.items.len,
        .files = files_list.items,
    });
}

pub fn main() !void {
    const gpa_unprotected = std.heap.page_allocator;
    var thread_safe_gpa_state = std.heap.ThreadSafeAllocator{ .child_allocator = gpa_unprotected };
    const gpa = thread_safe_gpa_state.allocator();

    const upload_dir = "uploads";
    std.fs.cwd().makeDir(upload_dir) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };

    const ctx = AppContext{
        .upload_dir = upload_dir,
        .allocator = gpa,
        .mutex = .{},
    };

    var app = helium.App(AppContext).init(gpa, ctx);

    try app.get("/", uploadFormHandler);
    try app.post("/upload", uploadHandler);
    try app.get("/uploads", listUploadsHandler);

    std.log.info("Starting secure file upload server on port 3000", .{});
    std.log.info("Files will be streamed directly to disk in: {s}", .{upload_dir});

    try app.listen(3000);
}
