// Native window helpers for window_dock on macOS.
//
// Flutter's windowing API creates the NSWindows but does not expose moving,
// styling, ordering or always-on-top. These functions operate directly on the
// NSWindow handle the framework hands out (`WindowControllerMacOS.windowHandle`).
//
// Coordinates are logical points in a global top-left space: the origin is
// the top-left corner of the primary screen and Y grows downwards, which is
// what every desktop platform other than macOS uses natively.

#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

typedef struct {
  double x;
  double y;
  double width;
  double height;
} WDRect;

static CGFloat WDPrimaryHeight(void) {
  NSArray<NSScreen*>* screens = [NSScreen screens];
  if (screens.count == 0) return 0;
  return screens[0].frame.size.height;
}

static WDRect WDFromCocoa(NSRect r) {
  WDRect out;
  out.x = r.origin.x;
  out.y = WDPrimaryHeight() - r.origin.y - r.size.height;
  out.width = r.size.width;
  out.height = r.size.height;
  return out;
}

static NSRect WDToCocoa(double x, double y, double w, double h) {
  return NSMakeRect(x, WDPrimaryHeight() - y - h, w, h);
}

// Borderless windows cannot become key (or main) by default, and Flutter only
// receives mouse-move events -- hover, cursor changes -- and keyboard input in
// the key window. Flutter owns these windows (and observes them with KVO, so
// they cannot be re-classed), so NSWindow's answers are hooked once: windows
// tagged by window_dock say yes, every other window keeps the original answer.
static char WDKeyableKey;
static IMP WDOriginalCanBecomeKey;
static IMP WDOriginalCanBecomeMain;

static BOOL WDCanBecomeKey(id self, SEL _cmd) {
  if (objc_getAssociatedObject(self, &WDKeyableKey) != nil) return YES;
  return ((BOOL(*)(id, SEL))WDOriginalCanBecomeKey)(self, _cmd);
}

static BOOL WDCanBecomeMain(id self, SEL _cmd) {
  if (objc_getAssociatedObject(self, &WDKeyableKey) != nil) return YES;
  return ((BOOL(*)(id, SEL))WDOriginalCanBecomeMain)(self, _cmd);
}

static void WDMakeKeyable(NSWindow* window) {
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    Method key = class_getInstanceMethod([NSWindow class], @selector(canBecomeKeyWindow));
    Method main = class_getInstanceMethod([NSWindow class], @selector(canBecomeMainWindow));
    WDOriginalCanBecomeKey = method_setImplementation(key, (IMP)WDCanBecomeKey);
    WDOriginalCanBecomeMain = method_setImplementation(main, (IMP)WDCanBecomeMain);
  });
  objc_setAssociatedObject(window, &WDKeyableKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

void wd_configure(void* handle, int frameless, int transparent) {
  NSWindow* window = (__bridge NSWindow*)handle;
  if (window == nil) return;
  NSRect content = [window contentRectForFrameRect:window.frame];
  if (frameless) {
    window.styleMask = NSWindowStyleMaskBorderless | NSWindowStyleMaskMiniaturizable;
    window.hasShadow = NO;
    window.movableByWindowBackground = NO;
    window.movable = NO;
    // Keep the content size: the old frame included the title bar.
    [window setFrame:content display:YES];
    WDMakeKeyable(window);
    // Track the mouse even when the window is not key, so hover effects and
    // cursors work in every window like the original's (FlutterViewController
    // `mouseTrackingMode`, 3 = kFlutterMouseTrackingModeAlways).
    NSViewController* flutterController = window.contentViewController;
    if ([flutterController respondsToSelector:@selector(setMouseTrackingMode:)]) {
      [flutterController setValue:@3 forKey:@"mouseTrackingMode"];
    }
  }
  // Mission Control (Exposé) only shows windows it manages. Without an
  // explicit choice, AppKit derives that from the window level, so the
  // always-on-top windows (NSFloatingWindowLevel) are treated as transient
  // and left out. Choosing "managed" outright keeps every window in Exposé
  // at any level; the other behaviors (Spaces, Cmd-` cycling) are kept.
  window.collectionBehavior =
      (window.collectionBehavior &
       ~(NSWindowCollectionBehaviorTransient | NSWindowCollectionBehaviorStationary)) |
      NSWindowCollectionBehaviorManaged;
  if (transparent) {
    window.opaque = NO;
    window.backgroundColor = [NSColor clearColor];
    NSViewController* controller = window.contentViewController;
    if ([controller respondsToSelector:@selector(setBackgroundColor:)]) {
      [controller setValue:[NSColor clearColor] forKey:@"backgroundColor"];
    }
  }
}

void wd_set_frame(void* handle, double x, double y, double w, double h) {
  NSWindow* window = (__bridge NSWindow*)handle;
  if (window == nil) return;
  NSRect current = window.frame;
  if (w <= 0) w = current.size.width;
  if (h <= 0) h = current.size.height;
  // Whole points only: a fractional size gives the view a fractional render
  // target, which Impeller can fail to allocate while the view resizes.
  w = MAX(1.0, round(w));
  h = MAX(1.0, round(h));
  NSRect target = WDToCocoa(x, y, w, h);
  if (NSEqualRects(target, current)) return;
  // Never redraw synchronously: the Flutter view resizes on its own, and a
  // forced display makes it wait on (and race with) the raster thread, which
  // crashed Impeller while the Album Art window was being dragged larger.
  [window setFrame:target display:NO animate:NO];
}

void wd_set_position(void* handle, double x, double y) {
  NSWindow* window = (__bridge NSWindow*)handle;
  if (window == nil) return;
  NSRect current = window.frame;
  [window setFrameTopLeftPoint:NSMakePoint(x, WDPrimaryHeight() - y)];
  (void)current;
}

WDRect wd_get_frame(void* handle) {
  NSWindow* window = (__bridge NSWindow*)handle;
  if (window == nil) {
    WDRect zero = {0, 0, 0, 0};
    return zero;
  }
  return WDFromCocoa(window.frame);
}

void wd_set_always_on_top(void* handle, int on) {
  NSWindow* window = (__bridge NSWindow*)handle;
  if (window == nil) return;
  window.level = on ? NSFloatingWindowLevel : NSNormalWindowLevel;
}

// Fullscreen without a separate Space (as the original's DirectDraw modes
// took over the display at once): the window covers its whole screen above
// the menu bar, which hides along with the Dock. The previous frame and
// level are kept on the window for leaving.
static char WDFullscreenKey;

void wd_set_fullscreen(void* handle, int on) {
  NSWindow* window = (__bridge NSWindow*)handle;
  if (window == nil) return;
  NSDictionary* saved = objc_getAssociatedObject(window, &WDFullscreenKey);
  if (on) {
    if (saved == nil) {
      objc_setAssociatedObject(
          window, &WDFullscreenKey,
          @{
            @"frame" : [NSValue valueWithRect:window.frame],
            @"level" : @(window.level),
          },
          OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    NSScreen* screen = window.screen ?: [NSScreen mainScreen];
    [NSApp setPresentationOptions:NSApplicationPresentationHideMenuBar |
                                  NSApplicationPresentationHideDock];
    window.level = NSMainMenuWindowLevel + 1;
    [window setFrame:screen.frame display:YES];
  } else if (saved != nil) {
    objc_setAssociatedObject(window, &WDFullscreenKey, nil,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [NSApp setPresentationOptions:NSApplicationPresentationDefault];
    window.level = [saved[@"level"] integerValue];
    [window setFrame:[saved[@"frame"] rectValue] display:YES];
  }
}

double wd_safe_area_top(void* handle) {
  NSWindow* window = (__bridge NSWindow*)handle;
  NSScreen* screen = window.screen ?: [NSScreen mainScreen];
  if (@available(macOS 12.0, *)) return screen.safeAreaInsets.top;
  return 0;
}

// Calls [callback] whenever a window becomes or stops being the key window,
// which Flutter's windowing API does not report on macOS.
void wd_observe_key_window(void (*callback)(void)) {
  static id becameKey, resignedKey;
  NSNotificationCenter* center = [NSNotificationCenter defaultCenter];
  if (becameKey != nil) [center removeObserver:becameKey];
  if (resignedKey != nil) [center removeObserver:resignedKey];
  void (^notify)(NSNotification*) = ^(NSNotification* note) {
    callback();
  };
  becameKey = [center addObserverForName:NSWindowDidBecomeKeyNotification
                                  object:nil
                                   queue:nil
                              usingBlock:notify];
  resignedKey = [center addObserverForName:NSWindowDidResignKeyNotification
                                    object:nil
                                     queue:nil
                                usingBlock:notify];
}

void wd_reset_presentation(void) {
  [NSApp setPresentationOptions:NSApplicationPresentationDefault];
}

void wd_set_visible(void* handle, int visible) {
  NSWindow* window = (__bridge NSWindow*)handle;
  if (window == nil) return;
  if (visible) {
    [window orderFront:nil];
  } else {
    [window orderOut:nil];
  }
}

int wd_is_visible(void* handle) {
  NSWindow* window = (__bridge NSWindow*)handle;
  return window != nil && window.visible ? 1 : 0;
}

// The first view in [view]'s tree that takes keyboard input.
static NSView* WDKeyView(NSView* view) {
  if (view.acceptsFirstResponder) return view;
  for (NSView* subview in view.subviews) {
    NSView* found = WDKeyView(subview);
    if (found != nil) return found;
  }
  return nil;
}

void wd_focus(void* handle) {
  NSWindow* window = (__bridge NSWindow*)handle;
  if (window == nil) return;
  [NSApp activateIgnoringOtherApps:YES];
  [window makeKeyAndOrderFront:nil];
  // A window that has not been clicked yet (one just opened, or made
  // borderless) leaves the keyboard with itself, so Flutter's view would
  // see no keys until clicked.
  if (window.firstResponder == window || window.firstResponder == nil) {
    NSView* view = WDKeyView(window.contentView);
    if (view != nil) [window makeFirstResponder:view];
  }
}

void wd_minimize(void* handle) {
  NSWindow* window = (__bridge NSWindow*)handle;
  if (window == nil) return;
  [window miniaturize:nil];
}

// A window that cannot become key does not take the focus when clicked
// (a layout's `noactivation="1"`).
void wd_set_activatable(void* handle, int activatable) {
  NSWindow* window = (__bridge NSWindow*)handle;
  if (window == nil) return;
  objc_setAssociatedObject(window, &WDKeyableKey, activatable ? @YES : nil,
                           OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

void wd_set_min_size(void* handle, double width, double height) {
  NSWindow* window = (__bridge NSWindow*)handle;
  if (window == nil) return;
  window.contentMinSize = NSMakeSize(width, height);
}

void wd_order_above(void* handle, void* other) {
  NSWindow* window = (__bridge NSWindow*)handle;
  NSWindow* below = (__bridge NSWindow*)other;
  if (window == nil || below == nil) return;
  [window orderWindow:NSWindowAbove relativeTo:below.windowNumber];
}

int wd_get_work_areas(WDRect* out, int max) {
  NSArray<NSScreen*>* screens = [NSScreen screens];
  int count = 0;
  for (NSScreen* screen in screens) {
    if (count >= max) break;
    out[count++] = WDFromCocoa(screen.visibleFrame);
  }
  return count;
}

void wd_get_cursor_position(double* x, double* y) {
  NSPoint p = [NSEvent mouseLocation];
  *x = p.x;
  *y = WDPrimaryHeight() - p.y;
}

void wd_activate_app(void) {
  [NSApp activateIgnoringOtherApps:YES];
}

// --- Popup menus -----------------------------------------------------------

@interface WDMenuTarget : NSObject
@property(nonatomic) NSInteger selected;
- (void)choose:(NSMenuItem*)item;
@end

@implementation WDMenuTarget
- (void)choose:(NSMenuItem*)item {
  self.selected = item.tag;
}
@end

// The key a shortcut hint names ("A", "1", "Delete", "F5", ...) as an
// NSMenuItem key equivalent, or nil.
static NSString* WDKeyEquivalent(NSString* key) {
  if (key.length == 1) return key.lowercaseString;
  static NSDictionary<NSString*, NSNumber*>* named;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    named = @{
      @"delete" : @(NSDeleteFunctionKey),
      @"del" : @(NSDeleteFunctionKey),
      @"backspace" : @(NSBackspaceCharacter),
      @"enter" : @(NSCarriageReturnCharacter),
      @"return" : @(NSCarriageReturnCharacter),
      @"esc" : @(0x1b),
      @"escape" : @(0x1b),
      @"tab" : @(NSTabCharacter),
      @"space" : @(' '),
      @"insert" : @(NSInsertFunctionKey),
      @"ins" : @(NSInsertFunctionKey),
      @"home" : @(NSHomeFunctionKey),
      @"end" : @(NSEndFunctionKey),
      @"pageup" : @(NSPageUpFunctionKey),
      @"pagedown" : @(NSPageDownFunctionKey),
      @"up" : @(NSUpArrowFunctionKey),
      @"down" : @(NSDownArrowFunctionKey),
      @"left" : @(NSLeftArrowFunctionKey),
      @"right" : @(NSRightArrowFunctionKey),
    };
  });
  NSString* lower = key.lowercaseString;
  NSNumber* code = named[lower];
  if (code == nil && [lower hasPrefix:@"f"]) {
    NSInteger n = [lower substringFromIndex:1].integerValue;
    if (n >= 1 && n <= 24 && [[NSString stringWithFormat:@"f%ld", (long)n] isEqualToString:lower]) {
      code = @(NSF1FunctionKey + n - 1);
    }
  }
  if (code == nil) return nil;
  unichar c = (unichar)code.unsignedShortValue;
  return [NSString stringWithCharacters:&c length:1];
}

// Shows a Windows-style shortcut hint ("Ctrl+Shift+1", "Delete", "L") as
// [item]'s key equivalent, so AppKit draws it in the menu's own right-aligned
// shortcut column; words after the keys are dropped. Returns NO, leaving
// [item] alone, when [hint] doesn't start with a shortcut.
// While the menu is open, typing the shortcut picks the item, as in Win32.
static BOOL WDSetKeyEquivalent(NSMenuItem* item, NSString* hint) {
  // "Ctrl+T toggles": AppKit's column has room for the keys only.
  hint = [hint componentsSeparatedByString:@" "].firstObject;
  NSArray<NSString*>* parts = [hint componentsSeparatedByString:@"+"];
  NSEventModifierFlags mask = 0;
  for (NSUInteger i = 0; i + 1 < parts.count; i++) {
    NSString* modifier = parts[i].lowercaseString;
    if ([modifier isEqualToString:@"ctrl"] || [modifier isEqualToString:@"control"]) {
      mask |= NSEventModifierFlagControl;
    } else if ([modifier isEqualToString:@"shift"]) {
      mask |= NSEventModifierFlagShift;
    } else if ([modifier isEqualToString:@"alt"] || [modifier isEqualToString:@"option"]) {
      mask |= NSEventModifierFlagOption;
    } else if ([modifier isEqualToString:@"cmd"] || [modifier isEqualToString:@"meta"]) {
      mask |= NSEventModifierFlagCommand;
    } else {
      return NO;
    }
  }
  NSString* key = WDKeyEquivalent(parts.lastObject);
  if (key == nil) return NO;
  item.keyEquivalent = key;
  // An empty mask matters: AppKit's default is Command.
  item.keyEquivalentModifierMask = mask;
  return YES;
}

static NSMenu* WDBuildMenu(NSArray* items, WDMenuTarget* target) {
  NSMenu* menu = [[NSMenu alloc] initWithTitle:@""];
  menu.autoenablesItems = NO;
  for (NSDictionary* spec in items) {
    if ([spec[@"separator"] boolValue]) {
      [menu addItem:[NSMenuItem separatorItem]];
      continue;
    }
    NSString* label = [spec[@"label"] isKindOfClass:[NSString class]] ? spec[@"label"] : @"";
    NSMenuItem* item = [[NSMenuItem alloc] initWithTitle:label
                                                  action:nil
                                           keyEquivalent:@""];
    item.enabled = spec[@"enabled"] == nil || [spec[@"enabled"] boolValue];
    item.state = [spec[@"checked"] boolValue]   ? NSControlStateValueOn
                 : [spec[@"mixed"] boolValue] ? NSControlStateValueMixed
                                               : NSControlStateValueOff;
    id shortcut = spec[@"shortcut"];
    if ([shortcut isKindOfClass:[NSString class]] && [shortcut length] > 0 &&
        !WDSetKeyEquivalent(item, shortcut)) {
      // A hint that names no key: shown after the title, as Win32 does.
      item.title = [NSString stringWithFormat:@"%@\t%@", item.title, shortcut];
    }
    NSArray* children = spec[@"items"];
    if ([children isKindOfClass:[NSArray class]] && children.count > 0) {
      item.submenu = WDBuildMenu(children, target);
    } else {
      item.tag = [spec[@"id"] integerValue];
      item.target = target;
      item.action = @selector(choose:);
    }
    [menu addItem:item];
  }
  return menu;
}

// Shows a popup menu described by [json] at the global top-left point (x, y)
// and blocks until it closes. Returns the chosen item's id, or -1. [alpha]
// (0..1) is how opaque the menu's windows are, submenus included.
int64_t wd_popup_menu(const char* json, double x, double y, double alpha) {
  NSData* data = [NSData dataWithBytes:json length:strlen(json)];
  NSArray* items = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
  if (![items isKindOfClass:[NSArray class]]) return -1;
  WDMenuTarget* target = [[WDMenuTarget alloc] init];
  target.selected = -1;
  NSMenu* menu = WDBuildMenu(items, target);
  NSPoint location = NSMakePoint(x, WDPrimaryHeight() - y);
  NSTimer* fade = nil;
  if (alpha < 1.0) {
    // The menu tracks in its own run loop mode and its windows are AppKit's,
    // so they are found while it is open (submenus open as it goes).
    CGFloat value = MAX(0.05, alpha);
    fade = [NSTimer timerWithTimeInterval:0.02
                                  repeats:YES
                                    block:^(NSTimer* timer) {
                                      for (NSWindow* window in NSApp.windows) {
                                        if ([NSStringFromClass([window class])
                                                containsString:@"MenuWindow"] &&
                                            window.alphaValue != value) {
                                          window.alphaValue = value;
                                        }
                                      }
                                    }];
    [[NSRunLoop currentRunLoop] addTimer:fade forMode:NSRunLoopCommonModes];
  }
  [menu popUpMenuPositioningItem:nil atLocation:location inView:nil];
  [fade invalidate];
  return target.selected;
}

// --- Window shapes ---------------------------------------------------------

// Shaped windows (SetWindowRgn in the original): outside its shape a window
// ignores the mouse, so clicks reach whatever is underneath. AppKit has no
// window regions, so the window's ignoresMouseEvents is toggled as the pointer
// moves in and out of the shape. Paths are in top-left window coordinates.
static NSMapTable<NSWindow*, NSBezierPath*>* WDShapes;
static id WDShapeLocalMonitor;
static id WDShapeGlobalMonitor;

static void WDUpdateShapedWindows(void) {
  // Leave the state alone mid-drag so a drag that leaves the shape keeps its
  // capture.
  if ([NSEvent pressedMouseButtons] != 0) return;
  NSPoint location = [NSEvent mouseLocation];
  for (NSWindow* window in WDShapes) {
    NSBezierPath* shape = [WDShapes objectForKey:window];
    NSRect frame = window.frame;
    BOOL ignore = NO;
    if (window.visible && NSPointInRect(location, frame)) {
      NSPoint local = NSMakePoint(location.x - frame.origin.x,
                                  NSMaxY(frame) - location.y);
      ignore = ![shape containsPoint:local];
    }
    if (window.ignoresMouseEvents != ignore) window.ignoresMouseEvents = ignore;
  }
}

static void WDEnsureShapeMonitors(void) {
  if (WDShapes != nil) return;
  WDShapes = [NSMapTable weakToStrongObjectsMapTable];
  NSEventMask mask = NSEventMaskMouseMoved;
  // Local events arrive while the pointer is over our (non-ignoring) windows,
  // global ones while it is over other apps' windows -- including through an
  // ignoring window of ours.
  WDShapeLocalMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:mask
                                                              handler:^NSEvent*(NSEvent* event) {
                                                                WDUpdateShapedWindows();
                                                                return event;
                                                              }];
  WDShapeGlobalMonitor = [NSEvent addGlobalMonitorForEventsMatchingMask:mask
                                                                handler:^(NSEvent* event) {
                                                                  WDUpdateShapedWindows();
                                                                }];
}

// Sets the window's shape to [polygonCount] polygons; polygon i has counts[i]
// points, read in order from [points] as x,y pairs. A count of 0 polygons
// removes the shape.
void wd_set_shape(void* handle, const double* points, const int32_t* counts,
                  int32_t polygonCount) {
  NSWindow* window = (__bridge NSWindow*)handle;
  if (window == nil) return;
  WDEnsureShapeMonitors();
  if (polygonCount <= 0) {
    [WDShapes removeObjectForKey:window];
    window.ignoresMouseEvents = NO;
    return;
  }
  NSBezierPath* path = [NSBezierPath bezierPath];
  path.windingRule = NSWindingRuleNonZero;
  int offset = 0;
  for (int i = 0; i < polygonCount; i++) {
    for (int j = 0; j < counts[i]; j++) {
      NSPoint p = NSMakePoint(points[(offset + j) * 2], points[(offset + j) * 2 + 1]);
      if (j == 0) {
        [path moveToPoint:p];
      } else {
        [path lineToPoint:p];
      }
    }
    [path closePath];
    offset += counts[i];
  }
  [WDShapes setObject:path forKey:window];
  WDUpdateShapedWindows();
}

// --- Blur behind glass --------------------------------------------------------

// Skins with translucent glass (GlassAMP, Resin) look right only when what
// shows through is blurred, as a window manager's backdrop does. An
// NSVisualEffectView behind the Flutter view blurs what is behind the window,
// and its mask keeps that to the glass. [alpha] is a w*h byte image, rows from
// the top, whose opaque pixels are the glass; w == 0 takes the blur away.
void wd_set_blur(void* handle, const uint8_t* alpha, int32_t w, int32_t h) {
  NSWindow* window = (__bridge NSWindow*)handle;
  if (window == nil) return;
  NSView* content = window.contentView;
  static NSString* const kIdentifier = @"WDBlurBehindGlass";
  NSVisualEffectView* effect = nil;
  for (NSView* view in content.subviews) {
    if ([view.identifier isEqualToString:kIdentifier]) effect = (NSVisualEffectView*)view;
  }
  if (w <= 0 || h <= 0 || alpha == NULL) {
    [effect removeFromSuperview];
    return;
  }
  if (effect == nil) {
    effect = [[NSVisualEffectView alloc] initWithFrame:content.bounds];
    effect.identifier = kIdentifier;
    effect.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    effect.state = NSVisualEffectStateActive;
    effect.material = NSVisualEffectMaterialUnderWindowBackground;
    effect.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
    effect.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    // Under the Flutter view, which draws the glass itself.
    [content addSubview:effect positioned:NSWindowBelow relativeTo:nil];
  }
  effect.frame = content.bounds;
  // A layer mask rather than `maskImage`, which drew the window's own picture
  // again, small, in a corner.
  size_t count = (size_t)w * (size_t)h;
  CFMutableDataRef pixels = CFDataCreateMutable(NULL, count * 4);
  CFDataSetLength(pixels, count * 4);
  uint8_t* out = CFDataGetMutableBytePtr(pixels);
  for (size_t i = 0; i < count; i++) {
    // Premultiplied black: only the alpha counts for a mask.
    out[i * 4] = 0;
    out[i * 4 + 1] = 0;
    out[i * 4 + 2] = 0;
    out[i * 4 + 3] = alpha[i];
  }
  CGDataProviderRef provider = CGDataProviderCreateWithCFData(pixels);
  CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
  CGImageRef image = CGImageCreate(w, h, 8, 32, (size_t)w * 4, space,
                                   kCGBitmapByteOrderDefault | kCGImageAlphaPremultipliedLast,
                                   provider, NULL, false, kCGRenderingIntentDefault);
  CGColorSpaceRelease(space);
  CGDataProviderRelease(provider);
  CFRelease(pixels);
  effect.wantsLayer = YES;
  CALayer* mask = [CALayer layer];
  mask.frame = effect.bounds;
  mask.contents = (__bridge id)image;
  mask.contentsGravity = kCAGravityResize;
  mask.magnificationFilter = kCAFilterLinear;
  effect.layer.mask = mask;
  CGImageRelease(image);
}
