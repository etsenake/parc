// Copyright 2026 Parc contributors.
#import "VideoPiPWindow.h"

#import <QuartzCore/QuartzCore.h>
#include <dlfcn.h>
#include <math.h>

//
//
// 1024×563 @2x). Chromium places bottom-right with a 2% buffer. Corner radius
//
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

// A later natural size keeps the width and pins the corner nearest the
// screen's, as Chromium's VideoOverlayWindowViews::
// CalculateAndUpdateWindowBounds does by window quadrant.
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

// The video surface stretches to fill its view, so the view keeps the
// video's aspect inside the window, filling it when they differ by under a
// point (Chromium's UpdateLayerBoundsWithLetterboxing).
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

// The window server ignores a background app's cursor unless its connection
// "SetsCursorInBackground", and a PiP floats over another app most of the
// time. That is switched on only while the pointer is on a control, so Parc's
// other windows behind the frontmost app keep leaving the cursor alone. The
// arrow goes back before it is switched off: AppKit skips setting the cursor
// it believes is current, even if the window server ignored it.
typedef int PCCGSConnection;
static void PCSetsCursorInBackground(BOOL on) {
  static PCCGSConnection (*connection)(void);
  static int (*set)(PCCGSConnection, PCCGSConnection, CFStringRef, CFTypeRef);
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    connection = (PCCGSConnection(*)(void))dlsym(RTLD_DEFAULT,
                                                 "CGSMainConnectionID");
    set = (int (*)(PCCGSConnection, PCCGSConnection, CFStringRef,
                   CFTypeRef))dlsym(RTLD_DEFAULT, "CGSSetConnectionProperty");
  });
  if (connection && set) {
    set(connection(), connection(), CFSTR("SetsCursorInBackground"),
        on ? kCFBooleanTrue : kCFBooleanFalse);
  }
}
// Counted: the video window and the Meet bar can each have a control under
// the pointer while one's exit and the other's entry cross.
void PCPictureInPicturePointAtControl(BOOL control) {
  static NSInteger pointing;
  if (control) {
    if (pointing++ == 0) {
      PCSetsCursorInBackground(YES);
    }
    [NSCursor.pointingHandCursor set];
  } else if (pointing > 0 && --pointing == 0) {
    [NSCursor.arrowCursor set];
    PCSetsCursorInBackground(NO);
  }
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
  // Arc142 MovableWindow → PIPWindowContent canBecomeKey witness returns false.
  return NO;
}
@end

//
// chip is an NSGlassEffectView disc with a borderless symbol button inside.
// Under the pointer a chip grows to 110% and its symbol goes from 92.5% to
//
//
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
    // WWDC25: custom floating chrome uses NSGlassEffectView (not
    // NSBezelStyleGlass — that bezel is a standard push shape). Circular
    // chips = glass.cornerRadius == half the side. Interactive on 27+.
    NSGlassEffectView* glass = [[NSGlassEffectView alloc] initWithFrame:frame];
    glass.translatesAutoresizingMaskIntoConstraints = NO;
    //
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
// The glass lays its content out by alignment rect, which follows the
// symbol's shape: a minus made a shorter button and a squarer disc.
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
  // The button tracks the press inside super until the mouse goes up; its
  // action can release the presenter that owns it.
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
  // AppKit anchors a view's layer at its origin; scale about the centre.
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

// Cues sit between the video and the chrome and never take the pointer, so
// clicks still drag the window.
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
@end
@implementation PCVideoPiPContent {
  NSTrackingArea* _tracking;
}
@synthesize changed = _changed;
@synthesize hoverChanged = _hoverChanged;
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
  // Chrome sits above this view. Leaving the video layer for a control must
  // not clear hover — the presenter's screen hit-test owns leave-panel.
  NSWindow* window = self.window;
  if (window && window.visible &&
      NSPointInRect(NSEvent.mouseLocation, window.frame)) {
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
  // Buttons handle their own mouseDown; video clicks climb here for drag.
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
      //
      ((NSGlassEffectView*)host).cornerRadius = size * 0.5;
    }
  }
  return button;
}

- (instancetype)initWithVideoView:(NSView*)videoView
                      sourceFrame:(NSRect)sourceFrame
                           action:(void (^)(PCVideoPiPAction, double))action
                          changed:(dispatch_block_t)changed {
  if (!(self = [super init])) {
    return nil;
  }
  (void)sourceFrame;
  _videoView = videoView;
  _action = [action copy];
  _changed = [changed copy];
  _controlsEnabled = YES;
  _buttons = [NSMutableDictionary new];
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
  //
  // Engine extras (skip/track/camera/…) stay out of the view — unconstrained
  // hidden ellipsis buttons were still landing at the bottom-left origin.

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
      [NSEvent addLocalMonitorForEventsMatchingMask:mask
                                            handler:^NSEvent*(NSEvent* event) {
                                              [weakSelf refreshHoverFromMouse];
                                              return event;
                                            }];
  // Nonactivating PiP must track hover while another app is frontmost.
  _globalMonitor = [NSEvent
      addGlobalMonitorForEventsMatchingMask:NSEventMaskMouseMoved |
                                            NSEventMaskLeftMouseDragged
                                    handler:^(NSEvent* event) {
                                      (void)event;
                                      [weakSelf refreshHoverFromMouse];
                                    }];
}

- (void)removeMouseMonitors {
  if (_localMonitor) {
    [NSEvent removeMonitor:_localMonitor];
    _localMonitor = nil;
  }
  if (_globalMonitor) {
    [NSEvent removeMonitor:_globalMonitor];
    _globalMonitor = nil;
  }
}

- (void)refreshHoverFromMouse {
  if (_invalidated) {
    [self setHovering:NO];
    return;
  }
  // Tracking-area enter/exit owns hover while the panel is not on-screen
  // (tests and pre-show). Screen hit-testing only after orderFront.
  if (!_panel.isVisible) {
    return;
  }
  NSPoint screenPoint = [NSEvent mouseLocation];
  const BOOL inside = NSPointInRect(screenPoint, _panel.frame);
  [self setHovering:inside];
  [self refreshPointer];
}

// The panel never becomes key, and macOS applies a window's cursor rects
// only in the key window, so the button under the pointer is found on every
// mouse event the monitors see, the global one while another app is
// frontmost, and the cursor set here: a hand over a button, the arrow again
// on leaving one. Chrome shown under a still pointer counts at once.
- (void)refreshPointer {
  PCVideoPiPChromeButton* button = nil;
  if (!_invalidated && _panel.visible && !_chrome.hidden) {
    NSView* content = _panel.contentView;
    const NSPoint point =
        [content.superview convertPoint:[_panel convertPointFromScreen:
                                                    NSEvent.mouseLocation]
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
    // Every move: the glass or a cursor rect may have changed it meanwhile.
    if (previous) {
      [NSCursor.pointingHandCursor set];
    } else {
      PCPictureInPicturePointAtControl(YES);
    }
  } else if (previous) {
    PCPictureInPicturePointAtControl(NO);
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
  // Drop in-flight fade completions — a stale hide completion was re-hiding
  // chrome right after hover showed it (flash once, then gone).
  [_chrome.layer removeAllAnimations];
  if (show) {
    _chrome.hidden = NO;
    _chrome.alphaValue = 1.0;
  } else {
    // Disable hits immediately; do not wait for a fade to finish.
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
    position += (-[_positionSampleAt timeIntervalSinceNow]) * _playbackRate;
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
  // The panel outlives a PiP session hidden; refreshing its slider 30 times a
  // second while it is ordered out cost the main thread for the whole video.
  const BOOL need = !_invalidated && _playbackRate != 0 && _mediaDuration > 0 &&
                    _shown;
  if (need) {
    if (!_progressTimer) {
      __weak PCVideoPiPPresenter* weakSelf = self;
      _progressTimer = [NSTimer
          scheduledTimerWithTimeInterval:kPCVideoPiPProgressInterval
                                repeats:YES
                                  block:^(NSTimer* timer) {
                                    (void)timer;
                                    [weakSelf refreshSliderValue];
                                  }];
      [[NSRunLoop mainRunLoop] addTimer:_progressTimer
                                forMode:NSRunLoopCommonModes];
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
  _positionSampleAt = [NSDate date];
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
  [_panel orderFront:nil];
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
  [_panel orderOut:nil];
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
  [_panel orderOut:nil];
  [_panel close];
  [_videoView removeFromSuperview];
}
- (void)setNaturalSize:(NSSize)size {
  if (_invalidated || !PCVideoPiPValidSize(size)) {
    return;
  }
  // A playing video's size changes (a page switching renditions as the
  // window grows) wait while the user resizes: a refit there fought the
  //
  //
  if (_panel.inLiveResize) {
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
  // Every change refits the window, as Chromium's UpdateNaturalSize does: a
  // reused window or a new rendition can bring another aspect.
  const NSRect frame =
      first ? PCVideoPiPFrameForNaturalSize(size)
            : PCVideoPiPFrameRefitted(_panel.frame, size,
                                      PCVideoPiPWorkArea(_panel.screen));
  // A resize lays out and notifies; observers can then release the owner.
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
  // Rounded only where its corners are the window's; bars keep it square.
  _videoView.layer.cornerRadius =
      NSEqualRects(frame, _panel.contentView.bounds) ? kPCVideoPiPCornerRadius
                                                     : 0;
  return YES;
}
- (void)setAction:(PCVideoPiPAction)action visible:(BOOL)visible {
  NSButton* button = _buttons[@(action)];
  if (!button) {
    // Unknown / unsupported chrome actions are intentionally absent.
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
      _positionSampleAt = [NSDate date];
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
  // The page supplies the bounds, so they stay within the video picture.
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
  // Bounds come from the page relative to the video, origin at the top left.
  const NSRect content = _panel.contentView.bounds;
  const NSRect video = _videoView.frame;
  NSRect frame = NSMakeRect(
      NSMinX(video) + NSWidth(video) * NSMinX(_captionBounds),
      NSMinY(video) + NSHeight(video) * (1 - NSMaxY(_captionBounds)),
      NSWidth(video) * NSWidth(_captionBounds),
      NSHeight(video) * NSHeight(_captionBounds));
  // A shown scrubber would cover bottom cues; they rise above it meanwhile.
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
  _positionSampleAt = [NSDate date];
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
