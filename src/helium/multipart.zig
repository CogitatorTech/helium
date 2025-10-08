const std = @import("std");
const mem = std.mem;
pub const MultipartParser = struct {
    allocator: mem.Allocator,
    boundary: []const u8,
    reader: std.io.AnyReader,
    state: ParserState = .awaiting_boundary,
    buffer: [8192]u8 = undefined,
    buffer_pos: usize = 0,
    buffer_len: usize = 0,
    const ParserState = enum {
        awaiting_boundary,
        reading_headers,
        reading_content,
        done,
    };
    pub const Part = struct {
        name: []const u8,
        filename: ?[]const u8,
        content_type: ?[]const u8,
        headers: std.StringHashMap([]const u8),
        pub fn deinit(self: *Part, allocator: mem.Allocator) void {
            allocator.free(self.name);
            if (self.filename) |fn_| allocator.free(fn_);
            if (self.content_type) |ct| allocator.free(ct);
            self.headers.deinit();
        }
    };
    pub fn init(allocator: mem.Allocator, boundary: []const u8, reader: std.io.AnyReader) !MultipartParser {
        return .{
            .allocator = allocator,
            .boundary = boundary,
            .reader = reader,
        };
    }
    pub fn extractBoundary(allocator: mem.Allocator, content_type: []const u8) ![]const u8 {
        const boundary_prefix = "boundary=";
        const start = mem.indexOf(u8, content_type, boundary_prefix) orelse return error.NoBoundary;
        var boundary = content_type[start + boundary_prefix.len ..];
        if (boundary.len > 0 and boundary[0] == '"') {
            boundary = boundary[1..];
            if (mem.indexOf(u8, boundary, "\"")) |end| {
                boundary = boundary[0..end];
            }
        }
        return allocator.dupe(u8, boundary);
    }
    pub fn nextPart(self: *MultipartParser) !?Part {
        if (self.state == .done) return null;
        while (self.state == .awaiting_boundary) {
            const line = try self.readLine();
            if (line.len == 0) continue;
            if (mem.indexOf(u8, line, self.boundary)) |_| {
                if (mem.endsWith(u8, line, "--")) {
                    self.state = .done;
                    return null;
                }
                self.state = .reading_headers;
                break;
            }
        }
        var headers = std.StringHashMap([]const u8).init(self.allocator);
        errdefer {
            var it = headers.iterator();
            while (it.next()) |entry| {
                self.allocator.free(entry.key_ptr.*);
                self.allocator.free(entry.value_ptr.*);
            }
            headers.deinit();
        }
        var part_name: ?[]const u8 = null;
        var filename: ?[]const u8 = null;
        var content_type: ?[]const u8 = null;
        while (self.state == .reading_headers) {
            const line = try self.readLine();
            if (line.len == 0) {
                self.state = .reading_content;
                break;
            }
            if (mem.indexOf(u8, line, ":")) |colon_pos| {
                const key = mem.trim(u8, line[0..colon_pos], &std.ascii.whitespace);
                const value = mem.trim(u8, line[colon_pos + 1 ..], &std.ascii.whitespace);
                if (mem.eql(u8, key, "Content-Disposition")) {
                    if (mem.indexOf(u8, value, "name=\"")) |name_start| {
                        const name_begin = name_start + 6;
                        if (mem.indexOf(u8, value[name_begin..], "\"")) |name_end| {
                            part_name = try self.allocator.dupe(u8, value[name_begin .. name_begin + name_end]);
                        }
                    }
                    if (mem.indexOf(u8, value, "filename=\"")) |fn_start| {
                        const fn_begin = fn_start + 10;
                        if (mem.indexOf(u8, value[fn_begin..], "\"")) |fn_end| {
                            filename = try self.allocator.dupe(u8, value[fn_begin .. fn_begin + fn_end]);
                        }
                    }
                } else if (mem.eql(u8, key, "Content-Type")) {
                    content_type = try self.allocator.dupe(u8, value);
                }
                const key_copy = try self.allocator.dupe(u8, key);
                errdefer self.allocator.free(key_copy);
                const value_copy = try self.allocator.dupe(u8, value);
                errdefer self.allocator.free(value_copy);
                try headers.put(key_copy, value_copy);
            }
        }
        if (part_name == null) return error.MissingPartName;
        self.state = .awaiting_boundary;
        return Part{
            .name = part_name.?,
            .filename = filename,
            .content_type = content_type,
            .headers = headers,
        };
    }
    pub fn streamPartContent(self: *MultipartParser, writer: std.io.AnyWriter, max_size: usize) !usize {
        var total_written: usize = 0;
        var boundary_buf: [4096]u8 = undefined;
        const full_boundary = try std.fmt.bufPrint(&boundary_buf, "\r\n--{s}", .{self.boundary});
        var accumulator: std.ArrayList(u8) = .{};
        defer accumulator.deinit(self.allocator);
        while (true) {
            const n = try self.fillBuffer();
            if (n == 0 and self.buffer_pos == self.buffer_len) break;
            try accumulator.appendSlice(self.allocator, self.buffer[self.buffer_pos..self.buffer_len]);
            self.buffer_pos = self.buffer_len;
            if (mem.indexOf(u8, accumulator.items, full_boundary)) |boundary_pos| {
                const to_write = accumulator.items[0..boundary_pos];
                if (total_written + to_write.len > max_size) {
                    return error.PartTooLarge;
                }
                try writer.writeAll(to_write);
                total_written += to_write.len;
                accumulator.clearRetainingCapacity();
                break;
            }
            if (accumulator.items.len > full_boundary.len + 4096) {
                const safe_write = accumulator.items.len - full_boundary.len;
                if (total_written + safe_write > max_size) {
                    return error.PartTooLarge;
                }
                try writer.writeAll(accumulator.items[0..safe_write]);
                total_written += safe_write;
                mem.copyForwards(u8, accumulator.items, accumulator.items[safe_write..]);
                accumulator.shrinkRetainingCapacity(accumulator.items.len - safe_write);
            }
        }
        return total_written;
    }
    fn fillBuffer(self: *MultipartParser) !usize {
        if (self.buffer_pos == self.buffer_len) {
            self.buffer_pos = 0;
            self.buffer_len = try self.reader.read(&self.buffer);
            return self.buffer_len;
        }
        return self.buffer_len - self.buffer_pos;
    }
    fn readLine(self: *MultipartParser) ![]const u8 {
        var line: std.ArrayList(u8) = .{};
        defer line.deinit(self.allocator);
        while (true) {
            if (self.buffer_pos >= self.buffer_len) {
                const n = try self.fillBuffer();
                if (n == 0) break;
            }
            const byte = self.buffer[self.buffer_pos];
            self.buffer_pos += 1;
            if (byte == '\n') {
                if (line.items.len > 0 and line.items[line.items.len - 1] == '\r') {
                    _ = line.pop();
                }
                return line.toOwnedSlice(self.allocator);
            }
            try line.append(self.allocator, byte);
        }
        return line.toOwnedSlice(self.allocator);
    }
};
pub const FileUploadHandler = struct {
    upload_dir: []const u8,
    allocator: mem.Allocator,
    max_file_size: usize = 50 * 1024 * 1024,
    pub const UploadedFile = struct {
        field_name: []const u8,
        filename: []const u8,
        filepath: []const u8,
        size: usize,
        content_type: ?[]const u8,
        pub fn deinit(self: *UploadedFile, allocator: mem.Allocator) void {
            allocator.free(self.field_name);
            allocator.free(self.filename);
            allocator.free(self.filepath);
            if (self.content_type) |ct| allocator.free(ct);
        }
    };
    pub fn init(allocator: mem.Allocator, upload_dir: []const u8) FileUploadHandler {
        return .{
            .allocator = allocator,
            .upload_dir = upload_dir,
        };
    }
    pub fn handleUpload(self: *FileUploadHandler, parser: *MultipartParser) !std.ArrayList(UploadedFile) {
        var uploaded_files: std.ArrayList(UploadedFile) = .{};
        errdefer {
            for (uploaded_files.items) |*file| {
                file.deinit(self.allocator);
            }
            uploaded_files.deinit(self.allocator);
        }
        std.fs.cwd().makeDir(self.upload_dir) catch |err| {
            if (err != error.PathAlreadyExists) return err;
        };
        while (try parser.nextPart()) |*part| {
            defer {
                var mut_part = part.*;
                mut_part.deinit(self.allocator);
            }
            if (part.filename == null) continue;
            const timestamp = std.time.timestamp();
            const safe_filename = try self.generateSafeFilename(part.filename.?, timestamp);
            defer self.allocator.free(safe_filename);
            const filepath = try std.fs.path.join(self.allocator, &[_][]const u8{ self.upload_dir, safe_filename });
            errdefer self.allocator.free(filepath);
            const file = try std.fs.cwd().createFile(filepath, .{});
            defer file.close();
            const file_writer = std.io.AnyWriter{
                .context = @ptrCast(@constCast(&file)),
                .writeFn = struct {
                    fn write(context: *const anyopaque, bytes: []const u8) anyerror!usize {
                        const f: *const std.fs.File = @ptrCast(@alignCast(context));
                        return f.write(bytes);
                    }
                }.write,
            };
            const size = try parser.streamPartContent(file_writer, self.max_file_size);
            const uploaded = UploadedFile{
                .field_name = try self.allocator.dupe(u8, part.name),
                .filename = try self.allocator.dupe(u8, part.filename.?),
                .filepath = filepath,
                .size = size,
                .content_type = if (part.content_type) |ct| try self.allocator.dupe(u8, ct) else null,
            };
            try uploaded_files.append(self.allocator, uploaded);
            std.log.info("Uploaded file: {s} ({d} bytes) to {s}", .{ uploaded.filename, size, filepath });
        }
        return uploaded_files;
    }
    fn generateSafeFilename(self: *FileUploadHandler, original: []const u8, timestamp: i64) ![]const u8 {
        var ext: []const u8 = "";
        if (mem.lastIndexOfScalar(u8, original, '.')) |dot_pos| {
            ext = original[dot_pos..];
        }
        return std.fmt.allocPrint(self.allocator, "upload_{d}{s}", .{ timestamp, ext });
    }
};
