#import "extension_install_presenter.h"

#include <algorithm>
#include <cmath>

@interface PCExtensionInstallPresenter () <NSTextViewDelegate, NSTextFieldDelegate> {
  NSWindow* __weak _window;
  NSString* _title;
  NSImage* _icon;
  NSString* _heading;
  NSArray<NSString*>* _permissions;
  NSArray<NSString*>* _details;
  NSString* _acceptLabel;
  NSString* _cancelLabel;
  NSString* _checkboxLabel;
  NSString* _justificationLabel;
  NSString* _justificationPlaceholder;
  NSString* (^_justificationCounterText)(NSUInteger);
  NSTextView* _justificationInput;
  NSTextField* _justificationCounter;
  NSArray<NSString*>* _parentAccounts;
  NSArray<NSString*>* _parentInstructions;
  NSString* _parentPasswordLabel;
  void (^_parentSubmit)(NSInteger, NSString*);
  NSPopUpButton* _parentChoice;
  NSSecureTextField* _parentPassword;
  NSTextField* _parentError;
  NSProgressIndicator* _parentProgress;
  BOOL _parentPending;
  BOOL _installationEducation;
  NSArray<PCExtensionInstallItem*>* _items;
  BOOL (^_validate)(void);
  BOOL (^_inputAllowed)(NSWindow*);
  void (^_result)(PCExtensionInstallChoice, BOOL);
  NSWindow* _sheet;
  NSStackView* _stack;
  NSButton* _accept;
  NSButton* _checkbox;
  NSTimer* _timer;
  id _closeObserver;
  NSTimeInterval _allowAfter;
  BOOL _wasObstructed;
  BOOL _started;
  BOOL _finished;
  BOOL _invalidated;
}
- (void)accept:(id)sender;
- (void)cancel:(id)sender;
- (void)finish:(PCExtensionInstallChoice)choice;
@end
@interface PCExtensionJustificationTextView : NSTextView
@property(nonatomic, copy) NSString* placeholder;
@end
@implementation PCExtensionJustificationTextView
@synthesize placeholder = _placeholder;
- (void)drawRect:(NSRect)dirtyRect {
  [super drawRect:dirtyRect];
  if (!self.string.length && self.placeholder.length) {
    NSRect rect = NSInsetRect(self.bounds, self.textContainerInset.width + 5,
                             self.textContainerInset.height);
    [self.placeholder drawInRect:rect
                 withAttributes:@{
                   NSFontAttributeName : self.font ?: [NSFont systemFontOfSize:13],
                   NSForegroundColorAttributeName : NSColor.placeholderTextColor
                 }];
  }
}
@end
@interface PCExtensionInstallSheet : NSWindow
@property(nonatomic, weak) PCExtensionInstallPresenter* request;
@end
@implementation PCExtensionInstallSheet
@synthesize request = _request;
- (void)cancelOperation:(id)sender {
  [self.request finish:PCExtensionInstallCancel];
}
@end
static void Later(void (^block)(void)) {
  [NSRunLoop.mainRunLoop
      performInModes:@[ NSRunLoopCommonModes, NSModalPanelRunLoopMode ]
               block:block];
}
namespace {
//
NSColor* DialogColor(uint32_t light, CGFloat lightAlpha, uint32_t dark,
                     CGFloat darkAlpha) {
  return [NSColor colorWithName:nil
                dynamicProvider:^NSColor*(NSAppearance* appearance) {
                  const BOOL isDark = [[appearance bestMatchFromAppearancesWithNames:@[
                    NSAppearanceNameAqua, NSAppearanceNameDarkAqua
                  ]] isEqualToString:NSAppearanceNameDarkAqua];
                  const uint32_t rgb = isDark ? dark : light;
                  return [NSColor colorWithSRGBRed:((rgb >> 16) & 0xff) / 255.0
                                             green:((rgb >> 8) & 0xff) / 255.0
                                              blue:(rgb & 0xff) / 255.0
                                             alpha:isDark ? darkAlpha : lightAlpha];
                }];
}
#define PC_DIALOG_COLOR(name, light, lightAlpha, dark, darkAlpha)            \
  NSColor* name() {                                                          \
    static NSColor* color = DialogColor(light, lightAlpha, dark, darkAlpha); \
    return color;                                                            \
  }
PC_DIALOG_COLOR(PopoverBackground, 0xFAFBFF, 1, 0x151C30, 1)
PC_DIALOG_COLOR(PopoverTitle, 0x181B1F, 1, 0xFFFFFF, 1)
PC_DIALOG_COLOR(PopoverMessage, 0x060E2B, .75, 0xEEEEF6, .75)
PC_DIALOG_COLOR(PopoverLogoBackground, 0xFFFFFF, .9, 0xFFFFFF, .6)
PC_DIALOG_COLOR(PopoverLogoShadow, 0x000000, .15, 0xFFFFFF, 0)
PC_DIALOG_COLOR(PopoverArrowIcon, 0x1E2E69, .3, 0xEEEEF6, .3)
PC_DIALOG_COLOR(NeutralButtonFace, 0xFFFFFF, 1, 0x302F63, 1)
PC_DIALOG_COLOR(NeutralButtonHovered, 0xF2F2F2, 1, 0x454473, 1)
PC_DIALOG_COLOR(NeutralButtonPressed, 0xE5E5E5, 1, 0x2B2A59, 1)
PC_DIALOG_COLOR(NeutralButtonForeground, 0x171717, 1, 0xFFFFFF, .9)
PC_DIALOG_COLOR(NeutralButtonBorder, 0xDBDBDB, 1, 0x6362AE, 1)
PC_DIALOG_COLOR(NeutralButtonShadow, 0xE2E2E2, 1, 0xFFFFFF, 0)
PC_DIALOG_COLOR(NeutralButtonIconForeground, 0x727272, 1, 0xD7D7FF, .77)
PC_DIALOG_COLOR(NeutralButtonIconBackground, 0x000000, .1, 0xC7C0D7, .2)
PC_DIALOG_COLOR(PrimaryButtonFace, 0x3139FB, 1, 0x3139FB, 1)
PC_DIALOG_COLOR(PrimaryButtonHovered, 0x2C33E2, 1, 0x2C33E2, 1)
PC_DIALOG_COLOR(PrimaryButtonPressed, 0x2A30D5, 1, 0x2A30D5, 1)
PC_DIALOG_COLOR(PrimaryButtonForeground, 0xFFFFFF, 1, 0xFFFFFF, 1)
PC_DIALOG_COLOR(PrimaryButtonBorder, 0xFFFFFF, 0, 0xFFFFFF, .2)
PC_DIALOG_COLOR(PrimaryButtonShadow, 0x3438B2, 1, 0x5A61FC, .5)
PC_DIALOG_COLOR(PrimaryButtonIconForeground, 0xFFFFFF, .9, 0xFFFFFF, .9)
PC_DIALOG_COLOR(PrimaryButtonIconBackground, 0xFFFFFF, .1, 0xFFFFFF, .1)
PC_DIALOG_COLOR(PrimaryButtonIconBorder, 0xFFFFFF, .2, 0xFFFFFF, .2)
PC_DIALOG_COLOR(Indigo4, 0xE8E9FF, 1, 0x1C1D4F, 1)
PC_DIALOG_COLOR(Indigo6, 0xC8CAFA, 1, 0x22246E, 1)
#undef PC_DIALOG_COLOR

// SwiftUI's continuous corner (RoundedCornerStyle.continuous) as a path.
NSBezierPath* ContinuousRect(NSRect rect, CGFloat radius) {
  const CGFloat r = std::min(radius, std::min(NSWidth(rect), NSHeight(rect)) / 2 / 1.52866483);
  const CGFloat x = NSMinX(rect), y = NSMinY(rect), X = NSMaxX(rect), Y = NSMaxY(rect);
  NSBezierPath* path = [NSBezierPath bezierPath];
  auto p = [](CGFloat px, CGFloat py) { return NSMakePoint(px, py); };
  [path moveToPoint:p(x + 1.52866483 * r, y)];
  [path lineToPoint:p(X - 1.52866483 * r, y)];
  [path curveToPoint:p(X - .63149399 * r, y + .07491100 * r)
       controlPoint1:p(X - 1.08849323 * r, y) controlPoint2:p(X - .86840689 * r, y)];
  [path curveToPoint:p(X - .07491100 * r, y + .63149399 * r)
       controlPoint1:p(X - .37282392 * r, y + .16905899 * r)
       controlPoint2:p(X - .16905899 * r, y + .37282392 * r)];
  [path curveToPoint:p(X, y + 1.52866483 * r)
       controlPoint1:p(X, y + .86840689 * r) controlPoint2:p(X, y + 1.08849323 * r)];
  [path lineToPoint:p(X, Y - 1.52866483 * r)];
  [path curveToPoint:p(X - .07491100 * r, Y - .63149399 * r)
       controlPoint1:p(X, Y - 1.08849323 * r) controlPoint2:p(X, Y - .86840689 * r)];
  [path curveToPoint:p(X - .63149399 * r, Y - .07491100 * r)
       controlPoint1:p(X - .16905899 * r, Y - .37282392 * r)
       controlPoint2:p(X - .37282392 * r, Y - .16905899 * r)];
  [path curveToPoint:p(X - 1.52866483 * r, Y)
       controlPoint1:p(X - .86840689 * r, Y) controlPoint2:p(X - 1.08849323 * r, Y)];
  [path lineToPoint:p(x + 1.52866483 * r, Y)];
  [path curveToPoint:p(x + .63149399 * r, Y - .07491100 * r)
       controlPoint1:p(x + 1.08849323 * r, Y) controlPoint2:p(x + .86840689 * r, Y)];
  [path curveToPoint:p(x + .07491100 * r, Y - .63149399 * r)
       controlPoint1:p(x + .37282392 * r, Y - .16905899 * r)
       controlPoint2:p(x + .16905899 * r, Y - .37282392 * r)];
  [path curveToPoint:p(x, Y - 1.52866483 * r)
       controlPoint1:p(x, Y - .86840689 * r) controlPoint2:p(x, Y - 1.08849323 * r)];
  [path lineToPoint:p(x, y + 1.52866483 * r)];
  [path curveToPoint:p(x + .07491100 * r, y + .63149399 * r)
       controlPoint1:p(x, y + 1.08849323 * r) controlPoint2:p(x, y + .86840689 * r)];
  [path curveToPoint:p(x + .63149399 * r, y + .07491100 * r)
       controlPoint1:p(x + .16905899 * r, y + .37282392 * r)
       controlPoint2:p(x + .37282392 * r, y + .16905899 * r)];
  [path curveToPoint:p(x + 1.52866483 * r, y)
       controlPoint1:p(x + .86840689 * r, y) controlPoint2:p(x + 1.08849323 * r, y)];
  [path closePath];
  return path;
}

NSTextField* DialogLabel(NSString* text, NSFont* font, NSColor* color, CGFloat lineSpacing) {
  NSMutableParagraphStyle* paragraph = [[NSMutableParagraphStyle alloc] init];
  paragraph.lineSpacing = lineSpacing;
  NSTextField* label = [NSTextField wrappingLabelWithString:@""];
  label.font = font;
  label.textColor = color;
  label.attributedStringValue = [[NSAttributedString alloc]
      initWithString:text
          attributes:@{
            NSFontAttributeName : font,
            NSForegroundColorAttributeName : color,
            NSParagraphStyleAttributeName : paragraph
          }];
  label.selectable = NO;
  return label;
}
// Places the label's text, not its inset cell, at (x, y, width) like SwiftUI Text.
CGFloat PlaceLabel(NSTextField* label, CGFloat x, CGFloat y, CGFloat width) {
  const CGFloat inset = 2;
  label.preferredMaxLayoutWidth = width + 2 * inset;
  const CGFloat height = ceil(
      [label.cell cellSizeForBounds:NSMakeRect(0, 0, width + 2 * inset, CGFLOAT_MAX)].height);
  label.frame = NSMakeRect(x - inset, y, width + 2 * inset, height);
  return height;
}
NSFont* DialogButtonFont() {
  return [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
}
NSFont* DialogHintFont() {
  NSFont* bold = [NSFont systemFontOfSize:11 weight:NSFontWeightBold];
  NSFontDescriptor* rounded =
      [bold.fontDescriptor fontDescriptorWithDesign:NSFontDescriptorSystemDesignRounded];
  return [NSFont fontWithDescriptor:rounded size:11] ?: bold;
}
}  // namespace
@interface PCDialogFlippedView : NSView
@end
@implementation PCDialogFlippedView
- (BOOL)isFlipped {
  return YES;
}
@end
// Dialogs.DialogViewBase fills PopoverBackground itself: an attached sheet's
// frame view puts the system sheet material over the window background color.
@interface PCDialogBaseView : PCDialogFlippedView
@end
@implementation PCDialogBaseView
- (BOOL)isOpaque {
  return YES;
}
- (void)drawRect:(NSRect)dirtyRect {
  [PopoverBackground() setFill];
  NSRectFill(dirtyRect);
}
@end
//
@interface PCDialogPictureIcon : NSView
@end
@implementation PCDialogPictureIcon {
  NSImage* _image;
  NSRect _imageRect;
}
- (instancetype)initWithImage:(NSImage*)image imageRect:(NSRect)imageRect {
  if ((self = [super initWithFrame:NSMakeRect(0, 0, 62, 62)])) {
    _image = image;
    _imageRect = imageRect;
  }
  return self;
}
- (BOOL)isFlipped {
  return YES;
}
- (void)drawRect:(NSRect)dirtyRect {
  NSGraphicsContext.currentContext.imageInterpolation = NSImageInterpolationHigh;
  [NSGraphicsContext saveGraphicsState];
  NSShadow* shadow = [[NSShadow alloc] init];
  shadow.shadowColor = PopoverLogoShadow();
  shadow.shadowBlurRadius = 3;
  shadow.shadowOffset = NSMakeSize(0, -1);
  [shadow set];
  [PopoverLogoBackground() setFill];
  [ContinuousRect(self.bounds, 13) fill];
  [NSGraphicsContext restoreGraphicsState];
  [_image drawInRect:_imageRect fromRect:NSZeroRect operation:NSCompositingOperationSourceOver
            fraction:1 respectFlipped:YES hints:nil];
}
- (void)viewDidChangeEffectiveAppearance {
  self.needsDisplay = YES;
}
@end
// Dialogs.DialogButtonStyleView with its DialogButtonLabel/ButtonHotkeyHint.
@interface PCDialogButton : NSButton
- (instancetype)initWithTitle:(NSString*)title primary:(BOOL)primary;
@property(nonatomic, readonly) CGFloat bodyWidth;
// The key event whose key equivalent is dispatching the action, if any.
@property(nonatomic, readonly) NSEvent* keyEvent;
@end
@implementation PCDialogButton {
  BOOL _primary;
  BOOL _hovered;
  NSTrackingArea* _tracking;
  NSString* _hintText;
  NSImage* _hintSymbol;
}
@synthesize keyEvent = _keyEvent;
- (instancetype)initWithTitle:(NSString*)title primary:(BOOL)primary {
  if ((self = [super initWithFrame:NSZeroRect])) {
    _primary = primary;
    self.title = title;
    self.bordered = NO;
    self.buttonType = NSButtonTypeMomentaryPushIn;
    self.font = DialogButtonFont();
    if (primary) {
      _hintSymbol = [NSImage imageWithSystemSymbolName:@"return" accessibilityDescription:nil];
    } else {
      _hintText = @"ESC";
    }
  }
  return self;
}
- (BOOL)isFlipped {
  return YES;
}
- (BOOL)performKeyEquivalent:(NSEvent*)event {
  _keyEvent = event;
  const BOOL handled = [super performKeyEquivalent:event];
  _keyEvent = nil;
  return handled;
}
- (NSImage*)hintSymbolWithColor:(NSColor*)color {
  NSImageSymbolConfiguration* configuration =
      [NSImageSymbolConfiguration configurationWithPointSize:11 weight:NSFontWeightBold];
  if (color) {
    configuration = [configuration configurationByApplyingConfiguration:
        [NSImageSymbolConfiguration configurationWithPaletteColors:@[ color ]]];
  }
  return [_hintSymbol imageWithSymbolConfiguration:configuration];
}
- (NSSize)hintContentSize {
  if (_hintSymbol) return [self hintSymbolWithColor:nil].size;
  return [_hintText sizeWithAttributes:@{NSFontAttributeName : DialogHintFont()}];
}
- (NSSize)hintSize {
  const NSSize content = [self hintContentSize];
  return NSMakeSize(content.width + 12, content.height + 6);
}
- (CGFloat)labelWidth {
  return [self.title sizeWithAttributes:@{NSFontAttributeName : DialogButtonFont()}].width;
}
- (CGFloat)bodyWidth {
  return 12 + [self labelWidth] + 8 + [self hintSize].width + 12;
}
// The view extends past the 36-point body for the centered border and the
// two-point shadow below it.
- (NSRect)body {
  return NSMakeRect(.5, .5, NSWidth(self.bounds) - 1, 36);
}
- (void)updateTrackingAreas {
  [super updateTrackingAreas];
  if (_tracking) [self removeTrackingArea:_tracking];
  _tracking = [[NSTrackingArea alloc]
      initWithRect:NSZeroRect
           options:NSTrackingMouseEnteredAndExited | NSTrackingActiveInKeyWindow |
                   NSTrackingInVisibleRect
             owner:self
          userInfo:nil];
  [self addTrackingArea:_tracking];
}
- (void)mouseEntered:(NSEvent*)event {
  _hovered = YES;
  self.needsDisplay = YES;
}
- (void)mouseExited:(NSEvent*)event {
  _hovered = NO;
  self.needsDisplay = YES;
}
- (void)viewDidMoveToWindow {
  [super viewDidMoveToWindow];
  _hovered = NO;
}
- (void)viewDidChangeEffectiveAppearance {
  self.needsDisplay = YES;
}
- (NSRect)focusRingMaskBounds {
  return [self body];
}
- (void)drawFocusRingMask {
  [ContinuousRect([self body], 6) fill];
}
- (void)drawRect:(NSRect)dirtyRect {
  const NSRect body = [self body];
  const BOOL pressed = self.cell.isHighlighted;
  NSColor *face, *foreground, *border, *shadow, *hintForeground, *hintBackground, *hintBorder;
  if (!_primary) {
    face = pressed    ? NeutralButtonPressed()
           : _hovered ? NeutralButtonHovered()
                      : NeutralButtonFace();
    foreground = NeutralButtonForeground();
    border = NeutralButtonBorder();
    shadow = NeutralButtonShadow();
    hintForeground = NeutralButtonIconForeground();
    hintBackground = NeutralButtonIconBackground();
  } else if (self.enabled) {
    face = pressed    ? PrimaryButtonPressed()
           : _hovered ? PrimaryButtonHovered()
                      : PrimaryButtonFace();
    foreground = PrimaryButtonForeground();
    border = PrimaryButtonBorder();
    shadow = PrimaryButtonShadow();
    hintForeground = PrimaryButtonIconForeground();
    hintBackground = PrimaryButtonIconBackground();
    hintBorder = PrimaryButtonIconBorder();
  } else {
    face = Indigo4();
    foreground = PopoverArrowIcon();
    shadow = Indigo6();
    hintForeground = PopoverArrowIcon();
    hintBackground = Indigo6();
  }
  [shadow setFill];
  [ContinuousRect(NSOffsetRect(body, 0, 2), 6) fill];
  NSBezierPath* shape = ContinuousRect(body, 6);
  [face setFill];
  [shape fill];
  if (border) {
    [border setStroke];
    shape.lineWidth = 1;
    [shape stroke];
  }
  NSDictionary* attributes = @{
    NSFontAttributeName : DialogButtonFont(),
    NSForegroundColorAttributeName : foreground
  };
  const NSSize label = [self.title sizeWithAttributes:attributes];
  [self.title drawAtPoint:NSMakePoint(NSMinX(body) + 12, NSMidY(body) - label.height / 2)
           withAttributes:attributes];
  const NSSize hint = [self hintSize];
  const NSRect badge = NSMakeRect(NSMaxX(body) - 12 - hint.width,
                                  NSMidY(body) - hint.height / 2, hint.width, hint.height);
  NSBezierPath* badgeShape = ContinuousRect(badge, 4);
  [hintBackground setFill];
  [badgeShape fill];
  if (hintBorder) {
    [hintBorder setStroke];
    badgeShape.lineWidth = 2;
    [badgeShape stroke];
  }
  const NSSize content = [self hintContentSize];
  const NSRect contentRect = NSMakeRect(NSMidX(badge) - content.width / 2,
                                        NSMidY(badge) - content.height / 2,
                                        content.width, content.height);
  if (_hintSymbol) {
    [[self hintSymbolWithColor:hintForeground] drawInRect:contentRect fromRect:NSZeroRect
             operation:NSCompositingOperationSourceOver fraction:1 respectFlipped:YES hints:nil];
  } else {
    [_hintText drawAtPoint:contentRect.origin
            withAttributes:@{
              NSFontAttributeName : DialogHintFont(),
              NSForegroundColorAttributeName : hintForeground
            }];
  }
}
@end
// Dialogs.ExplainerScroll: a 26-point background fade until scrolled to the end.
@interface PCDialogFade : NSView
@end
@implementation PCDialogFade
- (BOOL)isFlipped {
  return YES;
}
- (NSView*)hitTest:(NSPoint)point {
  return nil;
}
- (void)drawRect:(NSRect)dirtyRect {
  NSColor* background = PopoverBackground();
  [[[NSGradient alloc] initWithStartingColor:[background colorWithAlphaComponent:.01]
                                 endingColor:background] drawInRect:self.bounds angle:90];
}
- (void)viewDidChangeEffectiveAppearance {
  self.needsDisplay = YES;
}
@end
@protocol PCDialogDocument
- (CGFloat)layOutForWidth:(CGFloat)width;
@end
// The heading and Dialogs.ExplainerTextWithBullet rows in a leading LazyVStack.
@interface PCDialogExplainerDocument : PCDialogFlippedView <PCDialogDocument>
- (instancetype)initWithHeading:(NSString*)heading
                    permissions:(NSArray<NSString*>*)permissions
                        details:(NSArray<NSString*>*)details;
- (CGFloat)layOutForWidth:(CGFloat)width;
@end
@implementation PCDialogExplainerDocument {
  NSTextField* _heading;
  NSArray<NSTextField*>* _bullets;
  NSArray<NSTextField*>* _messages;
  NSArray<NSTextField*>* _details;
  CGFloat _bulletWidth;
}
- (instancetype)initWithHeading:(NSString*)heading
                    permissions:(NSArray<NSString*>*)permissions
                        details:(NSArray<NSString*>*)details {
  if ((self = [super initWithFrame:NSZeroRect])) {
    NSFont* font = [NSFont systemFontOfSize:14];
    _bulletWidth = [@"•" sizeWithAttributes:@{NSFontAttributeName : font}].width;
    _heading = DialogLabel(heading, font, PopoverMessage(), 1);
    [self addSubview:_heading];
    NSMutableArray* bullets = [NSMutableArray array];
    NSMutableArray* messages = [NSMutableArray array];
    NSMutableArray* extra = [NSMutableArray array];
    for (NSUInteger i = 0; i < permissions.count; ++i) {
      NSTextField* bullet = DialogLabel(@"•", font, PopoverMessage(), 1);
      [bullet setAccessibilityElement:NO];
      NSTextField* message = DialogLabel(permissions[i], font, PopoverMessage(), 1);
      NSTextField* detail = DialogLabel(details[i], font, PopoverMessage(), 1);
      detail.hidden = !details[i].length;
      for (NSTextField* label in @[ bullet, message, detail ]) [self addSubview:label];
      [bullets addObject:bullet];
      [messages addObject:message];
      [extra addObject:detail];
    }
    _bullets = bullets;
    _messages = messages;
    _details = extra;
  }
  return self;
}
- (CGFloat)layOutForWidth:(CGFloat)width {
  //
  const CGFloat rowSpacing = 8.66, textX = 3 + _bulletWidth + 3 + 8;
  CGFloat y = 1 + PlaceLabel(_heading, 0, 1, width);
  for (NSUInteger i = 0; i < _messages.count; ++i) {
    y += rowSpacing + 1;
    PlaceLabel(_bullets[i], 3, y, _bulletWidth);
    y += PlaceLabel(_messages[i], textX, y, width - textX);
    if (!_details[i].hidden) y += 1 + PlaceLabel(_details[i], textX, y + 1, width - textX);
  }
  self.frame = NSMakeRect(0, 0, width, y);
  return y;
}
@end
// Each imported extension's icon and name over its ExplainerTextWithBullet rows.
@interface PCDialogExtensionList : PCDialogFlippedView <PCDialogDocument>
- (instancetype)initWithItems:(NSArray<PCExtensionInstallItem*>*)items;
@end
@implementation PCDialogExtensionList {
  NSArray<NSImageView*>* _icons;
  NSArray<NSTextField*>* _names;
  NSArray<NSArray<NSTextField*>*>* _rows;
  CGFloat _bulletWidth;
}
- (instancetype)initWithItems:(NSArray<PCExtensionInstallItem*>*)items {
  if ((self = [super initWithFrame:NSZeroRect])) {
    NSFont* font = [NSFont systemFontOfSize:14];
    _bulletWidth = [@"•" sizeWithAttributes:@{NSFontAttributeName : font}].width;
    NSMutableArray* icons = [NSMutableArray array];
    NSMutableArray* names = [NSMutableArray array];
    NSMutableArray* rows = [NSMutableArray array];
    for (PCExtensionInstallItem* item in items) {
      NSImageView* icon = [NSImageView imageViewWithImage:item.icon ?:
          [NSImage imageWithSystemSymbolName:@"puzzlepiece.extension.fill"
                    accessibilityDescription:nil]];
      icon.imageScaling = NSImageScaleProportionallyUpOrDown;
      if (!item.icon) icon.contentTintColor = PopoverTitle();
      [icon setAccessibilityElement:NO];
      NSTextField* name = DialogLabel(item.name, [NSFont systemFontOfSize:14 weight:NSFontWeightMedium],
                                      PopoverTitle(), 1);
      NSMutableArray* labels = [NSMutableArray array];
      for (NSUInteger i = 0; i < item.permissions.count; ++i) {
        NSTextField* bullet = DialogLabel(@"•", font, PopoverMessage(), 1);
        [bullet setAccessibilityElement:NO];
        NSTextField* detail = DialogLabel(item.details[i], font, PopoverMessage(), 1);
        detail.hidden = !item.details[i].length;
        [labels addObjectsFromArray:@[ bullet, DialogLabel(item.permissions[i], font, PopoverMessage(), 1),
                                       detail ]];
      }
      for (NSView* view in [@[ icon, name ] arrayByAddingObjectsFromArray:labels]) [self addSubview:view];
      [icons addObject:icon];
      [names addObject:name];
      [rows addObject:labels];
    }
    _icons = icons;
    _names = names;
    _rows = rows;
  }
  return self;
}
- (CGFloat)layOutForWidth:(CGFloat)width {
  const CGFloat rowSpacing = 8.66, nameX = 24, textX = nameX + 3 + _bulletWidth + 3 + 8;
  CGFloat y = 1;
  for (NSUInteger item = 0; item < _names.count; ++item) {
    if (item) y += 16;
    const CGFloat height = PlaceLabel(_names[item], nameX, y, width - nameX);
    _icons[item].frame = NSMakeRect(0, y + std::floor((height - 18) / 2), 18, 18);
    y += height;
    NSArray<NSTextField*>* labels = _rows[item];
    for (NSUInteger i = 0; i + 2 < labels.count; i += 3) {
      y += rowSpacing + 1;
      PlaceLabel(labels[i], nameX + 3, y, _bulletWidth);
      y += PlaceLabel(labels[i + 1], textX, y, width - textX);
      if (!labels[i + 2].hidden) y += 1 + PlaceLabel(labels[i + 2], textX, y + 1, width - textX);
    }
  }
  self.frame = NSMakeRect(0, 0, width, y);
  return y;
}
@end
@interface PCDialogExplainerScroll : NSScrollView
@property(nonatomic, weak) NSView* fade;
@end
@implementation PCDialogExplainerScroll
@synthesize fade = _fade;
- (void)tile {
  [super tile];
  NSView<PCDialogDocument>* document = self.documentView;
  const CGFloat width = NSWidth(self.contentView.bounds);
  if (document && std::abs(NSWidth(document.frame) - width) > .5) {
    [document layOutForWidth:width];
  }
  [self updateFade];
}
- (void)reflectScrolledClipView:(NSClipView*)clipView {
  [super reflectScrolledClipView:clipView];
  [self updateFade];
}
- (void)updateFade {
  _fade.hidden = NSMaxY(self.contentView.bounds) >= NSHeight(self.documentView.frame) - .5;
}
@end
@implementation PCExtensionInstallItem
@synthesize name = _name, icon = _icon, permissions = _permissions, details = _details;
- (instancetype)initWithName:(NSString*)name
                        icon:(NSImage*)icon
                 permissions:(NSArray<NSString*>*)permissions
                     details:(NSArray<NSString*>*)details {
  NSParameterAssert(name.length && permissions.count == details.count);
  if ((self = [super init])) {
    _name = [name copy];
    _icon = icon;
    _permissions = [permissions copy];
    _details = [details copy];
  }
  return self;
}
@end
@implementation PCExtensionInstallPresenter
- (instancetype)initWithWindow:(NSWindow*)window
                         title:(NSString*)title
                          icon:(NSImage*)icon
                       heading:(NSString*)heading
                   permissions:(NSArray<NSString*>*)permissions
                       details:(NSArray<NSString*>*)details
                   acceptLabel:(NSString*)acceptLabel
                   cancelLabel:(NSString*)cancelLabel
                 checkboxLabel:(NSString*)checkboxLabel
                      validate:(BOOL (^)(void))validate
                  inputAllowed:(BOOL (^)(NSWindow*))inputAllowed
                        result:
                            (void (^)(PCExtensionInstallChoice, BOOL))result {
  NSParameterAssert(window && title.length &&
                    cancelLabel.length && permissions.count == details.count &&
                    validate && inputAllowed && result);
  if ((self = [super init])) {
    _window = window;
    _title = [title copy];
    _icon = icon;
    _heading = [heading copy];
    _permissions = [permissions copy];
    _details = [details copy];
    _acceptLabel = [acceptLabel copy];
    _cancelLabel = [cancelLabel copy];
    _checkboxLabel = [checkboxLabel copy];
    _validate = [validate copy];
    _inputAllowed = [inputAllowed copy];
    _result = [result copy];
    __weak PCExtensionInstallPresenter* weak = self;
    _closeObserver = [NSNotificationCenter.defaultCenter
        addObserverForName:NSWindowWillCloseNotification
                    object:window
                     queue:nil
                usingBlock:^(NSNotification*) {
                  [weak invalidate];
                }];
  }
  return self;
}
- (void)configureJustificationLabel:(NSString*)label
                       placeholder:(NSString*)placeholder
                       counterText:(NSString* (^)(NSUInteger))counter {
  NSParameterAssert(!_started && label.length && counter);
  _justificationLabel = [label copy];
  _justificationPlaceholder = [placeholder copy];
  _justificationCounterText = [counter copy];
}
- (void)configureParentAccounts:(NSArray<NSString*>*)accounts
                   instructions:(NSArray<NSString*>*)instructions
                  passwordLabel:(NSString*)label
                         submit:(void (^)(NSInteger, NSString*))submit {
  NSParameterAssert(!_started && accounts.count && submit && label.length);
  _parentAccounts = [accounts copy];
  _parentInstructions = [instructions copy];
  _parentPasswordLabel = [label copy];
  _parentSubmit = [submit copy];
}
- (void)setParentApprovalPending:(BOOL)pending error:(NSString*)error {
  if (_finished) return;
  _parentPending = pending;
  _parentPassword.stringValue = @"";
  _parentPassword.enabled = !pending;
  _parentChoice.enabled = !pending;
  _parentError.stringValue = error;
  _parentProgress.hidden = !pending;
  if (pending) [_parentProgress startAnimation:nil];
  else {
    [_parentProgress stopAnimation:nil];
    [_sheet makeFirstResponder:_parentPassword];
    if (error.length)
      NSAccessibilityPostNotification(_parentError, NSAccessibilityValueChangedNotification);
  }
  _accept.enabled = [self acceptAllowed];
  [_sheet.contentView layoutSubtreeIfNeeded];
  [_sheet setContentSize:NSMakeSize(480, MAX(230, _stack.fittingSize.height + 44))];
}
- (void)configureInstallationEducationWithName:(NSString*)name {
  NSParameterAssert(!_started && name.length && !_parentAccounts);
  _installationEducation = YES;
  _title = [NSString stringWithFormat:@"Add the “%@” extension to Parc?", name];
  _heading = _permissions.count ? @"It can:"
                               : @"This extension requires no special permissions.";
  _acceptLabel = @"Add Extension";
  _cancelLabel = @"Cancel";
}
- (void)configureImportedExtensions:(NSArray<PCExtensionInstallItem*>*)items {
  NSParameterAssert(!_started && items.count && !_parentAccounts);
  if (items.count == 1) {
    _icon = items[0].icon;
    _permissions = items[0].permissions;
    _details = items[0].details;
    [self configureInstallationEducationWithName:items[0].name];
  } else {
    _installationEducation = YES;
    _items = [items copy];
    _title = [NSString stringWithFormat:@"Add %lu extensions to Parc?", (unsigned long)items.count];
    _acceptLabel = @"Add All";
  }
  _cancelLabel = @"Skip";
}
- (void)controlTextDidChange:(NSNotification*)notification {
  if (notification.object == _parentPassword)
    _accept.enabled = [self acceptAllowed];
}
- (NSString*)justification {
  return [_justificationInput.string copy] ?: @"";
}
- (void)textDidChange:(NSNotification*)notification {
  if (notification.object != _justificationInput || _finished) {
    return;
  }
  const NSUInteger length = _justificationInput.string.length;
  _justificationCounter.stringValue = _justificationCounterText(length);
  _justificationCounter.textColor =
      length <= 280 ? NSColor.secondaryLabelColor : NSColor.systemRedColor;
  _justificationInput.needsDisplay = YES;
  _accept.enabled = [self acceptAllowed];
}
- (BOOL)valid {
  __attribute__((objc_precise_lifetime)) PCExtensionInstallPresenter* keep =
      self;
  (void)keep;
  NSWindow* window = _window;
  if (_invalidated || !window || !window.visible || window.miniaturized) {
    return NO;
  }
  BOOL valid = _validate && _validate();
  return valid && !_invalidated && _window == window && window.visible &&
         !window.miniaturized;
}
- (BOOL)acceptAllowed {
  if (_finished || !_accept || !_sheet.visible || ![self valid] ||
      _justificationInput.string.length > 280 || _parentPending ||
      (_parentAccounts && !_parentPassword.stringValue.length)) {
    return NO;
  }
  BOOL unobstructed = _inputAllowed && _inputAllowed(_sheet);
  if (_finished || !_sheet || ![self valid]) {
    return NO;
  }
  if (!unobstructed) {
    _wasObstructed = YES;
  } else if (_wasObstructed) {
    _wasObstructed = NO;
    _allowAfter = NSProcessInfo.processInfo.systemUptime + .5;
  }
  return unobstructed && NSProcessInfo.processInfo.systemUptime >= _allowAfter;
}
//
- (void)layOutPromptInSheet:(NSWindow*)sheet {
  sheet.styleMask |= NSWindowStyleMaskFullSizeContentView;
  sheet.titlebarAppearsTransparent = YES;
  sheet.titleVisibility = NSWindowTitleHidden;
  sheet.opaque = NO;
  sheet.backgroundColor = PopoverBackground();
  const CGFloat dialogWidth = 450, inset = 38, width = dialogWidth - 2 * inset;
  PCDialogBaseView* root = [[PCDialogBaseView alloc] initWithFrame:NSZeroRect];
  CGFloat y = inset;

  NSURL* markURL = [NSBundle.mainBundle URLForResource:@"Borderless"
                                         withExtension:@"png"
                                          subdirectory:@"AppIcons/Marks"];
  NSImage* mark = markURL ? [[NSImage alloc] initWithContentsOfURL:markURL] : nil;
  NSRect markRect = NSMakeRect(0, 0, 62, 62);
  if (mark.isValid && mark.size.width > 0 && mark.size.height > 0) {
    //
    const CGFloat scale = std::min(52.5 / mark.size.width, 45.5 / mark.size.height);
    const NSSize fitted = NSMakeSize(mark.size.width * scale, mark.size.height * scale);
    markRect = NSMakeRect(31.5 - fitted.width / 2, 31.5 - fitted.height / 2,
                          fitted.width, fitted.height);
  } else {
    mark = NSApp.applicationIconImage;
  }
  PCDialogPictureIcon* app = [[PCDialogPictureIcon alloc] initWithImage:mark imageRect:markRect];
  app.frameOrigin = NSMakePoint(inset, y);
  NSImageView* arrow = [NSImageView imageViewWithImage:
      [NSImage imageWithSystemSymbolName:@"arrow.left" accessibilityDescription:nil]];
  arrow.symbolConfiguration =
      [NSImageSymbolConfiguration configurationWithPointSize:28 weight:NSFontWeightRegular];
  arrow.contentTintColor = PopoverArrowIcon();
  arrow.imageScaling = NSImageScaleNone;
  arrow.frame = NSMakeRect(inset + 62, y, 62, 62);
  NSImageView* extension = [NSImageView imageViewWithImage:_icon ?:
      [NSImage imageWithSystemSymbolName:@"puzzlepiece.extension.fill"
                accessibilityDescription:nil]];
  if (_icon) {
    extension.imageScaling = NSImageScaleProportionallyUpOrDown;
  } else {
    extension.symbolConfiguration = arrow.symbolConfiguration;
    extension.contentTintColor = PopoverTitle();
    extension.imageScaling = NSImageScaleNone;
  }
  extension.frame = NSMakeRect(inset + 124, y, 62, 62);
  for (NSView* view in @[ app, arrow, extension ]) {
    [view setAccessibilityElement:NO];
    [root addSubview:view];
  }
  y += 62;

  NSTextField* title =
      DialogLabel(_title, [NSFont systemFontOfSize:18 weight:NSFontWeightMedium], PopoverTitle(), 4);
  [root addSubview:title];
  y += 17 + PlaceLabel(title, inset, y + 17, width) + 8;

  NSFont* body = [NSFont systemFontOfSize:14];
  if (_items.count || _permissions.count) {
    //
    const CGFloat maxHeight = _items.count ? 260 : 113;
    NSView<PCDialogDocument>* document =
        _items.count ? [[PCDialogExtensionList alloc] initWithItems:_items]
                     : [[PCDialogExplainerDocument alloc] initWithHeading:_heading
                                                              permissions:_permissions
                                                                  details:_details];
    CGFloat contentHeight = [document layOutForWidth:width];
    if (contentHeight > maxHeight && NSScroller.preferredScrollerStyle == NSScrollerStyleLegacy) {
      contentHeight = [document layOutForWidth:width - [NSScroller
          scrollerWidthForControlSize:NSControlSizeRegular scrollerStyle:NSScrollerStyleLegacy]];
    }
    const CGFloat visibleHeight = std::min<CGFloat>(contentHeight, maxHeight);
    PCDialogExplainerScroll* scroll =
        [[PCDialogExplainerScroll alloc] initWithFrame:NSMakeRect(inset, y, width, visibleHeight)];
    scroll.drawsBackground = NO;
    scroll.contentView.drawsBackground = NO;
    scroll.hasVerticalScroller = YES;
    scroll.autohidesScrollers = YES;
    scroll.documentView = document;
    PCDialogFade* fade = [[PCDialogFade alloc]
        initWithFrame:NSMakeRect(inset, y + visibleHeight - 26, width, 26)];
    fade.hidden = contentHeight <= visibleHeight;
    scroll.fade = fade;
    [root addSubview:scroll];
    [root addSubview:fade];
    y += visibleHeight;
  } else if (_heading.length) {
    NSTextField* heading = DialogLabel(_heading, body, PopoverMessage(), 1);
    [root addSubview:heading];
    y += PlaceLabel(heading, inset, y, width) + 8;
  }
  y += 8;

  PCDialogButton* cancel = [[PCDialogButton alloc] initWithTitle:_cancelLabel primary:NO];
  cancel.target = self;
  cancel.action = @selector(cancel:);
  cancel.keyEquivalent = @"\033";
  _accept = [[PCDialogButton alloc] initWithTitle:_acceptLabel primary:YES];
  _accept.target = self;
  _accept.action = @selector(accept:);
  _accept.keyEquivalent = @"\r";
  _accept.enabled = NO;
  NSArray<PCDialogButton*>* buttons = @[ (PCDialogButton*)_accept, cancel ];
  const CGFloat buttonsX =
      dialogWidth - 28 - buttons[0].bodyWidth - 8 - buttons[1].bodyWidth;
  CGFloat footerHeight = 36;
  if (_checkboxLabel.length) {
    _checkbox = [NSButton checkboxWithTitle:_checkboxLabel target:nil action:nil];
    _checkbox.attributedTitle = [[NSAttributedString alloc]
        initWithString:_checkboxLabel
            attributes:@{
              NSFontAttributeName : body,
              NSForegroundColorAttributeName : PopoverMessage()
            }];
    _checkbox.state = NSControlStateValueOff;
    _checkbox.cell.wraps = YES;
    _checkbox.cell.lineBreakMode = NSLineBreakByWordWrapping;
    const CGFloat available = buttonsX - 8 - 38;
    NSSize size = [_checkbox.cell cellSizeForBounds:NSMakeRect(0, 0, available, CGFLOAT_MAX)];
    size = NSMakeSize(std::min(ceil(size.width), available), ceil(size.height));
    footerHeight = std::max(footerHeight, size.height);
    _checkbox.frame = NSMakeRect(38, y + (footerHeight - size.height) / 2, size.width, size.height);
    [root addSubview:_checkbox];
  }
  CGFloat right = dialogWidth - 28;
  for (PCDialogButton* button in buttons) {
    const CGFloat buttonWidth = button.bodyWidth;
    button.frame = NSMakeRect(right - buttonWidth - .5, y + (footerHeight - 36) / 2 - .5,
                              buttonWidth + 1, 38.5);
    [root addSubview:button];
    right -= buttonWidth + 8;
  }
  y += footerHeight + 28;
  root.frame = NSMakeRect(0, 0, dialogWidth, y);
  sheet.contentView = root;
  [sheet setContentSize:NSMakeSize(dialogWidth, y)];
}
- (void)layOutStandardInSheet:(NSWindow*)sheet {
  NSStackView* stack = [NSStackView stackViewWithViews:@[]];
  _stack = stack;
  stack.orientation = NSUserInterfaceLayoutOrientationVertical;
  stack.alignment = NSLayoutAttributeLeading;
  stack.spacing = 12;
  stack.translatesAutoresizingMaskIntoConstraints = NO;
  if (_icon) {
    NSImageView* image = [NSImageView imageViewWithImage:_icon];
    [image.widthAnchor constraintEqualToConstant:48].active = YES;
    [image.heightAnchor constraintEqualToConstant:48].active = YES;
    [stack addArrangedSubview:image];
  }
  NSTextField* title = [NSTextField wrappingLabelWithString:_title];
  title.font = [NSFont boldSystemFontOfSize:15];
  [stack addArrangedSubview:title];
  [title.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;
  if (_heading.length) {
    NSTextField* heading = [NSTextField wrappingLabelWithString:_heading];
    [stack addArrangedSubview:heading];
    [heading.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;
  }
  NSStackView* list = [NSStackView stackViewWithViews:@[]];
  list.orientation = NSUserInterfaceLayoutOrientationVertical;
  list.alignment = NSLayoutAttributeLeading;
  list.spacing = 10;
  list.translatesAutoresizingMaskIntoConstraints = NO;
  for (NSUInteger i = 0; i < _permissions.count; ++i) {
    NSTextField* permission = [NSTextField wrappingLabelWithString:
        [@"• " stringByAppendingString:_permissions[i]]];
    [list addArrangedSubview:permission];
    [permission.widthAnchor constraintEqualToAnchor:list.widthAnchor].active = YES;
    if (_details[i].length) {
      NSTextField* detail = [NSTextField wrappingLabelWithString:_details[i]];
      [list addArrangedSubview:detail];
      [detail.widthAnchor constraintEqualToAnchor:list.widthAnchor].active = YES;
    }
  }
  NSScrollView* scroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
  scroll.hasVerticalScroller = YES;
  scroll.drawsBackground = NO;
  scroll.documentView = list;
  [list.widthAnchor constraintEqualToAnchor:scroll.contentView.widthAnchor]
      .active = YES;
  [stack addArrangedSubview:scroll];
  [scroll.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;
  CGFloat permissionHeight = _permissions.count
      ? (_parentAccounts.count ? 160 : 220) : 0;
  [scroll.heightAnchor constraintEqualToConstant:permissionHeight].active = YES;
  if (_checkboxLabel.length) {
    _checkbox = [NSButton checkboxWithTitle:_checkboxLabel
                                     target:nil
                                     action:nil];
    _checkbox.state = NSControlStateValueOff;
    [stack addArrangedSubview:_checkbox];
  }
  if (_justificationLabel.length) {
    [stack addArrangedSubview:[NSTextField
        wrappingLabelWithString:_justificationLabel]];
    NSScrollView* editor = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    editor.borderType = NSBezelBorder;
    editor.hasVerticalScroller = YES;
    PCExtensionJustificationTextView* input =
        [[PCExtensionJustificationTextView alloc]
            initWithFrame:NSMakeRect(0, 0, 432, 72)];
    input.font = [NSFont systemFontOfSize:13];
    input.richText = NO;
    input.importsGraphics = NO;
    input.verticallyResizable = YES;
    input.horizontallyResizable = NO;
    input.autoresizingMask = NSViewWidthSizable;
    input.textContainer.widthTracksTextView = YES;
    input.textContainerInset = NSMakeSize(6, 6);
    input.placeholder = _justificationPlaceholder;
    input.delegate = self;
    [input setAccessibilityLabel:_justificationLabel];
    _justificationInput = input;
    editor.documentView = input;
    [stack addArrangedSubview:editor];
    [editor.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;
    [editor.heightAnchor constraintEqualToConstant:72].active = YES;
    _justificationCounter = [NSTextField
        labelWithString:_justificationCounterText(0)];
    _justificationCounter.font = [NSFont systemFontOfSize:11];
    _justificationCounter.textColor = NSColor.secondaryLabelColor;
    [stack addArrangedSubview:_justificationCounter];
  }
  if (_parentAccounts.count) {
    for (NSString* instruction in _parentInstructions) {
      [stack addArrangedSubview:[NSTextField wrappingLabelWithString:instruction]];
    }
    _parentChoice = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [_parentChoice addItemsWithTitles:_parentAccounts];
    _parentChoice.accessibilityLabel = @"Parent account";
    [stack addArrangedSubview:_parentChoice];
    [stack addArrangedSubview:[NSTextField labelWithString:_parentPasswordLabel]];
    _parentPassword = [[NSSecureTextField alloc] initWithFrame:NSZeroRect];
    _parentPassword.delegate = self;
    _parentPassword.accessibilityLabel = _parentPasswordLabel;
    [stack addArrangedSubview:_parentPassword];
    [_parentPassword.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;
    _parentError = [NSTextField wrappingLabelWithString:@""];
    _parentError.textColor = NSColor.systemRedColor;
    [stack addArrangedSubview:_parentError];
    [_parentError.heightAnchor constraintGreaterThanOrEqualToConstant:32].active = YES;
    _parentProgress = [[NSProgressIndicator alloc] initWithFrame:NSZeroRect];
    _parentProgress.style = NSProgressIndicatorStyleSpinning;
    _parentProgress.controlSize = NSControlSizeSmall;
    _parentProgress.indeterminate = YES;
    _parentProgress.hidden = YES;
    [stack addArrangedSubview:_parentProgress];
  }
  NSButton* cancel = [NSButton buttonWithTitle:_cancelLabel
                                        target:self
                                        action:@selector(cancel:)];
  cancel.keyEquivalent = @"\033";
  NSMutableArray<NSView*>* buttonViews = [NSMutableArray arrayWithObject:cancel];
  if (_acceptLabel.length) {
    _accept = [NSButton buttonWithTitle:_acceptLabel
                                 target:self
                                 action:@selector(accept:)];
    _accept.enabled = NO;
    _accept.keyEquivalent = @"";
    [buttonViews addObject:_accept];
  }
  NSStackView* buttons = [NSStackView stackViewWithViews:buttonViews];
  buttons.spacing = 10;
  [stack addArrangedSubview:buttons];
  [sheet.contentView addSubview:stack];
  [NSLayoutConstraint activateConstraints:@[
    [stack.leadingAnchor
        constraintEqualToAnchor:sheet.contentView.leadingAnchor
                       constant:24],
    [stack.trailingAnchor
        constraintEqualToAnchor:sheet.contentView.trailingAnchor
                       constant:-24],
    [stack.topAnchor constraintEqualToAnchor:sheet.contentView.topAnchor
                                    constant:22],
    [stack.bottomAnchor constraintEqualToAnchor:sheet.contentView.bottomAnchor
                                       constant:-22]
  ]];
  [sheet.contentView layoutSubtreeIfNeeded];
  [sheet setContentSize:NSMakeSize(480,
                                   MAX(230, stack.fittingSize.height + 44))];
}
- (void)start {
  NSCAssert(NSThread.isMainThread, @"UI thread required");
  if (_started || _finished) {
    return;
  }
  _started = YES;
  Later(^{
    if (self->_finished) {
      return;
    }
    __attribute__((objc_precise_lifetime)) NSWindow* window = self->_window;
    if (![self valid] || !window || window.attachedSheet) {
      [self finish:PCExtensionInstallInterrupted];
      return;
    }
    PCExtensionInstallSheet* sheet = [[PCExtensionInstallSheet alloc]
        initWithContentRect:NSMakeRect(0, 0, 480, 320)
                  styleMask:NSWindowStyleMaskTitled
                    backing:NSBackingStoreBuffered
                      defer:NO];
    sheet.releasedWhenClosed = NO;
    sheet.title = self->_title;
    sheet.request = self;
    if (self->_installationEducation) {
      [self layOutPromptInSheet:sheet];
    } else {
      [self layOutStandardInSheet:sheet];
    }
    if (self->_finished || ![self valid] || window.attachedSheet) {
      [self finish:PCExtensionInstallInterrupted];
      return;
    }
    self->_sheet = sheet;
    [window beginSheet:sheet
        completionHandler:^(NSModalResponse) {
          [self finish:PCExtensionInstallInterrupted];
        }];
    if (self->_finished || ![self valid] || sheet.sheetParent != window ||
        window.attachedSheet != sheet || !sheet.visible) {
      [self finish:PCExtensionInstallInterrupted];
      return;
    }
    if (self->_parentPassword) [sheet makeFirstResponder:self->_parentPassword];
    // Current Chromium starts its 500ms protection at actual first visibility.
    self->_allowAfter = NSProcessInfo.processInfo.systemUptime + .5;
    __weak PCExtensionInstallPresenter* weak = self;
    self->_timer = [NSTimer
        timerWithTimeInterval:.05
                      repeats:YES
                        block:^(NSTimer*) {
                          PCExtensionInstallPresenter* strong = weak;
                          if (!strong || strong->_finished) {
                            return;
                          }
                          if (![strong valid]) {
                            [strong finish:PCExtensionInstallInterrupted];
                            return;
                          }
                          strong->_accept.enabled = [strong acceptAllowed];
                        }];
    [NSRunLoop.mainRunLoop addTimer:self->_timer forMode:NSRunLoopCommonModes];
    [NSRunLoop.mainRunLoop addTimer:self->_timer
                            forMode:NSModalPanelRunLoopMode];
  });
}
- (void)accept:(NSButton*)sender {
  if (sender != _accept || sender.window != _sheet || ![self acceptAllowed]) {
    return;
  }
  //
  // the input delay ended; NSEvent timestamps share systemUptime's clock.
  NSEvent* key = [sender isKindOfClass:PCDialogButton.class]
                     ? ((PCDialogButton*)sender).keyEvent
                     : nil;
  if (key && (key.isARepeat || key.timestamp < _allowAfter)) {
    return;
  }
  if (_parentSubmit) {
    // The secure field is cleared before either network request starts.
    NSString* credential = [_parentPassword.stringValue copy];
    NSInteger parent = _parentChoice.indexOfSelectedItem;
    _parentPassword.stringValue = @"";
    auto submit = _parentSubmit;
    submit(parent, credential);
    return;
  }
  [self finish:PCExtensionInstallAccept];
}
- (void)cancel:(NSButton*)sender {
  if (sender.window != _sheet) {
    return;
  }
  [self finish:PCExtensionInstallCancel];
}
- (void)finish:(PCExtensionInstallChoice)choice {
  if (_finished) {
    return;
  }
  _finished = YES;
  _parentPassword.stringValue = @"";
  _parentSubmit = nil;
  [_parentProgress stopAnimation:nil];
  [_timer invalidate];
  _timer = nil;
  BOOL checked = _checkbox && _checkbox.state == NSControlStateValueOn;
  NSWindow* sheet = _sheet;
  _sheet = nil;
  if (sheet.sheetParent) {
    [sheet.sheetParent endSheet:sheet];
  }
  [sheet orderOut:nil];
  Later(^{
    if (!self->_result) {
      return;
    }
    BOOL valid = [self valid];
    if (choice == PCExtensionInstallAccept) {
      valid = valid && self->_inputAllowed && self->_inputAllowed(sheet) &&
              [self valid];
    }
    auto result = self->_result;
    self->_result = nil;
    self->_validate = nil;
    self->_inputAllowed = nil;
    result(valid ? choice : PCExtensionInstallInterrupted, checked);
  });
}
- (void)invalidate {
  _invalidated = YES;
  [self finish:PCExtensionInstallInterrupted];
}
- (NSWindow*)sheet {
  return _sheet;
}
- (void)dealloc {
  [_timer invalidate];
  if (_closeObserver) {
    [NSNotificationCenter.defaultCenter removeObserver:_closeObserver];
  }
  NSCAssert(!_sheet, @"Owner must invalidate presented consent");
}
@end
