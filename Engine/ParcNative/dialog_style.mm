#import "dialog_style.h"

#include <algorithm>
#include <cmath>

namespace parc_dialog {
namespace {
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
}  // namespace
#define PC_DIALOG_COLOR(name, light, lightAlpha, dark, darkAlpha)            \
  NSColor* name() {                                                          \
    static NSColor* color = DialogColor(light, lightAlpha, dark, darkAlpha); \
    return color;                                                            \
  }
PC_DIALOG_COLOR(PopoverBackground, 0xFAFBFF, 1, 0x151C30, 1)
PC_DIALOG_COLOR(PopoverTitle, 0x181B1F, 1, 0xFFFFFF, 1)
PC_DIALOG_COLOR(PopoverMessage, 0x060E2B, .75, 0xEEEEF6, .75)
PC_DIALOG_COLOR(PopoverArrowIcon, 0x1E2E69, .3, 0xEEEEF6, .3)
// OnboardingSetupPalette.action, the onboarding selection mark's color.
PC_DIALOG_COLOR(SelectionColor, 0x3139FB, 1, 0x3139FB, 1)
namespace {
PC_DIALOG_COLOR(PopoverLogoBackground, 0xFFFFFF, .9, 0xFFFFFF, .6)
PC_DIALOG_COLOR(PopoverLogoShadow, 0x000000, .15, 0xFFFFFF, 0)
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
PC_DIALOG_COLOR(DestructiveButtonFace, 0xF53714, 1, 0xF53714, 1)
PC_DIALOG_COLOR(DestructiveButtonHovered, 0xDD3112, 1, 0xDD3112, 1)
PC_DIALOG_COLOR(DestructiveButtonPressed, 0xD02F11, 1, 0xD02F11, 1)
PC_DIALOG_COLOR(DestructiveButtonShadow, 0xB4250A, .3, 0xB4250A, .3)
PC_DIALOG_COLOR(Indigo4, 0xE8E9FF, 1, 0x1C1D4F, 1)
PC_DIALOG_COLOR(Indigo6, 0xC8CAFA, 1, 0x22246E, 1)
}  // namespace
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

NSTextField* Label(NSString* text, NSFont* font, NSColor* color, CGFloat lineSpacing) {
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
CGFloat PlaceLabel(NSTextField* label, CGFloat x, CGFloat y, CGFloat width) {
  const CGFloat inset = 2;
  label.preferredMaxLayoutWidth = width + 2 * inset;
  const CGFloat height = ceil(
      [label.cell cellSizeForBounds:NSMakeRect(0, 0, width + 2 * inset, CGFLOAT_MAX)].height);
  label.frame = NSMakeRect(x - inset, y, width + 2 * inset, height);
  return height;
}
NSFont* TitleFont() {
  return [NSFont systemFontOfSize:18 weight:NSFontWeightMedium];
}
NSFont* BodyFont() {
  return [NSFont systemFontOfSize:14];
}
namespace {
NSFont* ButtonFont() {
  return [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
}
NSFont* HintFont() {
  NSFont* bold = [NSFont systemFontOfSize:11 weight:NSFontWeightBold];
  NSFontDescriptor* rounded =
      [bold.fontDescriptor fontDescriptorWithDesign:NSFontDescriptorSystemDesignRounded];
  return [NSFont fontWithDescriptor:rounded size:11] ?: bold;
}
}  // namespace

void PrepareSheet(NSWindow* sheet) {
  sheet.styleMask |= NSWindowStyleMaskFullSizeContentView;
  sheet.titlebarAppearsTransparent = YES;
  sheet.titleVisibility = NSWindowTitleHidden;
  sheet.opaque = NO;
  sheet.backgroundColor = PopoverBackground();
}

NSImage* ParcMark(NSRect* imageRect) {
  NSURL* markURL = [NSBundle.mainBundle URLForResource:@"Borderless"
                                         withExtension:@"png"
                                          subdirectory:@"AppIcons/Marks"];
  NSImage* mark = markURL ? [[NSImage alloc] initWithContentsOfURL:markURL] : nil;
  *imageRect = NSMakeRect(0, 0, kArtSize, kArtSize);
  if (mark.isValid && mark.size.width > 0 && mark.size.height > 0) {
    //
    const CGFloat scale = std::min(52.5 / mark.size.width, 45.5 / mark.size.height);
    const NSSize fitted = NSMakeSize(mark.size.width * scale, mark.size.height * scale);
    *imageRect = NSMakeRect(31.5 - fitted.width / 2, 31.5 - fitted.height / 2,
                            fitted.width, fitted.height);
    return mark;
  }
  return NSApp.applicationIconImage;
}

NSImageView* ExtensionArt(NSImage* icon) {
  NSImageView* view = [NSImageView imageViewWithImage:icon ?:
      [NSImage imageWithSystemSymbolName:@"puzzlepiece.extension.fill"
                accessibilityDescription:nil]];
  if (icon) {
    view.imageScaling = NSImageScaleProportionallyUpOrDown;
  } else {
    view.symbolConfiguration =
        [NSImageSymbolConfiguration configurationWithPointSize:28 weight:NSFontWeightRegular];
    view.contentTintColor = PopoverTitle();
    view.imageScaling = NSImageScaleNone;
  }
  view.frame = NSMakeRect(0, 0, kArtSize, kArtSize);
  [view setAccessibilityElement:NO];
  return view;
}

CGFloat AddHeading(NSView* root, NSString* title, NSString* message, CGFloat y,
                   CGFloat maxMessageHeight) {
  const CGFloat width = kWidth - 2 * kInset;
  NSTextField* heading = Label(title, TitleFont(), PopoverTitle(), 4);
  [root addSubview:heading];
  y += 17 + PlaceLabel(heading, kInset, y + 17, width) + 8;
  if (!message.length) return y;
  NSTextField* label = Label(message, BodyFont(), PopoverMessage(), 1);
  CGFloat height = PlaceLabel(label, kInset, y, width);
  if (height <= maxMessageHeight) {
    [root addSubview:label];
    return y + height;
  }
  CGFloat textWidth = width;
  if (NSScroller.preferredScrollerStyle == NSScrollerStyleLegacy) {
    textWidth -= [NSScroller scrollerWidthForControlSize:NSControlSizeRegular
                                           scrollerStyle:NSScrollerStyleLegacy];
  }
  height = PlaceLabel(label, 2, 0, textWidth);
  PCDialogFlippedView* document =
      [[PCDialogFlippedView alloc] initWithFrame:NSMakeRect(0, 0, NSWidth(label.frame), height)];
  [document addSubview:label];
  NSScrollView* scroll = [[NSScrollView alloc]
      initWithFrame:NSMakeRect(kInset - 2, y, width + 4, maxMessageHeight)];
  scroll.drawsBackground = NO;
  scroll.contentView.drawsBackground = NO;
  scroll.hasVerticalScroller = YES;
  scroll.autohidesScrollers = YES;
  scroll.documentView = document;
  [root addSubview:scroll];
  return y + maxMessageHeight;
}

CGFloat PlaceFooter(NSView* root, CGFloat y, NSButton* checkbox, NSArray<NSButton*>* buttons) {
  CGFloat buttonsWidth = 0;
  for (NSButton* button in buttons) {
    buttonsWidth += ((PCDialogButton*)button).bodyWidth;
  }
  const CGFloat buttonsX =
      kWidth - 28 - buttonsWidth - 8 * (CGFloat)(buttons.count ? buttons.count - 1 : 0);
  CGFloat footerHeight = 36;
  if (checkbox) {
    const CGFloat available = buttonsX - 8 - kInset;
    NSSize size;
    if ([checkbox isKindOfClass:PCDialogCheckbox.class]) {
      size = [(PCDialogCheckbox*)checkbox sizeForWidth:available];
    } else {
      size = [checkbox.cell cellSizeForBounds:NSMakeRect(0, 0, available, CGFLOAT_MAX)];
      size = NSMakeSize(std::min(ceil(size.width), available), ceil(size.height));
    }
    footerHeight = std::max(footerHeight, size.height);
    checkbox.frame =
        NSMakeRect(kInset, y + (footerHeight - size.height) / 2, size.width, size.height);
    [root addSubview:checkbox];
  }
  CGFloat right = kWidth - 28;
  for (NSButton* button in buttons) {
    // The view extends past the 36-point body for its centered border and lip.
    const CGFloat buttonWidth = ((PCDialogButton*)button).bodyWidth;
    button.frame = NSMakeRect(right - buttonWidth - .5, y + (footerHeight - 36) / 2 - .5,
                              buttonWidth + 1, 38.5);
    [root addSubview:button];
    right -= buttonWidth + 8;
  }
  return y + footerHeight + 28;
}
}  // namespace parc_dialog

using namespace parc_dialog;

@implementation PCDialogFlippedView
- (BOOL)isFlipped {
  return YES;
}
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

@implementation PCDialogPictureIcon {
  NSImage* _image;
  NSRect _imageRect;
}
- (instancetype)initWithImage:(NSImage*)image imageRect:(NSRect)imageRect {
  if ((self = [super initWithFrame:NSMakeRect(0, 0, kArtSize, kArtSize)])) {
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

@implementation PCDialogButton {
  BOOL _primary;
  BOOL _destructive;
  BOOL _hovered;
  NSTrackingArea* _tracking;
  NSString* _hintText;
  NSImage* _hintSymbol;
}
@synthesize keyEvent = _keyEvent;
@synthesize showsHint = _showsHint;
- (instancetype)initWithTitle:(NSString*)title primary:(BOOL)primary {
  return [self initWithTitle:title primary:primary destructive:NO];
}
- (instancetype)initWithTitle:(NSString*)title
                      primary:(BOOL)primary
                  destructive:(BOOL)destructive {
  if ((self = [super initWithFrame:NSZeroRect])) {
    _primary = primary;
    _destructive = primary && destructive;
    _showsHint = YES;
    self.title = title;
    self.bordered = NO;
    self.buttonType = NSButtonTypeMomentaryPushIn;
    self.font = ButtonFont();
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
  return [_hintText sizeWithAttributes:@{NSFontAttributeName : HintFont()}];
}
- (NSSize)hintSize {
  const NSSize content = [self hintContentSize];
  return NSMakeSize(content.width + 12, content.height + 6);
}
- (CGFloat)labelWidth {
  return [self.title sizeWithAttributes:@{NSFontAttributeName : ButtonFont()}].width;
}
- (CGFloat)bodyWidth {
  return 12 + [self labelWidth] + (_showsHint ? 8 + [self hintSize].width : 0) + 12;
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
    foreground = self.enabled ? NeutralButtonForeground() : PopoverArrowIcon();
    border = NeutralButtonBorder();
    shadow = NeutralButtonShadow();
    hintForeground = NeutralButtonIconForeground();
    hintBackground = NeutralButtonIconBackground();
  } else if (self.enabled && _destructive) {
    // DestructiveButton face and lip; label, border and badge stay primary.
    face = pressed    ? DestructiveButtonPressed()
           : _hovered ? DestructiveButtonHovered()
                      : DestructiveButtonFace();
    foreground = PrimaryButtonForeground();
    shadow = DestructiveButtonShadow();
    hintForeground = PrimaryButtonIconForeground();
    hintBackground = PrimaryButtonIconBackground();
    hintBorder = PrimaryButtonIconBorder();
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
    NSFontAttributeName : ButtonFont(),
    NSForegroundColorAttributeName : foreground
  };
  const NSSize label = [self.title sizeWithAttributes:attributes];
  [self.title drawAtPoint:NSMakePoint(NSMinX(body) + 12, NSMidY(body) - label.height / 2)
           withAttributes:attributes];
  if (!_showsHint) return;
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
              NSFontAttributeName : HintFont(),
              NSForegroundColorAttributeName : hintForeground
            }];
  }
}
@end

@implementation PCDialogCheckbox
- (instancetype)initWithTitle:(NSString*)title target:(id)target action:(SEL)action {
  if ((self = [super initWithFrame:NSZeroRect])) {
    // The switch type keeps the checkbox role and AppKit's click/Space toggle.
    [self setButtonType:NSButtonTypeSwitch];
    self.bordered = NO;
    self.title = title;
    self.font = BodyFont();
    self.target = target;
    self.action = action;
    self.state = NSControlStateValueOff;
  }
  return self;
}
- (BOOL)isFlipped {
  return YES;
}
- (NSImage*)markForState:(NSControlStateValue)state {
  NSImageSymbolConfiguration* configuration =
      [NSImageSymbolConfiguration configurationWithPointSize:14
                                                      weight:NSFontWeightRegular
                                                       scale:NSImageSymbolScaleLarge];
  NSString* name = state == NSControlStateValueOn ? @"checkmark.circle.fill" : @"circle";
  return [[NSImage imageWithSystemSymbolName:name accessibilityDescription:nil]
      imageWithSymbolConfiguration:configuration];
}
- (NSSize)markSize {
  return [self markForState:NSControlStateValueOff].size;
}
- (NSDictionary*)labelAttributes {
  return @{
    NSFontAttributeName : BodyFont(),
    NSForegroundColorAttributeName : self.enabled
        ? PopoverMessage()
        : [PopoverMessage() colorWithAlphaComponent:.3]
  };
}
- (NSSize)labelSizeForWidth:(CGFloat)width {
  const NSRect bounds =
      [self.title boundingRectWithSize:NSMakeSize(std::max<CGFloat>(width, 1), CGFLOAT_MAX)
                               options:NSStringDrawingUsesLineFragmentOrigin
                            attributes:[self labelAttributes]];
  return NSMakeSize(ceil(NSWidth(bounds)), ceil(NSHeight(bounds)));
}
- (CGFloat)firstLineHeight {
  NSFont* font = BodyFont();
  return ceil(font.ascender - font.descender + font.leading);
}
- (NSSize)sizeForWidth:(CGFloat)width {
  const NSSize mark = [self markSize];
  const NSSize label = [self labelSizeForWidth:width - mark.width - 8];
  return NSMakeSize(std::min(width, ceil(mark.width) + 8 + label.width),
                    std::max(ceil(mark.height), label.height));
}
- (NSSize)intrinsicContentSize {
  return [self sizeForWidth:CGFLOAT_MAX];
}
- (NSRect)markRect {
  const NSSize mark = [self markSize];
  return NSMakeRect(0, std::max<CGFloat>(0, ([self firstLineHeight] - mark.height) / 2),
                    mark.width, mark.height);
}
- (void)setState:(NSControlStateValue)state {
  const BOOL changed = state != self.state;
  [super setState:state];
  if (!changed) return;
  self.needsDisplay = YES;
  NSAccessibilityPostNotification(self, NSAccessibilityValueChangedNotification);
}
- (void)setEnabled:(BOOL)enabled {
  [super setEnabled:enabled];
  self.needsDisplay = YES;
}
- (NSAccessibilityRole)accessibilityRole {
  return NSAccessibilityCheckBoxRole;
}
- (id)accessibilityValue {
  return self.state == NSControlStateValueOn ? @"Selected" : @"Not selected";
}
- (void)resetCursorRects {
  if (self.enabled) [self addCursorRect:self.bounds cursor:NSCursor.pointingHandCursor];
}
// Space toggles; Return and Escape continue to the sheet's buttons.
- (void)keyDown:(NSEvent*)event {
  const NSEventModifierFlags modifiers =
      event.modifierFlags & (NSEventModifierFlagCommand | NSEventModifierFlagControl |
                             NSEventModifierFlagOption | NSEventModifierFlagShift);
  if (!modifiers && [event.charactersIgnoringModifiers isEqualToString:@" "]) {
    if (self.enabled) [self performClick:self];
    return;
  }
  [self.nextResponder keyDown:event];
}
- (NSRect)focusRingMaskBounds {
  return [self markRect];
}
- (void)drawFocusRingMask {
  [[NSBezierPath bezierPathWithOvalInRect:NSInsetRect([self markRect], .5, .5)] fill];
}
- (void)viewDidChangeEffectiveAppearance {
  self.needsDisplay = YES;
}
- (void)drawRect:(NSRect)dirtyRect {
  const NSRect mark = [self markRect];
  CGContextRef context = NSGraphicsContext.currentContext.CGContext;
  CGContextSaveGState(context);
  if (!self.enabled) CGContextSetAlpha(context, .5);
  // Monochrome tint, so the checkmark stays cut out of the filled circle.
  CGContextBeginTransparencyLayerWithRect(context, NSRectToCGRect(mark), nullptr);
  [[self markForState:self.state] drawInRect:mark fromRect:NSZeroRect
                                   operation:NSCompositingOperationSourceOver
                                    fraction:1 respectFlipped:YES hints:nil];
  [SelectionColor() set];
  NSRectFillUsingOperation(mark, NSCompositingOperationSourceAtop);
  CGContextEndTransparencyLayer(context);
  CGContextRestoreGState(context);
  const CGFloat x = ceil(NSWidth(mark)) + 8;
  const CGFloat width = NSWidth(self.bounds) - x;
  const NSSize label = [self labelSizeForWidth:width];
  const CGFloat y = std::max<CGFloat>(0, (NSHeight(mark) - [self firstLineHeight]) / 2);
  [self.title drawWithRect:NSMakeRect(x, y, width, label.height)
                   options:NSStringDrawingUsesLineFragmentOrigin
                attributes:[self labelAttributes]];
}
@end

@interface PCDialogInputTextField : NSTextField
@property(nonatomic, weak) NSView* frameView;
@end
@implementation PCDialogInputTextField
@synthesize frameView = _frameView;
- (BOOL)becomeFirstResponder {
  const BOOL accepted = [super becomeFirstResponder];
  _frameView.needsDisplay = YES;
  return accepted;
}
- (void)textDidEndEditing:(NSNotification*)notification {
  [super textDidEndEditing:notification];
  _frameView.needsDisplay = YES;
}
@end

@implementation PCDialogInputField {
  PCDialogInputTextField* _field;
  NSArray<id>* _keyObservers;
}
// The body is 36 points tall, like the buttons, inside a 3-point halo margin.
static const CGFloat kHalo = 3;
- (instancetype)initWithText:(NSString*)text {
  if ((self = [super initWithFrame:NSMakeRect(0, 0, 100, 36 + 2 * kHalo)])) {
    _field = [[PCDialogInputTextField alloc] initWithFrame:NSZeroRect];
    _field.frameView = self;
    _field.stringValue = text;
    _field.bordered = NO;
    _field.bezeled = NO;
    _field.drawsBackground = NO;
    _field.focusRingType = NSFocusRingTypeNone;
    _field.font = BodyFont();
    _field.textColor = PopoverTitle();
    _field.usesSingleLineMode = YES;
    _field.lineBreakMode = NSLineBreakByTruncatingTail;
    _field.cell.scrollable = YES;
    _field.cell.wraps = NO;
    _field.editable = YES;
    _field.selectable = YES;
    [self addSubview:_field];
    [self layOutField];
  }
  return self;
}
- (NSTextField*)field {
  return _field;
}
- (NSRect)body {
  return NSInsetRect(self.bounds, kHalo, kHalo);
}
- (void)layOutField {
  const NSRect body = [self body];
  const CGFloat height = ceil(_field.intrinsicContentSize.height);
  // Like the labels, the text (not the cell's 2-point inset) sits 12 points in.
  _field.frame = NSMakeRect(NSMinX(body) + 10, NSMidY(body) - height / 2,
                            NSWidth(body) - 20, height);
}
- (void)setFrameSize:(NSSize)size {
  [super setFrameSize:size];
  [self layOutField];
}
- (BOOL)editing {
  NSWindow* window = self.window;
  NSText* editor = _field.currentEditor;
  return window.isKeyWindow && editor && window.firstResponder == editor;
}
- (void)viewWillMoveToWindow:(NSWindow*)window {
  for (id observer in _keyObservers) {
    [NSNotificationCenter.defaultCenter removeObserver:observer];
  }
  _keyObservers = nil;
  if (!window) return;
  __weak PCDialogInputField* weak = self;
  void (^redraw)(NSNotification*) = ^(NSNotification*) {
    weak.needsDisplay = YES;
  };
  _keyObservers = @[
    [NSNotificationCenter.defaultCenter addObserverForName:NSWindowDidBecomeKeyNotification
                                                    object:window
                                                     queue:nil
                                                usingBlock:redraw],
    [NSNotificationCenter.defaultCenter addObserverForName:NSWindowDidResignKeyNotification
                                                    object:window
                                                     queue:nil
                                                usingBlock:redraw],
  ];
}
- (void)dealloc {
  for (id observer in _keyObservers) {
    [NSNotificationCenter.defaultCenter removeObserver:observer];
  }
}
- (void)mouseDown:(NSEvent*)event {
  [self.window makeFirstResponder:_field];
}
- (void)resetCursorRects {
  [self addCursorRect:[self body] cursor:NSCursor.IBeamCursor];
}
- (void)viewDidChangeEffectiveAppearance {
  self.needsDisplay = YES;
}
- (void)drawRect:(NSRect)dirtyRect {
  const NSRect body = [self body];
  const BOOL editing = [self editing];
  if (editing) {
    [[SelectionColor() colorWithAlphaComponent:.18] setFill];
    [ContinuousRect(NSInsetRect(body, -kHalo, -kHalo), 8 + kHalo) fill];
  }
  NSBezierPath* shape = ContinuousRect(NSInsetRect(body, .5, .5), 8);
  [NeutralButtonFace() setFill];
  [shape fill];
  [(editing ? SelectionColor() : NeutralButtonBorder()) setStroke];
  shape.lineWidth = 1;
  [shape stroke];
}
@end
