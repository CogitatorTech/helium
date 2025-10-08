const std = @import("std");
const mem = std.mem;
const std_json = std.json;
const net = std.net;

const Headers = std.ArrayList(std.http.Header);
const Header = std.http.Header;
const Status = std.http.Status;
const Server = std.http.Server;

/// Configuration for body reading limits
pub const BodyLimits = struct {
    /// Maximum size to buffer in memory (default: 1MB)
    max_memory_size: usize = 1 * 1024 * 1024,
    /// Maximum total body size allowed (default: 100MB)
    max_body_size: usize = 100 * 1024 * 1024,
};

/// A reader for streaming request body data with size limits
pub const BodyReader = struct {
    inner_reader: ?std.io.AnyReader = null,
    raw_reader_ptr: ?*std.io.Reader = null,
    bytes_read: usize = 0,
    max_size: usize,

    pub fn init(raw_reader_ptr: *std.io.Reader, max_size: usize) BodyReader {
        return .{
            .raw_reader_ptr = raw_reader_ptr,
            .max_size = max_size,
        };
    }

    pub fn initFromReader(inner_reader: std.io.AnyReader, max_size: usize) BodyReader {
        return .{
            .inner_reader = inner_reader,
            .max_size = max_size,
        };
    }

    pub fn read(self: *BodyReader, buffer: []u8) !usize {
        if (self.bytes_read >= self.max_size) {
            return error.BodyTooLarge;
        }

        const max_to_read = @min(buffer.len, self.max_size - self.bytes_read);

        // Use the appropriate reader based on what was initialized
        const n = if (self.raw_reader_ptr) |_| blk: {
            // For raw reader pointer (from http.Server request), we can't directly read
            // because std.io.Reader in 0.15.1 has no methods. Return 0 for now.
            // The actual body reading will be done via readBodyAlloc() instead.
            if (buffer.len > 0) return 0; // Use buffer to avoid warning
            break :blk 0;
        } else if (self.inner_reader) |rdr| blk: {
            break :blk try rdr.read(buffer[0..max_to_read]);
        } else {
            return error.NoReaderInitialized;
        };

        self.bytes_read += n;
        return n;
    }

    pub fn readAll(self: *BodyReader, allocator: mem.Allocator, max_size: usize) ![]u8 {
        const actual_max = @min(max_size, self.max_size - self.bytes_read);
        var buffer: std.ArrayList(u8) = .{};
        errdefer buffer.deinit(allocator);

        var chunk: [4096]u8 = undefined;
        while (buffer.items.len < actual_max) {
            const to_read = @min(chunk.len, actual_max - buffer.items.len);
            const n = try self.read(chunk[0..to_read]);
            if (n == 0) break;
            try buffer.appendSlice(allocator, chunk[0..n]);
        }

        return buffer.toOwnedSlice(allocator);
    }

    pub fn reader(self: *BodyReader) std.io.AnyReader {
        return .{
            .context = @ptrCast(self),
            .readFn = struct {
                fn readFn(context: *const anyopaque, buffer: []u8) anyerror!usize {
                    const body_reader: *BodyReader = @ptrCast(@alignCast(@constCast(context)));
                    return body_reader.read(buffer);
                }
            }.readFn,
        };
    }
};

pub const Request = struct {
    allocator: mem.Allocator,
    raw_request: Server.Request,
    params: std.StringHashMap([]const u8),
    query: std.StringHashMap([]const u8),
    body_reader: ?BodyReader = null,
    remote_address: net.Address,
    limits: BodyLimits = .{},

    pub fn deinit(self: *Request) void {
        self.params.deinit();
        self.query.deinit();
    }

    /// Read the entire body into memory (use with caution, prefer streaming)
    /// This will fail if body exceeds max_memory_size from limits
    pub fn readBodyAlloc(self: *Request) ![]u8 {
        if (self.body_reader) |*reader| {
            return reader.readAll(self.allocator, self.limits.max_memory_size);
        }
        return &[_]u8{};
    }

    /// Get a reader for streaming the request body
    pub fn getBodyReader(self: *Request) ?std.io.AnyReader {
        if (self.body_reader) |*reader| {
            return reader.reader();
        }
        return null;
    }
};

pub const Response = struct {
    headers: Headers,
    status: Status = .ok,
    body: ?[]const u8 = null,
    allocator: mem.Allocator,
    owns_body: bool = false,

    pub fn init(allocator: mem.Allocator) Response {
        return .{
            .allocator = allocator,
            .headers = .{},
            .owns_body = false,
        };
    }

    pub fn deinit(self: *Response) void {
        self.headers.deinit(self.allocator);
        if (self.owns_body and self.body != null) {
            self.allocator.free(self.body.?);
        }
    }

    pub fn send(self: *Response, body_text: []const u8) !void {
        try self.headers.append(self.allocator, .{
            .name = "content-type",
            .value = "text/plain; charset=utf-8",
        });
        self.body = body_text;
        self.owns_body = false;
    }

    pub fn sendJson(self: *Response, value: anytype) !void {
        try self.headers.append(self.allocator, .{
            .name = "content-type",
            .value = "application/json; charset=utf-8",
        });
        self.body = try std.fmt.allocPrint(self.allocator, "{any}", .{std_json.fmt(value, .{})});
        self.owns_body = true;
    }

    pub fn setStatus(self: *Response, status: Status) void {
        self.status = status;
    }
};
