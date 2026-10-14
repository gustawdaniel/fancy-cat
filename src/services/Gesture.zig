const Self = @This();
const std = @import("std");

// Turns a stream of mouse wheel events (as sent by trackpads) into actions.
// Wheel events closer together than `gesture_timeout_ms` form one gesture.
// Vertical events scroll right away. A gesture turns a page once it has
// `horizontal_threshold` horizontal events in the same direction, unless it
// has already settled as vertical (`vertical_lock` vertical events). A
// horizontal gesture turns exactly one page, however long it lasts, and stops
// scrolling. Swiping left turns to the next page, like turning a paper page.

pub const Wheel = enum { up, down, left, right };

pub const Action = enum {
    none,
    scroll_up,
    scroll_down,
    next_page,
    prev_page,
};

pub const Options = struct {
    gesture_timeout_ms: i64 = 500,
    horizontal_threshold: u16 = 2,
    page_flip: bool = false,
};

// vertical events after which the gesture no longer turns pages
const vertical_lock = 4;

const Axis = enum { none, vertical, horizontal };

options: Options,
last_ms: ?i64 = null,
axis: Axis = .none,
vertical_count: u16 = 0,
// horizontal events in the current direction, positive to the right
horizontal_run: i32 = 0,

pub fn init(options: Options) Self {
    return .{ .options = options };
}

pub fn handle(self: *Self, wheel: Wheel, now_ms: i64) Action {
    if (self.last_ms) |last| {
        if (now_ms - last > self.options.gesture_timeout_ms) self.reset();
    }
    self.last_ms = now_ms;

    switch (wheel) {
        .up, .down => {
            if (self.axis == .horizontal) return .none;
            self.vertical_count +|= 1;
            if (self.vertical_count >= vertical_lock) self.axis = .vertical;
            return if (wheel == .up) .scroll_up else .scroll_down;
        },
        .left, .right => {
            if (self.axis != .none) return .none;

            const dir: i32 = if (wheel == .right) 1 else -1;
            if (self.horizontal_run * dir < 0) self.horizontal_run = 0;
            self.horizontal_run += dir;
            if (@abs(self.horizontal_run) < self.options.horizontal_threshold) return .none;

            self.axis = .horizontal;
            if (!self.options.page_flip) return .none;
            return if (wheel == .left) .next_page else .prev_page;
        },
    }
}

fn reset(self: *Self) void {
    self.axis = .none;
    self.vertical_count = 0;
    self.horizontal_run = 0;
}

fn feed(g: *Self, wheel: Wheel, n: usize, start_ms: i64, out: []Action) i64 {
    var t = start_ms;
    for (0..n) |i| {
        out[i] = g.handle(wheel, t);
        t += 10;
    }
    return t;
}

fn count(actions: []const Action, action: Action) usize {
    var n: usize = 0;
    for (actions) |a| {
        if (a == action) n += 1;
    }
    return n;
}

test "vertical scrolling is immediate" {
    var g = Self.init(.{});
    try std.testing.expectEqual(Action.scroll_down, g.handle(.down, 0));
    try std.testing.expectEqual(Action.scroll_up, g.handle(.up, 10));
}

test "swiping left turns to the next page, right to the previous" {
    var g = Self.init(.{ .page_flip = true });
    try std.testing.expectEqual(Action.none, g.handle(.left, 0));
    try std.testing.expectEqual(Action.next_page, g.handle(.left, 10));
    try std.testing.expectEqual(Action.none, g.handle(.right, 2000));
    try std.testing.expectEqual(Action.prev_page, g.handle(.right, 2010));
}

test "a horizontal gesture turns exactly one page" {
    var g = Self.init(.{ .page_flip = true });
    var out: [50]Action = undefined;
    _ = feed(&g, .left, out.len, 0, &out);
    try std.testing.expectEqual(@as(usize, 1), count(&out, .next_page));
}

test "slow swipe with pauses below the timeout stays one gesture" {
    var g = Self.init(.{ .page_flip = true });
    var flips: usize = 0;
    var t: i64 = 0;
    for (0..20) |_| {
        if (g.handle(.left, t) == .next_page) flips += 1;
        t += 450;
    }
    try std.testing.expectEqual(@as(usize, 1), flips);
}

test "a little vertical noise does not block a swipe" {
    var g = Self.init(.{ .page_flip = true });
    _ = g.handle(.down, 0);
    _ = g.handle(.left, 10);
    _ = g.handle(.down, 20);
    try std.testing.expectEqual(Action.next_page, g.handle(.left, 30));
}

test "a settled vertical gesture ignores sideways wobble" {
    var g = Self.init(.{ .page_flip = true });
    var out: [vertical_lock]Action = undefined;
    const t = feed(&g, .down, out.len, 0, &out);
    var side: [10]Action = undefined;
    _ = feed(&g, .left, side.len, t, &side);
    try std.testing.expectEqual(@as(usize, side.len), count(&side, .none));
}

test "a swipe stops vertical scrolling" {
    var g = Self.init(.{ .page_flip = true });
    var out: [2]Action = undefined;
    const t = feed(&g, .left, out.len, 0, &out);
    try std.testing.expectEqual(Action.none, g.handle(.down, t));
}

test "changing direction restarts the count" {
    var g = Self.init(.{ .page_flip = true });
    try std.testing.expectEqual(Action.none, g.handle(.left, 0));
    try std.testing.expectEqual(Action.none, g.handle(.right, 10));
    try std.testing.expectEqual(Action.prev_page, g.handle(.right, 20));
}

test "page flip is off by default" {
    var g = Self.init(.{});
    var out: [20]Action = undefined;
    _ = feed(&g, .left, out.len, 0, &out);
    try std.testing.expectEqual(@as(usize, out.len), count(&out, .none));
}
