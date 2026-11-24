#import "AmpedSkinImage.h"

#import <CommonCrypto/CommonDigest.h>
#import <ImageIO/ImageIO.h>
#include <pwd.h>
#include <unistd.h>

/// The picture of the skin archive [data] that the app drew, when it has: a
/// modern skin runs scripts this renderer cannot, so the app draws it and
/// keeps the picture where the previews can read it (named by the SHA-256 of
/// the archive, `SkinPreviewStore`). The extension may read only that folder.
static NSData* AmpedAppDrawnPNG(NSData* data, CGSize* size) {
  uint8_t digest[CC_SHA256_DIGEST_LENGTH];
  CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
  NSMutableString* key = [NSMutableString stringWithCapacity:64];
  for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) {
    [key appendFormat:@"%02x", digest[i]];
  }
  // The sandbox moves the home folder; the app's is the real one.
  struct passwd* user = getpwuid(getuid());
  if (user == NULL) return nil;
  NSString* home = [NSString stringWithUTF8String:user->pw_dir];
  // The newest version's picture; until the app has drawn it again (it does
  // so a while after it starts) the one of the version before shows, which is
  // better than the simpler picture drawn here.
  NSData* png = nil;
  for (NSString* version in @[ @"v4", @"v3" ]) {
    NSString* path = [NSString
        stringWithFormat:@"%@/Library/Application Support/org.hadak.amped/amped/previews/%@/%@.png",
                         home, version, key];
    png = [NSData dataWithContentsOfFile:path];
    if (png != nil) break;
  }
  if (png == nil) return nil;
  CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)png, NULL);
  if (source == NULL) return nil;
  NSDictionary* properties =
      CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source, 0, NULL));
  CFRelease(source);
  NSNumber* width = properties[(NSString*)kCGImagePropertyPixelWidth];
  NSNumber* height = properties[(NSString*)kCGImagePropertyPixelHeight];
  if (width == nil || height == nil) return nil;
  *size = CGSizeMake(width.doubleValue, height.doubleValue);
  return png;
}

NSData* AmpedCreateSkinPNG(NSURL* url, int layout, int scale,
                             CGSize* size) {
  NSData* data = [NSData dataWithContentsOfURL:url
                                       options:NSDataReadingMappedIfSafe
                                         error:nil];
  if (data == nil) return nil;
  NSData* drawn = AmpedAppDrawnPNG(data, size);
  if (drawn != nil) return drawn;
  // The skin's name in the song title, as the thumbnailer on Linux shows it.
  NSString* title = [[url.lastPathComponent.stringByDeletingPathExtension
      stringByReplacingOccurrencesOfString:@"_"
                                withString:@" "] uppercaseString];
  SkinPreviewImage image, scaled;
  if (skin_preview_render(data.bytes, data.length, title.UTF8String, layout,
                          &image) != 0) {
    return nil;
  }
  int longest = MAX(image.width, image.height);
  int failed = skin_preview_fit(&image, longest * scale, &scaled);
  skin_preview_free(&image);
  if (failed) return nil;
  *size = CGSizeMake(scaled.width, scaled.height);
  uint8_t* png = NULL;
  size_t length = 0;
  failed = skin_preview_encode_png(&scaled, &png, &length);
  skin_preview_free(&scaled);
  if (failed) return nil;
  return [NSData dataWithBytesNoCopy:png length:length freeWhenDone:YES];
}
