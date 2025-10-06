const std = @import("std");
const helium = @import("helium");

const Context = struct {};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var app = helium.App(Context).init(allocator, .{});
    defer app.deinit();

    var ctx = Context{};

    // Test route that uses query parameters
    try app.get("/search", .{searchHandler});

    std.log.info("Test server with query string parsing", .{});
    try app.listen(8080, &ctx);
}

fn searchHandler(ctx: *Context, req: *helium.Request, res: *helium.Response) !void {
    _ = ctx;

    // Access query parameters
    const name = req.query.get("name") orelse "unknown";
    const page = req.query.get("page") orelse "1";

    const response_text = try std.fmt.allocPrint(
        res.allocator,
        "Search query - name: {s}, page: {s}",
        .{ name, page }
    );

    try res.send(response_text);
}

