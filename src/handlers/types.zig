// Types used in document handlers
pub const EncodedImage = struct { base64: []const u8, width: u16, height: u16 };

// A rectangle in pixels of the page rendered at the active zoom
pub const Rect = struct { x: u32, y: u32, width: u32, height: u32 };

// The page size and the visible part of it, in pixels at the active zoom
pub const View = struct { page_width: u32, page_height: u32, visible: Rect };

pub const ScrollDirection = enum { Up, Down, Left, Right };

pub const DocumentError = error{
    FailedToCreateContext,
    FailedToOpenDocument,
    FailedToRenderPage,
    InvalidPageNumber,
    UnsupportedFileFormat,
};
