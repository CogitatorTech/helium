const std = @import("std");
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    const query_string = "name=zig&page=1";
    // Try using std.Uri.Component.Query
    var iter = std.Uri.Component.Query.iterate(query_string);
    while (iter.next()) |param| {
        const key = try std.Uri.unescapeString(allocator, param.key.percent_encoded);
        defer allocator.free(key);
        const value = try std.Uri.unescapeString(allocator, param.value.percent_encoded);
        defer allocator.free(value);
        std.debug.print("key: {s}, value: {s}\n", .{key, value});
    }
}
