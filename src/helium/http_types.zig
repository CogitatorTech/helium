const std = @import("std");
const mem = std.mem;
const std_json = std.json;
const net = std.net;

const Headers = std.ArrayList(std.http.Header);
const Header = std.http.Header;
const Status = std.http.Status;
const Server = std.http.Server;

pub const Request = struct {
    allocator: mem.Allocator,
    raw_request: Server.Request,
    params: std.StringHashMap([]const u8),
    body_str: ?[]const u8 = null,
    remote_address: net.Address,

    // This function is removed.
    // pub fn json(...) ...

    pub fn deinit(self: *Request) void {
        self.params.deinit();
    }
};

pub const Response = struct {
    headers: Headers,
    status: Status = .ok,
    body: ?[]const u8 = null,
    allocator: mem.Allocator,

    pub fn init(allocator: mem.Allocator) Response {
        return .{
            .allocator = allocator,
            .headers = Headers.init(allocator),
        };
    }

    pub fn deinit(self: *Response) void {
        self.headers.deinit();
    }

    pub fn send(self: *Response, body_text: []const u8) !void {
        try self.headers.append(Header{
            .name = "content-type",
            .value = "text/plain; charset=utf-8",
        });
        self.body = body_text;
    }

    pub fn sendJson(self: *Response, value: anytype) !void {
        try self.headers.append(Header{
            .name = "content-type",
            .value = "application/json; charset=utf-8",
        });
        self.body = try std_json.stringifyAlloc(self.allocator, value, .{});
    }

    pub fn setStatus(self: *Response, status: Status) void {
        self.status = status;
    }
};
