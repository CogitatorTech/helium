const std = @import("std");
const mem = std.mem;
const mw = @import("./middleware.zig");
const http_types = @import("./http_types.zig");
const Request = http_types.Request;
const Response = http_types.Response;

/// CORS configuration options
pub const CorsConfig = struct {
    /// Allowed origins. Use "*" for any origin, or specify exact origins.
    allowed_origins: []const []const u8 = &.{"*"},
    /// Allowed HTTP methods
    allowed_methods: []const u8 = "GET, POST, PUT, DELETE, OPTIONS",
    /// Allowed request headers
    allowed_headers: []const u8 = "Content-Type, Authorization",
    /// Whether to allow credentials (cookies, authorization headers)
    allow_credentials: bool = false,
    /// Preflight cache duration in seconds (Access-Control-Max-Age)
    max_age: ?u32 = null,
    /// Headers to expose to the client
    expose_headers: ?[]const u8 = null,
};

/// Returns a CORS middleware configured with the given options.
pub fn configured(comptime ContextType: type, comptime config: CorsConfig) mw.chain.Types(ContextType).MiddlewareFn {
    return struct {
        fn handler(ctx: *ContextType, req: *Request, res: *Response, next_opaque: *anyopaque) !void {
            const Next = mw.chain.Types(ContextType).Next;
            const next = @as(*Next, @ptrCast(@alignCast(next_opaque)));

            // Set allowed origin - use "*" if configured, otherwise first specified origin
            // Note: In production, you'd want to check the request Origin header against allowed_origins
            // but Zig 0.15.2's HTTP server doesn't expose request headers for iteration
            const allowed_origin = if (config.allowed_origins.len == 1 and mem.eql(u8, config.allowed_origins[0], "*"))
                "*"
            else if (config.allowed_origins.len > 0)
                config.allowed_origins[0]
            else
                "*";

            try res.headers.append(res.allocator, .{ .name = "Access-Control-Allow-Origin", .value = allowed_origin });
            try res.headers.append(res.allocator, .{ .name = "Access-Control-Allow-Methods", .value = config.allowed_methods });
            try res.headers.append(res.allocator, .{ .name = "Access-Control-Allow-Headers", .value = config.allowed_headers });

            if (config.allow_credentials) {
                try res.headers.append(res.allocator, .{ .name = "Access-Control-Allow-Credentials", .value = "true" });
            }

            if (config.max_age) |age| {
                const age_str = try std.fmt.allocPrint(res.allocator, "{d}", .{age});
                try res.headers.append(res.allocator, .{ .name = "Access-Control-Max-Age", .value = age_str });
            }

            if (config.expose_headers) |headers| {
                try res.headers.append(res.allocator, .{ .name = "Access-Control-Expose-Headers", .value = headers });
            }

            // Handle preflight OPTIONS request
            if (req.raw_request.head.method == .OPTIONS) {
                res.status = .no_content;
                return;
            }

            try next.call(ctx, req, res);
        }
    }.handler;
}

/// Simple CORS middleware that allows all origins (for development).
/// For production, use `configured()` with specific origins.
pub fn any(comptime ContextType: type) mw.chain.Types(ContextType).MiddlewareFn {
    return configured(ContextType, .{});
}
