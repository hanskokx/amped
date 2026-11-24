#import "PreviewProvider.h"

#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#import "AmpedSkinImage.h"

/// The preview is drawn at the classic player's double size.
static const int kScale = 2;

@implementation PreviewProvider

- (void)providePreviewForFileRequest:(QLFilePreviewRequest*)request
                   completionHandler:
                       (void (^)(QLPreviewReply* _Nullable reply,
                                 NSError* _Nullable error))handler {
  // A PNG rather than a drawing, so the window shapes stay transparent.
  CGSize size;
  NSData* png =
      AmpedCreateSkinPNG(request.fileURL, SKIN_PREVIEW_STACK, kScale, &size);
  if (png == nil) {
    handler(nil, [NSError errorWithDomain:NSCocoaErrorDomain
                                     code:NSFileReadCorruptFileError
                                 userInfo:nil]);
    return;
  }
  QLPreviewReply* reply = [[QLPreviewReply alloc]
      initWithDataOfContentType:UTTypePNG
                    contentSize:size
              dataCreationBlock:^NSData* _Nullable(QLPreviewReply* unused,
                                                   NSError** error) {
                return png;
              }];
  handler(reply, nil);
}

@end
