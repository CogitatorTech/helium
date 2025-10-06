const std = @import("std");
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    const encoded = "hello%20world";
    // Try different APIs
    const decoded = try std.Uri.percentDecodeBackwards(allocator, encoded);
    defer allocator.free(decoded);
    std.debug.print("decoded: {s}\n", .{decoded});
}
