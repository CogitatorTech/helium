const std = @import("std");
const mem = std.mem;
const std_json = std.json;
const net = std.net;
const Headers = std.ArrayList(std.http.Header);
const Header = std.http.Header;
const Status = std.http.Status;
const Server = std.http.Server;
pub const BodyLimits = struct {
    max_memory_size: usize = 1 * 1024 * 1024,
    max_body_size: usize = 100 * 1024 * 1024,
};
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
        const n = if (self.raw_reader_ptr) |rdr| blk: {
            const adapted_reader = rdr.adaptToOldInterface();
            break :blk try adapted_reader.read(buffer[0..max_to_read]);
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
    pub fn readBodyAlloc(self: *Request) ![]u8 {
        if (self.body_reader) |*reader| {
            return reader.readAll(self.allocator, self.limits.max_memory_size);
        }
        return &[_]u8{};
    }
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
            .headers = Headers{},
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
        // Use {f} format specifier with json.fmt() to output proper JSON
        self.body = try std.fmt.allocPrint(self.allocator, "{f}", .{std_json.fmt(value, .{})});
        self.owns_body = true;
    }
    pub fn setStatus(self: *Response, status: Status) void {
        self.status = status;
    }
};

// Regression tests
test "BodyReader can read from raw_reader_ptr" {
    const testing = std.testing;

    // Create test data
    const test_data = "Hello, World!";
    var in_reader = std.io.Reader.fixed(test_data);

    // Initialize BodyReader with raw_reader_ptr
    var body_reader = BodyReader.init(&in_reader, 1024);

    // Read data
    var buffer: [100]u8 = undefined;
    const n = try body_reader.read(&buffer);

    // Verify data was read correctly (not returning 0)
    try testing.expect(n > 0);
    try testing.expectEqualSlices(u8, test_data, buffer[0..n]);
}

test "BodyReader tracks bytes_read correctly" {
    const testing = std.testing;

    const test_data = "Hello, World!";
    var in_reader = std.io.Reader.fixed(test_data);
    var body_reader = BodyReader.init(&in_reader, 1024);

    var buffer: [100]u8 = undefined;
    const n = try body_reader.read(&buffer);

    try testing.expectEqual(n, body_reader.bytes_read);
}

test "Response initializes headers correctly" {
    const testing = std.testing;

    var response = Response.init(testing.allocator);
    defer response.deinit();

    // Should be able to append headers without crash
    try response.headers.append(testing.allocator, .{
        .name = "Content-Type",
        .value = "text/plain",
    });

    try testing.expectEqual(@as(usize, 1), response.headers.items.len);
}

test "Response deinit frees owned body" {
    const testing = std.testing;

    var response = Response.init(testing.allocator);

    // Allocate a body
    response.body = try testing.allocator.dupe(u8, "test body");
    response.owns_body = true;

    // deinit should free the body
    response.deinit();
}
