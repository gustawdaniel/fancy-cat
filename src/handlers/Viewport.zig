const std = @import("std");
const types = @import("./types.zig");

// Scrolling only moves a clip over an image that is already in the terminal.
// The rendered region is the whole page when it is small enough, otherwise a
// band around the visible part, re-rendered once the view leaves it.

// cap on rendered pixels, about 48 MiB of RGB samples
pub const max_region_pixels: u64 = 16 * 1024 * 1024;
// kitty images are sized with u16
const max_side: u32 = std.math.maxInt(u16);

pub fn chooseRegion(view: types.View) types.Rect {
    const pw = @min(view.page_width, max_side);
    const ph = @min(view.page_height, max_side);
    const v = view.visible;

    if (@as(u64, pw) * ph <= max_region_pixels) {
        return .{ .x = 0, .y = 0, .width = pw, .height = ph };
    }

    // prefer the full width with room to scroll a view height up and down
    const width = if (@as(u64, pw) * 3 * v.height <= max_region_pixels) pw else @min(pw, 2 * v.width);
    const height: u32 = @intCast(std.math.clamp(max_region_pixels / width, v.height, ph));

    return .{
        .x = center(v.x, v.width, width, pw),
        .y = center(v.y, v.height, height, ph),
        .width = width,
        .height = height,
    };
}

// start of a span of `size` centered on [pos, pos + len), kept within [0, limit)
fn center(pos: u32, len: u32, size: u32, limit: u32) u32 {
    const mid = pos + len / 2;
    const start = mid -| size / 2;
    return @min(start, limit - size);
}

pub fn contains(region: types.Rect, visible: types.Rect) bool {
    return visible.x >= region.x and
        visible.y >= region.y and
        visible.x + visible.width <= region.x + region.width and
        visible.y + visible.height <= region.y + region.height;
}

test "a small page is rendered whole" {
    const view = types.View{
        .page_width = 1200,
        .page_height = 1700,
        .visible = .{ .x = 0, .y = 400, .width = 1200, .height = 900 },
    };
    const r = chooseRegion(view);
    try std.testing.expectEqual(types.Rect{ .x = 0, .y = 0, .width = 1200, .height = 1700 }, r);
    try std.testing.expect(contains(r, view.visible));
}

test "a large page gets a band around the view" {
    const view = types.View{
        .page_width = 3000,
        .page_height = 12000,
        .visible = .{ .x = 0, .y = 6000, .width = 3000, .height = 1800 },
    };
    const r = chooseRegion(view);
    try std.testing.expectEqual(@as(u32, 3000), r.width);
    try std.testing.expect(@as(u64, r.width) * r.height <= max_region_pixels);
    try std.testing.expect(r.height >= 3 * view.visible.height);
    try std.testing.expect(contains(r, view.visible));
}

test "a band near the end of the page stays within it" {
    const view = types.View{
        .page_width = 3000,
        .page_height = 12000,
        .visible = .{ .x = 0, .y = 12000 - 1800, .width = 3000, .height = 1800 },
    };
    const r = chooseRegion(view);
    try std.testing.expectEqual(@as(u32, 12000), r.y + r.height);
    try std.testing.expect(contains(r, view.visible));
}

test "a very wide page narrows the band to the view" {
    const view = types.View{
        .page_width = 20000,
        .page_height = 28000,
        .visible = .{ .x = 9000, .y = 9000, .width = 3000, .height = 1800 },
    };
    const r = chooseRegion(view);
    try std.testing.expectEqual(@as(u32, 6000), r.width);
    try std.testing.expect(@as(u64, r.width) * r.height <= max_region_pixels);
    try std.testing.expect(contains(r, view.visible));
}

test "leaving the band is detected" {
    const region = types.Rect{ .x = 0, .y = 1000, .width = 3000, .height = 5000 };
    try std.testing.expect(contains(region, .{ .x = 0, .y = 1000, .width = 3000, .height = 1800 }));
    try std.testing.expect(!contains(region, .{ .x = 0, .y = 999, .width = 3000, .height = 1800 }));
    try std.testing.expect(!contains(region, .{ .x = 0, .y = 4201, .width = 3000, .height = 1800 }));
}
