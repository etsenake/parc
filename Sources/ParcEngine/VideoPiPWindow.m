// Copyright 2026 Parc contributors.
#import "VideoPiPWindow.h"

#import "page_host.h"

#import <QuartzCore/QuartzCore.h>
#include <dlfcn.h>
#include <math.h>

@interface PCVideoPiPSystemSeams : NSObject <PCNativePresentation, PCNativeScheduling>
@property(class, nonatomic, readonly) PCVideoPiPSystemSeams* sharedSeams;
@end
@implementation PCVideoPiPSystemSeams
+ (PCVideoPiPSystemSeams*)sharedSeams {
  static PCVideoPiPSystemSeams* shared;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    shared = [[PCVideoPiPSystemSeams alloc] init];
  });
  return shared;
}
- (NSWindow*)attachedSheetOfWindow:(NSWindow*)window {
  return window.attachedSheet;
}
- (NSWindow*)sheetParentOfWindow:(NSWindow*)window {
  return window.sheetParent;
}
- (NSWindow*)parentWindowOfWindow:(NSWindow*)window {
  return window.parentWindow;
}
- (NSArray<NSWindow*>*)childWindowsOfWindow:(NSWindow*)window {
  return window.childWindows;
}
- (BOOL)isWindowVisible:(NSWindow*)window {
  return window.visible;
}
- (void)window:(NSWindow*)window
           beginSheet:(NSWindow*)sheet
    completionHandler:(void (^)(NSModalResponse))handler {
  [window beginSheet:sheet completionHandler:handler];
}
- (void)window:(NSWindow*)window endSheet:(NSWindow*)sheet {
  [window endSheet:sheet];
}
- (void)window:(NSWindow*)window endSheet:(NSWindow*)sheet returnCode:(NSModalResponse)code {
  [window endSheet:sheet returnCode:code];
}
- (void)endApplicationSheet:(NSWindow*)sheet {
  [NSApp endSheet:sheet];
}
- (void)window:(NSWindow*)window
    addChildWindow:(NSWindow*)child
           ordered:(NSWindowOrderingMode)place {
  [window addChildWindow:child ordered:place];
}
- (void)window:(NSWindow*)window removeChildWindow:(NSWindow*)child {
  [window removeChildWindow:child];
}
- (void)orderFrontWindow:(NSWindow*)window {
  [window orderFront:nil];
}
- (void)makeKeyAndOrderFrontWindow:(NSWindow*)window {
  [window makeKeyAndOrderFront:nil];
}
- (void)makeKeyWindow:(NSWindow*)window {
  [window makeKeyWindow];
}
- (void)orderOutWindow:(NSWindow*)window {
  [window orderOut:nil];
}
- (void)closeWindow:(NSWindow*)window {
  [window close];
}
- (NSPopover*)makePopover {
  return [NSPopover new];
}
- (NSTimeInterval)systemUptime {
  return NSProcessInfo.processInfo.systemUptime;
}
- (NSDate*)currentDate {
  return [NSDate date];
}
- (NSTimeInterval)timeIntervalSinceNowForDate:(NSDate*)date {
  return [date timeIntervalSinceNow];
}
- (NSTimer*)timerWithTimeInterval:(NSTimeInterval)interval
                          repeats:(BOOL)repeats
                            block:(void (^)(NSTimer*))block {
  return [NSTimer timerWithTimeInterval:interval repeats:repeats block:block];
}
- (NSTimer*)scheduledTimerWithTimeInterval:(NSTimeInterval)interval
                                   repeats:(BOOL)repeats
                                     block:(void (^)(NSTimer*))block {
  return [NSTimer scheduledTimerWithTimeInterval:interval repeats:repeats block:block];
}
- (void)addTimer:(NSTimer*)timer forMode:(NSRunLoopMode)mode {
  [[NSRunLoop mainRunLoop] addTimer:timer forMode:mode];
}
- (void)performInModes:(NSArray<NSRunLoopMode>*)modes block:(void (^)(void))block {
  [[NSRunLoop mainRunLoop] performInModes:modes block:block];
}
- (void)dispatchToMainQueue:(dispatch_block_t)block {
  dispatch_async(dispatch_get_main_queue(), block);
}
- (void)runAnimationGroup:(void (^)(NSAnimationContext*))changes
        completionHandler:(void (^)(void))completion {
  [NSAnimationContext runAnimationGroup:changes completionHandler:completion];
}
@end

@interface PCVideoPiPSlider : NSSlider
@property(nonatomic, copy) void (^scrubbingChanged)(BOOL);
@end
@implementation PCVideoPiPSlider
- (void)mouseDown:(NSEvent*)event {
  void (^changed)(BOOL) = self.scrubbingChanged;
  if (changed) changed(YES);
  @try {
    [super mouseDown:event];
  } @finally {
    if (changed) changed(NO);
  }
}
@end

static const CGFloat kPCVideoPiPCornerRadius = 16;
static const CGFloat kPCVideoPiPNormalWidth = 512;
static const CGFloat kPCVideoPiPMinWidth = 284;
static const CGFloat kPCVideoPiPMinHeight = 160;
static const CGFloat kPCVideoPiPChromeButton = 28;
static const CGFloat kPCVideoPiPPlayButton = 56;
static const NSTimeInterval kPCVideoPiPProgressInterval = 1.0 / 30.0;

static BOOL PCVideoPiPValidSize(NSSize size) {
  return size.width > 0 && size.height > 0 && isfinite(size.width) &&
         isfinite(size.height);
}

static NSRect PCVideoPiPWorkArea(NSScreen* screen) {
  screen = screen ?: NSScreen.mainScreen ?: NSScreen.screens.firstObject;
  return screen ? screen.visibleFrame : NSMakeRect(0, 0, 1280, 800);
}

static NSSize PCVideoPiPSizeForAspect(CGFloat width, CGFloat aspect,
                                      NSRect work) {
  CGFloat height = width / aspect;
  if (height < kPCVideoPiPMinHeight) {
    height = kPCVideoPiPMinHeight;
    width = height * aspect;
  }
  if (width < kPCVideoPiPMinWidth) {
    width = kPCVideoPiPMinWidth;
    height = width / aspect;
  }
  if (height > NSHeight(work)) {
    height = NSHeight(work);
    width = height * aspect;
  }
  if (width > NSWidth(work)) {
    width = NSWidth(work);
    height = width / aspect;
  }
  return NSMakeSize(round(width), round(height));
}

static NSRect PCVideoPiPFrameForNaturalSize(NSSize natural) {
  const NSRect work = PCVideoPiPWorkArea(nil);
  const NSSize size =
      PCVideoPiPValidSize(natural)
          ? PCVideoPiPSizeForAspect(kPCVideoPiPNormalWidth,
                                    natural.width / natural.height, work)
          : NSMakeSize(kPCVideoPiPNormalWidth, kPCVideoPiPNormalWidth * 9 / 16);
  const CGFloat unused_w = fmax(0, work.size.width - size.width);
  const CGFloat unused_h = fmax(0, work.size.height - size.height);
  const CGFloat buffer = (unused_w + unused_h) / 2.0 * 0.02;
  return NSMakeRect(NSMaxX(work) - size.width - buffer, NSMinY(work) + buffer,
                    size.width, size.height);
}

static NSRect PCVideoPiPFrameRefitted(NSRect frame, NSSize natural,
                                      NSRect work) {
  const NSSize size = PCVideoPiPSizeForAspect(
      NSWidth(frame), natural.width / natural.height, work);
  CGFloat x = NSMidX(frame) >= NSMidX(work) ? NSMaxX(frame) - size.width
                                            : NSMinX(frame);
  CGFloat y = NSMidY(frame) >= NSMidY(work) ? NSMaxY(frame) - size.height
                                            : NSMinY(frame);
  x = fmin(fmax(x, NSMinX(work)), NSMaxX(work) - size.width);
  y = fmin(fmax(y, NSMinY(work)), NSMaxY(work) - size.height);
  return NSMakeRect(x, y, size.width, size.height);
}

static NSRect PCVideoPiPVideoRect(NSRect bounds, NSSize natural) {
  if (!PCVideoPiPValidSize(natural) || NSIsEmptyRect(bounds)) {
    return bounds;
  }
  const CGFloat aspect = natural.width / natural.height;
  CGFloat width = NSWidth(bounds);
  CGFloat height = NSHeight(bounds);
  if (width / height > aspect) {
    width = height * aspect;
  } else {
    height = width / aspect;
  }
  width = NSWidth(bounds) - width < 1 ? NSWidth(bounds) : round(width);
  height = NSHeight(bounds) - height < 1 ? NSHeight(bounds) : round(height);
  return NSMakeRect(round(NSMidX(bounds) - width / 2),
                    round(NSMidY(bounds) - height / 2), width, height);
}

typedef int PCCGSConnection;
@implementation PCVideoPiPEnvironment {
  PCCGSConnection (*_connection)(void);
  int (*_setProperty)(PCCGSConnection, PCCGSConnection, CFStringRef, CFTypeRef);
  BOOL _resolved;
}
+ (PCVideoPiPEnvironment*)system {
  static PCVideoPiPEnvironment* shared;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    shared = [[PCVideoPiPEnvironment alloc] init];
  });
  return shared;
}
- (void)setCursor:(NSCursor*)cursor {
  [cursor set];
}
- (NSPoint)mouseLocation {
  return NSEvent.mouseLocation;
}
- (id)addLocalMonitorForMask:(NSEventMask)mask
                     handler:(NSEvent* (^)(NSEvent*))handler {
  return [NSEvent addLocalMonitorForEventsMatchingMask:mask handler:handler];
}
- (id)addGlobalMonitorForMask:(NSEventMask)mask
                      handler:(void (^)(NSEvent*))handler {
  return [NSEvent addGlobalMonitorForEventsMatchingMask:mask handler:handler];
}
- (void)removeMonitor:(id)monitor {
  [NSEvent removeMonitor:monitor];
}
- (void*)symbolNamed:(const char*)name {
  return dlsym(RTLD_DEFAULT, name);
}
- (BOOL)isWindowInLiveResize:(NSWindow*)window {
  return window.inLiveResize;
}
- (void)setSetsCursorInBackground:(BOOL)on {
  @synchronized(self) {
    if (!_resolved) {
      _resolved = YES;
      _connection =
          (PCCGSConnection(*)(void))[self symbolNamed:"CGSMainConnectionID"];
      _setProperty = (int (*)(PCCGSConnection, PCCGSConnection, CFStringRef,
                              CFTypeRef))
          [self symbolNamed:"CGSSetConnectionProperty"];
    }
  }
  if (_connection && _setProperty) {
    _setProperty(_connection(), _connection(), CFSTR("SetsCursorInBackground"),
                 on ? kCFBooleanTrue : kCFBooleanFalse);
  }
}
@end
void PCPictureInPicturePointAtControlInEnvironment(
    BOOL control, PCVideoPiPEnvironment* environment) {
  static NSInteger pointing;
  if (control) {
    if (pointing++ == 0) {
      [environment setSetsCursorInBackground:YES];
    }
    [environment setCursor:NSCursor.pointingHandCursor];
  } else if (pointing > 0 && --pointing == 0) {
    [environment setCursor:NSCursor.arrowCursor];
    [environment setSetsCursorInBackground:NO];
  }
}
void PCPictureInPicturePointAtControl(BOOL control) {
  PCPictureInPicturePointAtControlInEnvironment(
      control, PCVideoPiPEnvironment.system);
}

static NSImage* PCVideoPiPSymbol(NSString* name, CGFloat pointSize) {
  NSImage* image = [NSImage imageWithSystemSymbolName:name
                             accessibilityDescription:nil];
  if (!image) {
    return nil;
  }
  NSImageSymbolConfiguration* config = [NSImageSymbolConfiguration
      configurationWithPointSize:pointSize
                          weight:NSFontWeightMedium];
  return [image imageWithSymbolConfiguration:config] ?: image;
}

@interface PCVideoPiPPanel : NSPanel
@end
@implementation PCVideoPiPPanel
- (BOOL)canBecomeKeyWindow {
  return NO;
}
@end

@interface PCVideoPiPChromeButton : NSButton
@property(nonatomic, readonly) NSView* hostView;
@property(nonatomic) BOOL hovered;
@end
@implementation PCVideoPiPChromeButton {
  NSView* _hostView;
}
@synthesize hostView = _hostView;
@synthesize hovered = _hovered;
- (instancetype)initWithFrame:(NSRect)frame {
  if (!(self = [super initWithFrame:frame])) {
    return nil;
  }
  self.alphaValue = 0.925;
  self.bordered = NO;
  self.buttonType = NSButtonTypeMomentaryChange;
  self.imagePosition = NSImageOnly;
  self.contentTintColor = NSColor.whiteColor;
  if (@available(macOS 26.0, *)) {
    NSGlassEffectView* glass = [[NSGlassEffectView alloc] initWithFrame:frame];
    glass.translatesAutoresizingMaskIntoConstraints = NO;
    glass.style = NSGlassEffectViewStyleClear;
    if (@available(macOS 27.0, *)) {
      glass.effectIsInteractive = YES;
    }
    glass.contentView = self;
    _hostView = glass;
  } else {
    self.translatesAutoresizingMaskIntoConstraints = NO;
    self.wantsLayer = YES;
    self.layer.backgroundColor =
        [NSColor colorWithWhite:0.12 alpha:0.55].CGColor;
    self.layer.cornerCurve = kCACornerCurveContinuous;
    _hostView = self;
  }
  return self;
}
- (NSEdgeInsets)alignmentRectInsets {
  return NSEdgeInsetsZero;
}
- (void)layout {
  [super layout];
  const CGFloat side = fmin(NSWidth(_hostView.bounds), NSHeight(_hostView.bounds));
  const CGFloat radius = side * 0.5;
  if (@available(macOS 26.0, *)) {
    if ([_hostView isKindOfClass:NSGlassEffectView.class]) {
      ((NSGlassEffectView*)_hostView).cornerRadius = radius;
    }
  } else if (self.layer) {
    self.layer.cornerRadius = radius;
  }
}
- (void)resetCursorRects {
  [self addCursorRect:self.bounds cursor:NSCursor.pointingHandCursor];
}
- (void)mouseDown:(NSEvent*)event {
  __attribute__((objc_precise_lifetime)) PCVideoPiPChromeButton* keep = self;
  keep.alphaValue = 0.7;
  [super mouseDown:event];
  keep.alphaValue = keep->_hovered ? 1 : 0.925;
}
- (void)setHovered:(BOOL)hovered {
  if (_hovered == hovered) {
    return;
  }
  _hovered = hovered;
  self.alphaValue = hovered ? 1 : 0.925;
  CALayer* layer = _hostView.layer;
  if (!layer) {
    return;
  }
  const CGFloat scale = hovered ? 1.1 : 1;
  const CGFloat dx = NSWidth(_hostView.bounds) * (0.5 - layer.anchorPoint.x);
  const CGFloat dy = NSHeight(_hostView.bounds) * (0.5 - layer.anchorPoint.y);
  const CATransform3D to = CATransform3DTranslate(
      CATransform3DScale(CATransform3DMakeTranslation(dx, dy, 0), scale, scale,
                         1),
      -dx, -dy, 0);
  CABasicAnimation* animation =
      [CABasicAnimation animationWithKeyPath:@"transform"];
  animation.fromValue = [NSValue
      valueWithCATransform3D:(layer.presentationLayer ?: layer).transform];
  animation.toValue = [NSValue valueWithCATransform3D:to];
  animation.duration = 0.3;
  animation.timingFunction =
      [CAMediaTimingFunction functionWithControlPoints:0.25:0.1:0.25:1];
  [layer addAnimation:animation forKey:@"hover"];
  layer.transform = to;
}
@end

@interface PCVideoPiPCaptions : NSView
@property(nonatomic) NSImage* image;
@end
@implementation PCVideoPiPCaptions
@synthesize image = _image;
- (void)setImage:(NSImage*)image {
  _image = image;
  self.needsDisplay = YES;
}
- (BOOL)wantsUpdateLayer {
  return YES;
}
- (void)updateLayer {
  self.layer.contents = _image;
}
- (NSView*)hitTest:(NSPoint)point {
  (void)point;
  return nil;
}
@end

@interface PCVideoPiPContent : NSView
@property(nonatomic, copy) dispatch_block_t changed;
@property(nonatomic, copy) void (^hoverChanged)(BOOL hovering);
@property(nonatomic, strong) id<PCNativePresentation> presentation;
@property(nonatomic, strong) PCVideoPiPEnvironment* environment;
@end
@implementation PCVideoPiPContent {
  NSTrackingArea* _tracking;
}
@synthesize environment = _environment;
@synthesize changed = _changed;
@synthesize hoverChanged = _hoverChanged;
@synthesize presentation = _presentation;
- (void)updateTrackingAreas {
  [super updateTrackingAreas];
  if (_tracking) {
    [self removeTrackingArea:_tracking];
  }
  _tracking = [[NSTrackingArea alloc]
      initWithRect:self.bounds
           options:NSTrackingMouseEnteredAndExited | NSTrackingMouseMoved |
                   NSTrackingActiveAlways | NSTrackingInVisibleRect |
                   NSTrackingEnabledDuringMouseDrag
             owner:self
          userInfo:nil];
  [self addTrackingArea:_tracking];
}
- (void)mouseEntered:(NSEvent*)event {
  (void)event;
  void (^callback)(BOOL) = self.hoverChanged;
  if (callback) {
    callback(YES);
  }
}
- (void)mouseExited:(NSEvent*)event {
  (void)event;
  NSWindow* window = self.window;
  if (window && [_presentation isWindowVisible:window] &&
      NSPointInRect([_environment mouseLocation], window.frame)) {
    return;
  }
  void (^callback)(BOOL) = self.hoverChanged;
  if (callback) {
    callback(NO);
  }
}
- (void)mouseMoved:(NSEvent*)event {
  (void)event;
  void (^callback)(BOOL) = self.hoverChanged;
  if (callback) {
    callback(YES);
  }
}
- (void)mouseDown:(NSEvent*)event {
  [self.window performWindowDragWithEvent:event];
}
- (void)setFrameSize:(NSSize)size {
  [super setFrameSize:size];
  dispatch_block_t callback = self.changed;
  if (callback) {
    callback();
  }
}
@end

@implementation PCVideoPiPPresenter {
  NSPanel* _panel;
  BOOL _shown;
  NSView* _videoView;
  PCVideoPiPCaptions* _captions;
  NSRect _captionBounds;
  BOOL _captionsLiftedForScrubber;
  NSView* _chrome;
  NSButton* _backButton;
  NSButton* _minimizeButton;
  NSButton* _closeButton;
  NSButton* _playButton;
  NSTextField* _title;
  NSImageView* _favicon;
  NSSlider* _position;
  NSMutableDictionary<NSNumber*, NSButton*>* _buttons;
  void (^_action)(PCVideoPiPAction, double);
  dispatch_block_t _changed;
  id _localMonitor;
  id _globalMonitor;
  BOOL _invalidated;
  NSSize _naturalSize;
  BOOL _hovering;
  BOOL _controlsEnabled;
  BOOL _playing;
  double _mediaPosition;
  double _mediaDuration;
  double _playbackRate;
  NSDate* _positionSampleAt;
  NSTimer* _progressTimer;
  __weak PCVideoPiPChromeButton* _pointed;
  NSSize _pendingNaturalSize;
  id<PCNativePresentation> _presentation;
  PCVideoPiPEnvironment* _environment;
}
@synthesize scheduler = _scheduler;
- (id<PCNativePresentation>)presentation {
  return _presentation;
}
- (void)setPresentation:(id<PCNativePresentation>)presentation {
  _presentation = presentation;
  ((PCVideoPiPContent*)_panel.contentView).presentation = presentation;
}

- (NSButton*)makeChromeButton:(NSString*)symbol
                        action:(PCVideoPiPAction)action
                         label:(NSString*)label
                          size:(CGFloat)size {
  PCVideoPiPChromeButton* button =
      [[PCVideoPiPChromeButton alloc] initWithFrame:NSMakeRect(0, 0, size, size)];
  button.image = PCVideoPiPSymbol(symbol, size * 0.42);
  button.tag = action;
  button.accessibilityLabel = label;
  button.target = self;
  button.action = @selector(performAction:);
  NSView* host = button.hostView;
  [host.widthAnchor constraintEqualToConstant:size].active = YES;
  [host.heightAnchor constraintEqualToConstant:size].active = YES;
  if (@available(macOS 26.0, *)) {
    if ([host isKindOfClass:NSGlassEffectView.class]) {
      ((NSGlassEffectView*)host).cornerRadius = size * 0.5;
    }
  }
  return button;
}

- (instancetype)initWithVideoView:(NSView*)videoView
                      sourceFrame:(NSRect)sourceFrame
                           action:(void (^)(PCVideoPiPAction, double))action
                          changed:(dispatch_block_t)changed {
  return [self initWithVideoView:videoView
                     sourceFrame:sourceFrame
                          action:action
                         changed:changed
                     environment:PCVideoPiPEnvironment.system];
}

- (instancetype)initWithVideoView:(NSView*)videoView
                      sourceFrame:(NSRect)sourceFrame
                           action:(void (^)(PCVideoPiPAction, double))action
                          changed:(dispatch_block_t)changed
                      environment:(PCVideoPiPEnvironment*)environment {
  if (!(self = [super init])) {
    return nil;
  }
  (void)sourceFrame;
  _environment = environment;
  _videoView = videoView;
  _action = [action copy];
  _changed = [changed copy];
  _controlsEnabled = YES;
  _buttons = [NSMutableDictionary new];
  _presentation = PCVideoPiPSystemSeams.sharedSeams;
  _scheduler = PCVideoPiPSystemSeams.sharedSeams;
  NSRect frame = PCVideoPiPFrameForNaturalSize(NSZeroSize);
  _panel = [[PCVideoPiPPanel alloc]
      initWithContentRect:frame
                styleMask:NSWindowStyleMaskNonactivatingPanel |
                          NSWindowStyleMaskResizable
                  backing:NSBackingStoreBuffered
                    defer:NO];
  _panel.releasedWhenClosed = NO;
  _panel.delegate = self;
  _panel.floatingPanel = YES;
  _panel.level = NSFloatingWindowLevel;
  _panel.hidesOnDeactivate = NO;
  _panel.opaque = NO;
  _panel.backgroundColor = NSColor.clearColor;
  _panel.hasShadow = YES;
  _panel.acceptsMouseMovedEvents = YES;
  _panel.ignoresMouseEvents = NO;
  _panel.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces |
                              NSWindowCollectionBehaviorFullScreenAuxiliary;
  _panel.movableByWindowBackground = NO;

  PCVideoPiPContent* content =
      [[PCVideoPiPContent alloc] initWithFrame:NSMakeRect(0, 0, frame.size.width,
                                                          frame.size.height)];
  content.wantsLayer = YES;
  content.layer.backgroundColor = NSColor.blackColor.CGColor;
  content.layer.cornerRadius = kPCVideoPiPCornerRadius;
  content.layer.cornerCurve = kCACornerCurveContinuous;
  content.layer.masksToBounds = YES;
  content.presentation = _presentation;
  content.environment = _environment;
  _panel.contentView = content;

  _videoView.frame = content.bounds;
  _videoView.wantsLayer = YES;
  _videoView.layer.cornerRadius = kPCVideoPiPCornerRadius;
  _videoView.layer.cornerCurve = kCACornerCurveContinuous;
  _videoView.layer.masksToBounds = YES;
  [content addSubview:_videoView];

  _captions = [[PCVideoPiPCaptions alloc] initWithFrame:NSZeroRect];
  _captions.wantsLayer = YES;
  _captions.hidden = YES;
  [content addSubview:_captions];

  _chrome = [[NSView alloc] initWithFrame:content.bounds];
  _chrome.wantsLayer = YES;
  _chrome.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  _chrome.alphaValue = 0;
  _chrome.hidden = YES;
  [content addSubview:_chrome];

  _backButton = [self makeChromeButton:@"arrow.up.left"
                                action:PCVideoPiPReturn
                                 label:@"Return to Tab"
                                  size:kPCVideoPiPChromeButton];
  _minimizeButton = [self makeChromeButton:@"minus"
                                    action:PCVideoPiPMinimize
                                     label:@"Hide"
                                      size:kPCVideoPiPChromeButton];
  _closeButton = [self makeChromeButton:@"xmark"
                                 action:PCVideoPiPClose
                                  label:@"Close"
                                   size:kPCVideoPiPChromeButton];
  _playButton = [self makeChromeButton:@"pause.fill"
                                action:PCVideoPiPPlayPause
                                 label:@"Pause"
                                  size:kPCVideoPiPPlayButton];
  _playButton.image = PCVideoPiPSymbol(@"pause.fill", 22);

  _title = [NSTextField labelWithString:@""];
  _title.textColor = NSColor.whiteColor;
  _title.font = [NSFont systemFontOfSize:12 weight:NSFontWeightMedium];
  _title.alignment = NSTextAlignmentCenter;
  _title.translatesAutoresizingMaskIntoConstraints = NO;
  _title.lineBreakMode = NSLineBreakByTruncatingTail;
  _title.drawsBackground = NO;

  _favicon = [NSImageView new];
  _favicon.translatesAutoresizingMaskIntoConstraints = NO;
  _favicon.imageScaling = NSImageScaleProportionallyUpOrDown;
  _favicon.wantsLayer = YES;
  _favicon.layer.cornerRadius = 4;
  _favicon.layer.masksToBounds = YES;

  _position = [PCVideoPiPSlider sliderWithValue:0
                               minValue:0
                               maxValue:0
                                 target:self
                                 action:@selector(seek:)];
  __weak PCVideoPiPPresenter* weakPresenter = self;
  ((PCVideoPiPSlider*)_position).scrubbingChanged = ^(BOOL scrubbing) {
    PCVideoPiPPresenter* presenter = weakPresenter;
    if (!presenter || presenter->_invalidated) return;
    void (^callback)(PCVideoPiPAction, double) = [presenter->_action copy];
    if (callback)
      callback(scrubbing ? PCVideoPiPBeginScrubbing : PCVideoPiPEndScrubbing, 0);
  };
  _position.translatesAutoresizingMaskIntoConstraints = NO;
  _position.controlSize = NSControlSizeMini;
  _position.accessibilityLabel = @"Playback position";

  NSButton* mute = [self makeChromeButton:@"speaker.wave.2.fill"
                                   action:PCVideoPiPMute
                                    label:@"Mute"
                                     size:kPCVideoPiPChromeButton];

  NSView* backHost = ((PCVideoPiPChromeButton*)_backButton).hostView;
  NSView* minimizeHost = ((PCVideoPiPChromeButton*)_minimizeButton).hostView;
  NSView* closeHost = ((PCVideoPiPChromeButton*)_closeButton).hostView;
  NSView* playHost = ((PCVideoPiPChromeButton*)_playButton).hostView;
  NSView* muteHost = ((PCVideoPiPChromeButton*)mute).hostView;
  [_chrome addSubview:backHost];
  [_chrome addSubview:minimizeHost];
  [_chrome addSubview:closeHost];
  [_chrome addSubview:playHost];
  [_chrome addSubview:_title];
  [_chrome addSubview:_favicon];
  [_chrome addSubview:_position];
  [_chrome addSubview:muteHost];

  _buttons[@(PCVideoPiPReturn)] = _backButton;
  _buttons[@(PCVideoPiPMinimize)] = _minimizeButton;
  _buttons[@(PCVideoPiPClose)] = _closeButton;
  _buttons[@(PCVideoPiPPlayPause)] = _playButton;
  _buttons[@(PCVideoPiPMute)] = mute;

  [NSLayoutConstraint activateConstraints:@[
    [backHost.leadingAnchor constraintEqualToAnchor:_chrome.leadingAnchor
                                           constant:10],
    [backHost.topAnchor constraintEqualToAnchor:_chrome.topAnchor constant:10],

    [closeHost.trailingAnchor constraintEqualToAnchor:_chrome.trailingAnchor
                                             constant:-10],
    [closeHost.topAnchor constraintEqualToAnchor:_chrome.topAnchor constant:10],
    [minimizeHost.trailingAnchor constraintEqualToAnchor:closeHost.leadingAnchor
                                                constant:-6],
    [minimizeHost.centerYAnchor constraintEqualToAnchor:closeHost.centerYAnchor],

    [_title.centerXAnchor constraintEqualToAnchor:_chrome.centerXAnchor],
    [_title.centerYAnchor constraintEqualToAnchor:backHost.centerYAnchor],
    [_title.leadingAnchor
        constraintGreaterThanOrEqualToAnchor:backHost.trailingAnchor
                                    constant:8],
    [_title.trailingAnchor
        constraintLessThanOrEqualToAnchor:minimizeHost.leadingAnchor
                                 constant:-8],
    [_title.widthAnchor constraintLessThanOrEqualToConstant:280],

    [playHost.centerXAnchor constraintEqualToAnchor:_chrome.centerXAnchor],
    [playHost.centerYAnchor constraintEqualToAnchor:_chrome.centerYAnchor],

    [_position.leadingAnchor constraintEqualToAnchor:_chrome.leadingAnchor
                                            constant:12],
    [_position.trailingAnchor constraintEqualToAnchor:_favicon.leadingAnchor
                                             constant:-8],
    [_position.bottomAnchor constraintEqualToAnchor:_chrome.bottomAnchor
                                           constant:-12],

    [_favicon.trailingAnchor constraintEqualToAnchor:_chrome.trailingAnchor
                                            constant:-12],
    [_favicon.centerYAnchor constraintEqualToAnchor:_position.centerYAnchor],
    [_favicon.widthAnchor constraintEqualToConstant:18],
    [_favicon.heightAnchor constraintEqualToConstant:18],

    [muteHost.trailingAnchor constraintEqualToAnchor:_chrome.trailingAnchor
                                            constant:-10],
    [muteHost.bottomAnchor constraintEqualToAnchor:_position.topAnchor
                                          constant:-8],
  ]];

  __weak PCVideoPiPPresenter* weakSelf = self;
  content.changed = ^{
    [weakSelf layoutVideo];
    [weakSelf notifyChanged];
  };
  content.hoverChanged = ^(BOOL hovering) {
    [weakSelf setHovering:hovering];
    [weakSelf refreshPointer];
  };
  [self installMouseMonitors];
  return self;
}

- (void)installMouseMonitors {
  __weak PCVideoPiPPresenter* weakSelf = self;
  NSEventMask mask = NSEventMaskMouseMoved | NSEventMaskLeftMouseDragged |
                     NSEventMaskLeftMouseUp | NSEventMaskLeftMouseDown;
  _localMonitor =
      [_environment addLocalMonitorForMask:mask
                                    handler:^NSEvent*(NSEvent* event) {
                                      [weakSelf refreshHoverFromMouse];
                                      return event;
                                    }];
  _globalMonitor = [_environment
      addGlobalMonitorForMask:NSEventMaskMouseMoved | NSEventMaskLeftMouseDragged
                      handler:^(NSEvent* event) {
                        (void)event;
                        [weakSelf refreshHoverFromMouse];
                      }];
}

- (void)removeMouseMonitors {
  if (_localMonitor) {
    [_environment removeMonitor:_localMonitor];
    _localMonitor = nil;
  }
  if (_globalMonitor) {
    [_environment removeMonitor:_globalMonitor];
    _globalMonitor = nil;
  }
}

- (void)refreshHoverFromMouse {
  if (_invalidated) {
    [self setHovering:NO];
    return;
  }
  if (![_presentation isWindowVisible:_panel]) {
    return;
  }
  NSPoint screenPoint = [_environment mouseLocation];
  const BOOL inside = NSPointInRect(screenPoint, _panel.frame);
  [self setHovering:inside];
  [self refreshPointer];
}

- (void)refreshPointer {
  PCVideoPiPChromeButton* button = nil;
  if (!_invalidated && [_presentation isWindowVisible:_panel] && !_chrome.hidden) {
    NSView* content = _panel.contentView;
    const NSPoint point =
        [content.superview convertPoint:[_panel convertPointFromScreen:
                                                    [_environment mouseLocation]]
                               fromView:nil];
    for (NSView* view = [content hitTest:point]; view && view != content;
         view = view.superview) {
      if ([view isKindOfClass:PCVideoPiPChromeButton.class]) {
        button = (PCVideoPiPChromeButton*)view;
        break;
      }
    }
    if (button.hiddenOrHasHiddenAncestor || !button.enabled) {
      button = nil;
    }
  }
  [self pointAt:button];
}
- (void)pointAt:(PCVideoPiPChromeButton*)button {
  PCVideoPiPChromeButton* previous = _pointed;
  if (button) {
    if (previous) {
      [_environment setCursor:NSCursor.pointingHandCursor];
    } else {
      PCPictureInPicturePointAtControlInEnvironment(YES, _environment);
    }
  } else if (previous) {
    PCPictureInPicturePointAtControlInEnvironment(NO, _environment);
  }
  if (button == previous) {
    return;
  }
  previous.hovered = NO;
  _pointed = button;
  button.hovered = YES;
}

- (NSPanel*)panel {
  return _panel;
}
- (NSView*)videoView {
  return _videoView;
}
- (BOOL)isInvalidated {
  return _invalidated;
}
- (void)notifyChanged {
  if (_invalidated) {
    return;
  }
  __attribute__((objc_precise_lifetime)) PCVideoPiPPresenter* keep = self;
  dispatch_block_t callback = [keep->_changed copy];
  if (callback) {
    callback();
  }
}
- (void)setHovering:(BOOL)hovering {
  if (_hovering == hovering) {
    return;
  }
  _hovering = hovering;
  [self applyChromeVisibility];
}
- (void)applyChromeVisibility {
  const BOOL show = _controlsEnabled && _hovering && !_invalidated;
  [_chrome.layer removeAllAnimations];
  if (show) {
    _chrome.hidden = NO;
    _chrome.alphaValue = 1.0;
  } else {
    _chrome.hidden = YES;
    _chrome.alphaValue = 0;
  }
  [_panel invalidateCursorRectsForView:_chrome];
  [self refreshSliderVisibility];
  [self refreshPointer];
}
- (void)refreshSliderVisibility {
  const BOOL show =
      _controlsEnabled && _hovering && !_invalidated && _mediaDuration > 0;
  _position.hidden = !show;
  if (_captionsLiftedForScrubber != !_position.hiddenOrHasHiddenAncestor) {
    _captionsLiftedForScrubber = !_captionsLiftedForScrubber;
    [self layoutCaptions];
  }
}
- (double)currentMediaPosition {
  if (_mediaDuration <= 0 || !isfinite(_mediaDuration)) {
    return 0;
  }
  double position = _mediaPosition;
  if (_playbackRate != 0 && _positionSampleAt) {
    position += (-[_scheduler timeIntervalSinceNowForDate:_positionSampleAt]) * _playbackRate;
  }
  return fmax(0, fmin(position, _mediaDuration));
}
- (void)refreshSliderValue {
  if (_mediaDuration <= 0 || !isfinite(_mediaDuration)) {
    _position.maxValue = 0;
    _position.doubleValue = 0;
    [self refreshSliderVisibility];
    return;
  }
  _position.maxValue = _mediaDuration;
  _position.doubleValue = [self currentMediaPosition];
  [self refreshSliderVisibility];
}
- (void)syncProgressTimer {
  const BOOL need = !_invalidated && _playbackRate != 0 && _mediaDuration > 0 &&
                    _shown;
  if (need) {
    if (!_progressTimer) {
      __weak PCVideoPiPPresenter* weakSelf = self;
      _progressTimer = [_scheduler
          scheduledTimerWithTimeInterval:kPCVideoPiPProgressInterval
                                repeats:YES
                                  block:^(NSTimer* timer) {
                                    (void)timer;
                                    [weakSelf refreshSliderValue];
                                  }];
      [_scheduler addTimer:_progressTimer forMode:NSRunLoopCommonModes];
    }
  } else if (_progressTimer) {
    [_progressTimer invalidate];
    _progressTimer = nil;
  }
}
- (void)performAction:(NSButton*)sender {
  if (_invalidated || !_controlsEnabled || !_hovering ||
      sender.hiddenOrHasHiddenAncestor || !sender.enabled) {
    return;
  }
  __attribute__((objc_precise_lifetime)) PCVideoPiPPresenter* keep = self;
  void (^callback)(PCVideoPiPAction, double) = [keep->_action copy];
  if (callback) {
    callback((PCVideoPiPAction)sender.tag, 0);
  }
}
- (void)seek:(NSSlider*)sender {
  if (_invalidated || sender.hidden) {
    return;
  }
  _mediaPosition = sender.doubleValue;
  _positionSampleAt = _scheduler.currentDate;
  void (^callback)(PCVideoPiPAction, double) = [_action copy];
  if (callback) {
    callback(PCVideoPiPSeek, sender.doubleValue);
  }
}
- (void)showInactive {
  if (_invalidated) {
    return;
  }
  __attribute__((objc_precise_lifetime)) PCVideoPiPPresenter* keep = self;
  [_presentation orderFrontWindow:_panel];
  keep->_shown = YES;
  [keep->_panel.contentView updateTrackingAreas];
  [keep refreshSliderValue];
  [keep syncProgressTimer];
  [keep refreshHoverFromMouse];
  [keep notifyChanged];
}
- (void)hide {
  if (_invalidated) {
    return;
  }
  __attribute__((objc_precise_lifetime)) PCVideoPiPPresenter* keep = self;
  [_presentation orderOutWindow:_panel];
  keep->_shown = NO;
  [keep pointAt:nil];
  [keep syncProgressTimer];
  [keep setHovering:NO];
  [keep notifyChanged];
}
- (void)invalidate {
  if (_invalidated) {
    return;
  }
  _invalidated = YES;
  [self pointAt:nil];
  [self removeMouseMonitors];
  [_progressTimer invalidate];
  _progressTimer = nil;
  _action = nil;
  _changed = nil;
  ((PCVideoPiPContent*)_panel.contentView).changed = nil;
  ((PCVideoPiPContent*)_panel.contentView).hoverChanged = nil;
  _panel.delegate = nil;
  [_presentation orderOutWindow:_panel];
  [_presentation closeWindow:_panel];
  [_videoView removeFromSuperview];
}
- (void)setNaturalSize:(NSSize)size {
  if (_invalidated || !PCVideoPiPValidSize(size)) {
    return;
  }
  if ([_environment isWindowInLiveResize:_panel]) {
    _pendingNaturalSize = size;
    return;
  }
  [self applyNaturalSize:size];
}
- (void)applyNaturalSize:(NSSize)size {
  _pendingNaturalSize = NSZeroSize;
  if (NSEqualSizes(size, _naturalSize)) {
    return;
  }
  const BOOL first = !PCVideoPiPValidSize(_naturalSize);
  _naturalSize = size;
  _panel.contentAspectRatio = size;
  const NSRect frame =
      first ? PCVideoPiPFrameForNaturalSize(size)
            : PCVideoPiPFrameRefitted(_panel.frame, size,
                                      PCVideoPiPWorkArea(_panel.screen));
  __attribute__((objc_precise_lifetime)) PCVideoPiPPresenter* keep = self;
  NSPanel* panel = _panel;
  if (!NSEqualRects(frame, panel.frame)) {
    [panel setFrame:frame display:YES];
  }
  if (!keep->_invalidated && [keep layoutVideo]) {
    [keep layoutCaptions];
    [keep notifyChanged];
  }
}
- (BOOL)layoutVideo {
  const NSRect frame =
      PCVideoPiPVideoRect(_panel.contentView.bounds, _naturalSize);
  if (NSEqualRects(frame, _videoView.frame)) {
    return NO;
  }
  _videoView.frame = frame;
  _videoView.layer.cornerRadius =
      NSEqualRects(frame, _panel.contentView.bounds) ? kPCVideoPiPCornerRadius
                                                     : 0;
  return YES;
}
- (void)setAction:(PCVideoPiPAction)action visible:(BOOL)visible {
  NSButton* button = _buttons[@(action)];
  if (!button) {
    return;
  }
  if (!visible && (action == PCVideoPiPMute || action == PCVideoPiPPlayPause ||
                   action == PCVideoPiPReturn || action == PCVideoPiPClose ||
                   action == PCVideoPiPMinimize)) {
    button.hidden = YES;
  } else if (visible) {
    button.hidden = NO;
  }
  [self refreshPointer];
}
- (void)setAction:(PCVideoPiPAction)action title:(NSString*)title {
  NSButton* button = _buttons[@(action)];
  if (!button) {
    return;
  }
  button.accessibilityLabel = title;
  if (action == PCVideoPiPPlayPause) {
    const BOOL playing = [title isEqualToString:@"Pause"];
    button.image =
        PCVideoPiPSymbol(playing ? @"pause.fill" : @"play.fill", 22);
    button.accessibilityLabel = title;
    if (playing != _playing) {
      _mediaPosition = [self currentMediaPosition];
      _positionSampleAt = _scheduler.currentDate;
      _playing = playing;
      if (_playbackRate == 0 || _playbackRate == 1) {
        _playbackRate = playing ? 1.0 : 0.0;
      } else if (!playing) {
        _playbackRate = 0.0;
      }
      [self syncProgressTimer];
      [self refreshSliderValue];
    }
  } else if (action == PCVideoPiPMute) {
    const BOOL muted = [title.lowercaseString containsString:@"unmute"];
    button.image = PCVideoPiPSymbol(
        muted ? @"speaker.slash.fill" : @"speaker.wave.2.fill", 12);
  }
}
- (void)setControlsVisible:(BOOL)visible {
  _controlsEnabled = visible;
  [self applyChromeVisibility];
}
- (void)setSourceTitle:(NSString*)title {
  _title.stringValue = title ?: @"";
  _panel.title = title ?: @"";
}
- (void)setFavicon:(NSImage*)image {
  _favicon.image = image;
}
- (void)setCaptions:(NSImage*)image bounds:(NSRect)bounds {
  const BOOL finite = isfinite(NSMinX(bounds)) && isfinite(NSMinY(bounds)) &&
                      isfinite(NSWidth(bounds)) && isfinite(NSHeight(bounds));
  _captionBounds =
      finite ? NSIntersectionRect(bounds, NSMakeRect(0, 0, 1, 1)) : NSZeroRect;
  const BOOL valid = image && !NSIsEmptyRect(_captionBounds);
  _captions.image = valid ? image : nil;
  _captions.hidden = !valid;
  [self layoutCaptions];
}
- (void)layoutCaptions {
  if (_captions.hidden) {
    return;
  }
  const NSRect content = _panel.contentView.bounds;
  const NSRect video = _videoView.frame;
  NSRect frame = NSMakeRect(
      NSMinX(video) + NSWidth(video) * NSMinX(_captionBounds),
      NSMinY(video) + NSHeight(video) * (1 - NSMaxY(_captionBounds)),
      NSWidth(video) * NSWidth(_captionBounds),
      NSHeight(video) * NSHeight(_captionBounds));
  if (!_position.hiddenOrHasHiddenAncestor) {
    [_chrome layoutSubtreeIfNeeded];
    const CGFloat floor = NSMaxY(_position.frame) + 6;
    frame.origin.y = fmin(fmax(NSMinY(frame), floor),
                          fmax(0, NSHeight(content) - NSHeight(frame)));
  }
  _captions.frame = frame;
}
- (void)setPosition:(double)position duration:(double)duration {
  [self setPosition:position
           duration:duration
      playbackRate:_playing ? (_playbackRate != 0 ? _playbackRate : 1.0) : 0.0];
}
- (void)setPosition:(double)position
           duration:(double)duration
      playbackRate:(double)playbackRate {
  const BOOL valid = isfinite(duration) && duration > 0 && isfinite(position);
  _mediaDuration = valid ? duration : 0;
  _mediaPosition = valid ? fmax(0, fmin(position, duration)) : 0;
  _playbackRate = valid ? playbackRate : 0;
  _positionSampleAt = _scheduler.currentDate;
  if (_playbackRate != 0) {
    _playing = YES;
  } else if (valid) {
    _playing = NO;
  }
  [self refreshSliderValue];
  [self syncProgressTimer];
}
- (void)windowDidResize:(NSNotification*)note {
  (void)note;
  [self layoutCaptions];
  [self notifyChanged];
}
- (void)windowDidEndLiveResize:(NSNotification*)note {
  (void)note;
  if (!_invalidated && PCVideoPiPValidSize(_pendingNaturalSize)) {
    [self applyNaturalSize:_pendingNaturalSize];
  }
}
- (void)windowDidMove:(NSNotification*)note {
  (void)note;
  [self notifyChanged];
}
- (void)windowDidChangeScreen:(NSNotification*)note {
  (void)note;
  [self notifyChanged];
}
- (void)windowDidChangeBackingProperties:(NSNotification*)note {
  (void)note;
  [self notifyChanged];
}
- (void)windowWillClose:(NSNotification*)note {
  (void)note;
  if (_invalidated) {
    return;
  }
  __attribute__((objc_precise_lifetime)) PCVideoPiPPresenter* keep = self;
  void (^callback)(PCVideoPiPAction, double) = [keep->_action copy];
  [keep invalidate];
  if (callback) {
    callback(PCVideoPiPSystemClose, 0);
  }
}
- (void)dealloc {
  [self invalidate];
}
@end
