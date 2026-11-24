#import <QuickLookUI/QuickLookUI.h>

/// The Quick Look preview of a skin: for `.wsz`, the main window,
/// equalizer and playlist editor as the classic player first shows them; for `.wal`, the
/// skin's screenshot, else its main window.
@interface PreviewProvider : QLPreviewProvider <QLPreviewingController>
@end
