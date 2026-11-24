// Renders a skin file into a PNG for the Quick Look extension, using
// the shared renderer in native/skin_preview.

#import <Foundation/Foundation.h>

#include "skin_preview.h"

NS_ASSUME_NONNULL_BEGIN

/// The skin at `url` in `layout` (`SKIN_PREVIEW_STACK`, ...), enlarged
/// `scale` times with sharp pixels, as a PNG with the window shapes left
/// transparent; nil when it is not a skin. Sets `size` to its pixel size.
NSData* _Nullable AmpedCreateSkinPNG(NSURL* url, int layout, int scale,
                                       CGSize* size);

NS_ASSUME_NONNULL_END
