const std = @import("std");
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    const query_string = "name=zig&page=1";
    // Manual parsing approach
    var it = std.mem.splitScalar(u8, query_string, '&');
    while (it.next()) |pair| {
        if (std.mem.indexOfScalar(u8, pair, '=')) |eq_pos| {
            const key = pair[0..eq_pos];
            const value = pair[eq_pos + 1..];
            const decoded_key = try std.Uri.unescapeString(allocator, key);
            defer allocator.free(decoded_key);
            const decoded_value = try std.Uri.unescapeString(allocator, value);
            defer allocator.free(decoded_value);
            std.debug.print("key: {s}, value: {s}\n", .{decoded_key, decoded_value});
        }
    }
}
