// Native file drops for file_drop on macOS.
//
// Flutter's windowing API creates the NSWindows; this installs a transparent
// drop target over a window's content (`WindowControllerMacOS.windowHandle`).

#import <Cocoa/Cocoa.h>


typedef void (*FDDropCallback)(int64_t token, char* path);

// A transparent overlay that accepts file drags for its window. It returns
// nil from hitTest: so every mouse event still reaches the Flutter view;
// AppKit finds drag destinations by registered types, not hitTest:.
@interface FDDropView : NSView
@property(nonatomic) FDDropCallback callback;
@property(nonatomic) int64_t token;
@property(nonatomic, copy) NSArray<NSString*>* extensions;
@property(nonatomic) BOOL directories;
@end

@implementation FDDropView

- (NSView*)hitTest:(NSPoint)point {
  return nil;
}

- (NSArray<NSURL*>*)acceptedURLs:(id<NSDraggingInfo>)info {
  NSArray<NSURL*>* urls = [info.draggingPasteboard
      readObjectsForClasses:@[ [NSURL class] ]
                    options:@{NSPasteboardURLReadingFileURLsOnlyKey : @YES}];
  NSMutableArray<NSURL*>* accepted = [NSMutableArray array];
  for (NSURL* url in urls) {
    NSNumber* isDirectory = nil;
    [url getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:nil];
    if (isDirectory.boolValue) {
      if (self.directories) [accepted addObject:url];
    } else if (self.extensions.count == 0 ||
               [self.extensions containsObject:url.pathExtension.lowercaseString]) {
      [accepted addObject:url];
    }
  }
  return accepted;
}

- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)info {
  return [self acceptedURLs:info].count > 0 ? NSDragOperationCopy : NSDragOperationNone;
}

- (NSDragOperation)draggingUpdated:(id<NSDraggingInfo>)info {
  return [self draggingEntered:info];
}

- (BOOL)performDragOperation:(id<NSDraggingInfo>)info {
  NSArray<NSURL*>* urls = [self acceptedURLs:info];
  for (NSURL* url in urls) {
    // Ownership of the copy passes to Dart, which frees it.
    self.callback(self.token, strdup(url.fileSystemRepresentation));
  }
  return urls.count > 0;
}

@end

// Calls [callback] with [token] and the path of every dropped file whose
// extension is in the comma-separated [extensions] (all files when empty),
// and of dropped folders when [directories] is set.
void fd_enable_file_drop(void* handle, const char* extensions, int32_t directories,
                         FDDropCallback callback, int64_t token) {
  NSWindow* window = (__bridge NSWindow*)handle;
  NSView* content = window.contentView;
  if (content == nil) return;
  for (NSView* subview in content.subviews) {
    if ([subview isKindOfClass:[FDDropView class]]) [subview removeFromSuperview];
  }
  FDDropView* drop = [[FDDropView alloc] initWithFrame:content.bounds];
  drop.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  drop.callback = callback;
  drop.token = token;
  NSString* list = [NSString stringWithUTF8String:extensions];
  NSMutableArray<NSString*>* parsed = [NSMutableArray array];
  for (NSString* ext in [list componentsSeparatedByString:@","]) {
    if (ext.length > 0) [parsed addObject:ext.lowercaseString];
  }
  drop.extensions = parsed;
  drop.directories = directories != 0;
  [drop registerForDraggedTypes:@[ NSPasteboardTypeFileURL ]];
  [content addSubview:drop positioned:NSWindowAbove relativeTo:nil];
}
