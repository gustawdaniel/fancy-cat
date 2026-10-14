const Self = @This();
const vaxis = @import("vaxis");
const Context = @import("../Context.zig").Context;
const CommandMode = @import("./CommandMode.zig");
const Config = @import("../config/Config.zig");

context: *Context,
// vim-style count typed before a page jump, e.g. 12G
count: u16 = 0,
// first key of `first_page` was pressed, waiting for the second
pending_first_page: bool = false,

pub const KeyAction = struct {
    codepoint: u21,
    mods: vaxis.Key.Modifiers,
    handler: *const fn (*Context) void,
};

pub fn init(context: *Context) Self {
    return .{
        .context = context,
    };
}

fn goToPage(self: *Self, page: u16) void {
    if (self.context.document_handler.goToPage(page)) self.context.resetCurrentPage();
}

// Vim-style page jumps: `gg` (first page), `G` (last page), and a count
// before either, e.g. `12G` or `12gg`, to go to that page.
// Returns true when the key was consumed.
fn handlePageJump(self: *Self, key: vaxis.Key, km: Config.KeyMap) bool {
    if (key.codepoint >= '0' and key.codepoint <= '9' and key.matches(key.codepoint, .{})) {
        self.count = self.count *| 10 +| @as(u16, @intCast(key.codepoint - '0'));
        self.pending_first_page = false;
        return true;
    }

    if (key.matches(km.last_page.codepoint, km.last_page.mods)) {
        self.goToPage(if (self.count > 0) self.count else self.context.document_handler.getTotalPages());
        self.count = 0;
        self.pending_first_page = false;
        return true;
    }

    if (key.matches(km.first_page.codepoint, km.first_page.mods)) {
        if (self.pending_first_page) {
            self.goToPage(if (self.count > 0) self.count else 1);
            self.count = 0;
            self.pending_first_page = false;
        } else {
            self.pending_first_page = true;
        }
        return true;
    }

    self.count = 0;
    self.pending_first_page = false;
    return false;
}

pub fn handleKeyStroke(self: *Self, key: vaxis.Key, km: Config.KeyMap) !void {
    if (self.handlePageJump(key, km)) return;

    // O(n) but n is small
    // Centralized key handling
    const allocator = self.context.arena.allocator();
    const key_actions = try allocator.dupe(KeyAction, &[_]KeyAction{
        .{
            .codepoint = km.next.codepoint,
            .mods = km.next.mods,
            .handler = struct {
                fn action(s: *Context) void {
                    if (s.document_handler.changePage(1)) s.resetCurrentPage();
                }
            }.action,
        },
        .{
            .codepoint = km.prev.codepoint,
            .mods = km.prev.mods,
            .handler = struct {
                fn action(s: *Context) void {
                    if (s.document_handler.changePage(-1)) s.resetCurrentPage();
                }
            }.action,
        },
        .{
            .codepoint = km.zoom_in.codepoint,
            .mods = km.zoom_in.mods,
            .handler = struct {
                fn action(s: *Context) void {
                    s.document_handler.zoomIn(1.0);
                    s.reload_page = true;
                }
            }.action,
        },
        .{
            .codepoint = km.zoom_in_mult.codepoint,
            .mods = km.zoom_in_mult.mods,
            .handler = struct {
                fn action(s: *Context) void {
                    s.document_handler.zoomIn(s.config.general.zoom_mult);
                    s.reload_page = true;
                }
            }.action,
        },
        .{
            .codepoint = km.zoom_out.codepoint,
            .mods = km.zoom_out.mods,
            .handler = struct {
                fn action(s: *Context) void {
                    s.document_handler.zoomOut(1.0);
                    s.reload_page = true;
                }
            }.action,
        },
        .{
            .codepoint = km.zoom_out_mult.codepoint,
            .mods = km.zoom_out_mult.mods,
            .handler = struct {
                fn action(s: *Context) void {
                    s.document_handler.zoomOut(s.config.general.zoom_mult);
                    s.reload_page = true;
                }
            }.action,
        },
        .{
            .codepoint = km.width_mode.codepoint,
            .mods = km.width_mode.mods,
            .handler = struct {
                fn action(s: *Context) void {
                    s.document_handler.toggleWidthMode();
                    s.reload_page = true;
                }
            }.action,
        },
        .{
            .codepoint = km.full_screen.codepoint,
            .mods = km.full_screen.mods,
            .handler = struct {
                fn action(s: *Context) void {
                    s.toggleFullScreen();
                    s.document_handler.resetDefaultZoom();
                    s.document_handler.resetZoomAndScroll();
                    s.reload_page = true;
                }
            }.action,
        },
        .{
            .codepoint = km.scroll_up.codepoint,
            .mods = km.scroll_up.mods,
            .handler = struct {
                fn action(s: *Context) void {
                    s.document_handler.scroll(.Up, 1.0);
                    s.reload_page = true;
                }
            }.action,
        },
        .{
            .codepoint = km.scroll_up_mult.codepoint,
            .mods = km.scroll_up_mult.mods,
            .handler = struct {
                fn action(s: *Context) void {
                    s.document_handler.scroll(.Up, s.config.general.scroll_mult);
                    s.reload_page = true;
                }
            }.action,
        },
        .{
            .codepoint = km.scroll_down.codepoint,
            .mods = km.scroll_down.mods,
            .handler = struct {
                fn action(s: *Context) void {
                    s.document_handler.scroll(.Down, 1.0);
                    s.reload_page = true;
                }
            }.action,
        },
        .{
            .codepoint = km.scroll_down_mult.codepoint,
            .mods = km.scroll_down_mult.mods,
            .handler = struct {
                fn action(s: *Context) void {
                    s.document_handler.scroll(.Down, s.config.general.scroll_mult);
                    s.reload_page = true;
                }
            }.action,
        },
        .{
            .codepoint = km.scroll_left.codepoint,
            .mods = km.scroll_left.mods,
            .handler = struct {
                fn action(s: *Context) void {
                    s.document_handler.scroll(.Left, 1.0);
                    s.reload_page = true;
                }
            }.action,
        },
        .{
            .codepoint = km.scroll_left_mult.codepoint,
            .mods = km.scroll_left_mult.mods,
            .handler = struct {
                fn action(s: *Context) void {
                    s.document_handler.scroll(.Left, s.config.general.scroll_mult);
                    s.reload_page = true;
                }
            }.action,
        },
        .{
            .codepoint = km.scroll_right.codepoint,
            .mods = km.scroll_right.mods,
            .handler = struct {
                fn action(s: *Context) void {
                    s.document_handler.scroll(.Right, 1.0);
                    s.reload_page = true;
                }
            }.action,
        },
        .{
            .codepoint = km.scroll_right_mult.codepoint,
            .mods = km.scroll_right_mult.mods,
            .handler = struct {
                fn action(s: *Context) void {
                    s.document_handler.scroll(.Right, s.config.general.scroll_mult);
                    s.reload_page = true;
                }
            }.action,
        },
        .{
            .codepoint = km.colorize.codepoint,
            .mods = km.colorize.mods,
            .handler = struct {
                fn action(s: *Context) void {
                    s.document_handler.toggleColor();
                    s.reload_page = true;
                }
            }.action,
        },
        .{
            .codepoint = km.enter_command_mode.codepoint,
            .mods = km.enter_command_mode.mods,
            .handler = struct {
                fn action(s: *Context) void {
                    s.changeMode(.command);
                }
            }.action,
        },
    });

    for (key_actions) |action| {
        if (key.matches(action.codepoint, action.mods)) {
            action.handler(self.context);
            return;
        }
    }
}
