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
// The Space name card's tint, behind a dialog input.
PC_DIALOG_COLOR(FieldFill, 0x060E2B, .07, 0xEEEEF6, .10)
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
                   CGFloat maxMessageHeight, bool selectableMessage) {
  const CGFloat width = kWidth - 2 * kInset;
  NSTextField* heading = Label(title, TitleFont(), PopoverTitle(), 4);
  [root addSubview:heading];
  y += 17 + PlaceLabel(heading, kInset, y + 17, width) + 8;
  if (!message.length) return y;
  NSTextField* label = Label(message, BodyFont(), PopoverMessage(), 1);
  label.selectable = selectableMessage;
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
  const CGFloat left = 28, right = kWidth - 28, rowWidth = right - left, gap = 8;
  // Rows of buttons, the first being the bottom row with the Return button.
  NSMutableArray<NSMutableArray<PCDialogButton*>*>* rows = [NSMutableArray array];
  CGFloat used = 0;
  for (NSButton* item in buttons) {
    PCDialogButton* button = (PCDialogButton*)item;
    if (button.bodyWidth > rowWidth) button.maximumWidth = rowWidth;
    const CGFloat width = button.bodyWidth;
    if (!rows.count || used + gap + width > rowWidth) {
      [rows addObject:[NSMutableArray arrayWithObject:button]];
      used = width;
    } else {
      [rows.lastObject addObject:button];
      used += gap + width;
    }
  }
  CGFloat bottomWidth = 0;
  for (PCDialogButton* button in rows.firstObject) {
    bottomWidth += button.bodyWidth + (bottomWidth ? gap : 0);
  }
  // A checkbox shares the bottom row only with room for a readable label.
  NSSize checkboxSize = NSZeroSize;
  BOOL checkboxRow = NO;
  if (checkbox) {
    CGFloat available = right - bottomWidth - gap - kInset;
    if (available < 100) {
      checkboxRow = YES;
      available = kWidth - 2 * kInset;
    }
    if ([checkbox isKindOfClass:PCDialogCheckbox.class]) {
      checkboxSize = [(PCDialogCheckbox*)checkbox sizeForWidth:available];
    } else {
      checkboxSize = [checkbox.cell cellSizeForBounds:NSMakeRect(0, 0, available, CGFLOAT_MAX)];
      checkboxSize = NSMakeSize(std::min(ceil(checkboxSize.width), available),
                                ceil(checkboxSize.height));
    }
    if (checkboxRow) {
      checkbox.frame = NSMakeRect(kInset, y, checkboxSize.width, checkboxSize.height);
      [root addSubview:checkbox];
      y += checkboxSize.height + 16;
    }
  }
  auto placeRow = [&](NSArray<PCDialogButton*>* row, CGFloat top, CGFloat height) {
    CGFloat x = right;
    for (PCDialogButton* button in row) {
      // The view extends past the 36-point body for its centered border and lip.
      const CGFloat width = button.bodyWidth;
      button.frame = NSMakeRect(x - width - .5, top + (height - 36) / 2 - .5, width + 1, 38.5);
      [root addSubview:button];
      x -= width + gap;
    }
  };
  for (NSInteger i = (NSInteger)rows.count - 1; i > 0; --i) {
    placeRow(rows[i], y, 36);
    y += 36 + 10;
  }
  CGFloat footerHeight = 36;
  if (checkbox && !checkboxRow) {
    footerHeight = std::max(footerHeight, checkboxSize.height);
    checkbox.frame = NSMakeRect(kInset, y + (footerHeight - checkboxSize.height) / 2,
                                checkboxSize.width, checkboxSize.height);
    [root addSubview:checkbox];
  }
  if (rows.count) placeRow(rows.firstObject, y, footerHeight);
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
@synthesize maximumWidth = _maximumWidth;
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
  const CGFloat natural = 12 + [self labelWidth] + (_showsHint ? 8 + [self hintSize].width : 0) + 12;
  return _maximumWidth > 0 ? std::min(natural, _maximumWidth) : natural;
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
  NSMutableParagraphStyle* paragraph = [[NSMutableParagraphStyle alloc] init];
  paragraph.lineBreakMode = NSLineBreakByTruncatingTail;
  NSDictionary* attributes = @{
    NSFontAttributeName : ButtonFont(),
    NSForegroundColorAttributeName : foreground,
    NSParagraphStyleAttributeName : paragraph
  };
  const NSSize hint = [self hintSize];
  const NSSize label = [self.title sizeWithAttributes:attributes];
  const CGFloat labelWidth =
      NSWidth(body) - 24 - (_showsHint ? 8 + hint.width : 0);
  [self.title drawInRect:NSMakeRect(NSMinX(body) + 12, NSMidY(body) - label.height / 2,
                                    std::max<CGFloat>(labelWidth, 0), label.height)
          withAttributes:attributes];
  if (!_showsHint) return;
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

//
// are the selection marks, so AppKit lays it out and draws keyboard focus.
@implementation PCDialogCheckbox
- (instancetype)initWithTitle:(NSString*)title target:(id)target action:(SEL)action {
  if ((self = [super initWithFrame:NSZeroRect])) {
    [self setButtonType:NSButtonTypeSwitch];
    self.bordered = NO;
    self.imagePosition = NSImageLeading;
    NSImageSymbolConfiguration* large =
        [NSImageSymbolConfiguration configurationWithScale:NSImageSymbolScaleLarge];
    self.image = [[NSImage imageWithSystemSymbolName:@"circle" accessibilityDescription:nil]
        imageWithSymbolConfiguration:large];
    self.alternateImage =
        [[NSImage imageWithSystemSymbolName:@"checkmark.circle.fill" accessibilityDescription:nil]
            imageWithSymbolConfiguration:large];
    self.contentTintColor = SelectionColor();
    self.attributedTitle = [[NSAttributedString alloc]
        initWithString:title
            attributes:@{
              NSFontAttributeName : BodyFont(),
              NSForegroundColorAttributeName : PopoverMessage()
            }];
    self.cell.wraps = YES;
    self.cell.lineBreakMode = NSLineBreakByWordWrapping;
    self.target = target;
    self.action = action;
    self.state = NSControlStateValueOff;
  }
  return self;
}
- (NSSize)sizeForWidth:(CGFloat)width {
  const NSSize size = [self.cell cellSizeForBounds:NSMakeRect(0, 0, width, CGFLOAT_MAX)];
  return NSMakeSize(std::min(ceil(size.width), width), ceil(size.height));
}
- (NSAccessibilityRole)accessibilityRole {
  return NSAccessibilityCheckBoxRole;
}
- (id)accessibilityValue {
  return self.state == NSControlStateValueOn ? @"Selected" : @"Not selected";
}
- (BOOL)sendAction:(SEL)action to:(id)target {
  NSAccessibilityPostNotification(self, NSAccessibilityValueChangedNotification);
  return [super sendAction:action to:target];
}
- (void)resetCursorRects {
  if (self.enabled) [self addCursorRect:self.bounds cursor:NSCursor.pointingHandCursor];
}
// Space toggles (not Command-, Option- or Control-Space, nor a repeat); every
// other key, Return and Escape included, continues to the dialog.
- (void)keyDown:(NSEvent*)event {
  if (event.keyCode == 49 &&
      !(event.modifierFlags &
        (NSEventModifierFlagCommand | NSEventModifierFlagOption | NSEventModifierFlagControl))) {
    if (!event.isARepeat) [self performClick:nil];
    return;
  }
  [self.nextResponder keyDown:event];
}
@end

@implementation PCDialogCard
@synthesize field = _field;
- (void)mouseDown:(NSEvent*)event {
  NSView* field = _field;
  if (field) {
    [self.window makeFirstResponder:field];
  } else {
    [super mouseDown:event];
  }
}
- (void)viewDidChangeEffectiveAppearance {
  self.needsDisplay = YES;
}
- (void)drawRect:(NSRect)dirtyRect {
  [FieldFill() setFill];
  [ContinuousRect(self.bounds, 8) fill];
}
@end

//
// card without a focus ring, and a press on the card's padding focuses it.
@implementation PCDialogInputField {
  NSTextField* _field;
}
static const CGFloat kFieldPadding = 12;
- (instancetype)initWithText:(NSString*)text {
  return [self initWithText:text secure:NO];
}
- (instancetype)initWithText:(NSString*)text secure:(BOOL)secure {
  if ((self = [super initWithFrame:NSMakeRect(0, 0, 100, 36)])) {
    _field = secure ? [[NSSecureTextField alloc] initWithFrame:NSZeroRect]
                    : [[NSTextField alloc] initWithFrame:NSZeroRect];
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
- (void)layOutField {
  const CGFloat height = ceil(_field.intrinsicContentSize.height);
  // The cell's 2-point inset puts the text itself on the 12-point padding.
  _field.frame = NSMakeRect(kFieldPadding - 2, (NSHeight(self.bounds) - height) / 2,
                            NSWidth(self.bounds) - 2 * kFieldPadding + 4, height);
}
- (void)setFrameSize:(NSSize)size {
  [super setFrameSize:size];
  [self layOutField];
}
- (void)mouseDown:(NSEvent*)event {
  [self.window makeFirstResponder:_field];
}
- (void)viewDidChangeEffectiveAppearance {
  self.needsDisplay = YES;
}
- (void)drawRect:(NSRect)dirtyRect {
  [FieldFill() setFill];
  [ContinuousRect(self.bounds, 8) fill];
}
@end

@implementation PCDialogPanel
@synthesize enterButton = _enterButton;
@synthesize escapeButton = _escapeButton;
- (BOOL)composing {
  NSResponder* responder = self.firstResponder;
  return [responder isKindOfClass:NSTextView.class] && ((NSTextView*)responder).hasMarkedText;
}
- (void)cancelOperation:(id)sender {
  NSButton* button = _escapeButton;
  if (button.enabled && !self.composing) [button performClick:self];
}
- (BOOL)performKeyEquivalent:(NSEvent*)event {
  if (event.type != NSEventTypeKeyDown) return [super performKeyEquivalent:event];
  if (self.composing) return NO;
  const BOOL plain = !(event.modifierFlags &
                       (NSEventModifierFlagCommand | NSEventModifierFlagControl |
                        NSEventModifierFlagOption | NSEventModifierFlagShift));
  NSButton* enter = _enterButton;
  if (plain && enter &&
      (event.keyCode == 76 || [event.charactersIgnoringModifiers isEqualToString:@"\003"])) {
    if (enter.enabled) [enter performClick:self];
    return YES;
  }
  return [super performKeyEquivalent:event];
}
@end

@implementation PCDialogPrompt {
  NSString* _title;
  NSString* _message;
  NSMutableArray<NSButton*>* _buttons;
  PCDialogPanel* _window;
}
@synthesize icon = _icon;
@synthesize escapeButton = _escapeButton;
- (instancetype)initWithTitle:(NSString*)title message:(NSString*)message {
  if ((self = [super init])) {
    _title = [title copy];
    _message = [message copy];
    _buttons = [NSMutableArray array];
  }
  return self;
}
- (NSButton*)addButtonWithTitle:(NSString*)title
                           role:(PCDialogPromptRole)role
                       response:(NSModalResponse)response {
  NSAssert(!_window, @"Add buttons before laying out the prompt");
  const BOOL primary = role == PCDialogPromptPrimary || role == PCDialogPromptDestructive;
  PCDialogButton* button = [[PCDialogButton alloc] initWithTitle:title
                                                         primary:primary
                                                     destructive:role == PCDialogPromptDestructive];
  button.tag = response;
  button.target = self;
  button.action = @selector(respond:);
  if (primary) {
    button.keyEquivalent = @"\r";
  } else if (role == PCDialogPromptCancel) {
    button.keyEquivalent = @"\033";
    if (!_escapeButton) _escapeButton = button;
  } else {
    button.showsHint = NO;
  }
  button.keyEquivalentModifierMask = 0;
  [_buttons addObject:button];
  return button;
}
- (void)respond:(NSButton*)sender {
  __attribute__((objc_precise_lifetime)) PCDialogPrompt* keep = self;
  (void)keep;
  NSWindow* window = _window;
  if (sender.window == window && window.sheetParent) {
    [window.sheetParent endSheet:window returnCode:sender.tag];
  }
}
- (NSWindow*)window {
  if (_window) return _window;
  PCDialogPanel* panel = [[PCDialogPanel alloc] initWithContentRect:NSMakeRect(0, 0, kWidth, 200)
                                                          styleMask:NSWindowStyleMaskTitled
                                                            backing:NSBackingStoreBuffered
                                                              defer:YES];
  panel.releasedWhenClosed = NO;
  panel.becomesKeyOnlyIfNeeded = NO;
  panel.title = _title;
  panel.accessibilityLabel = _title;
  PrepareSheet(panel);
  PCDialogBaseView* root = [[PCDialogBaseView alloc] initWithFrame:NSZeroRect];
  CGFloat y = kInset;
  NSView* art;
  if (_icon) {
    NSImageView* image = [NSImageView imageViewWithImage:_icon];
    image.imageScaling = NSImageScaleProportionallyUpOrDown;
    image.frame = NSMakeRect(0, 0, kArtSize, kArtSize);
    art = image;
  } else {
    NSRect markRect;
    NSImage* mark = ParcMark(&markRect);
    art = [[PCDialogPictureIcon alloc] initWithImage:mark imageRect:markRect];
  }
  [art setAccessibilityElement:NO];
  art.frameOrigin = NSMakePoint(kInset, y);
  [root addSubview:art];
  y = AddHeading(root, _title, _message, y + kArtSize, 240, true) + 22;
  // Footer order, right to left: the Return button, Cancel, then auxiliaries.
  NSMutableArray<NSButton*>* ordered = [NSMutableArray array];
  for (NSButton* button in _buttons) {
    if ([button.keyEquivalent isEqualToString:@"\r"]) [ordered addObject:button];
  }
  for (NSButton* button in _buttons) {
    if ([button.keyEquivalent isEqualToString:@"\033"]) [ordered addObject:button];
  }
  for (NSButton* button in _buttons) {
    if (!button.keyEquivalent.length) [ordered addObject:button];
  }
  y = PlaceFooter(root, y, nil, ordered);
  root.frame = NSMakeRect(0, 0, kWidth, y);
  panel.contentView = root;
  [panel setContentSize:NSMakeSize(kWidth, y)];
  NSButton* enter = nil;
  for (NSButton* button in _buttons) {
    if ([button.keyEquivalent isEqualToString:@"\r"]) {
      enter = button;
      break;
    }
  }
  panel.enterButton = enter;
  panel.escapeButton = _escapeButton;
  if (enter) [panel setAccessibilityDefaultButton:enter];
  _window = panel;
  return panel;
}
- (void)setEscapeButton:(NSButton*)button {
  _escapeButton = button;
  _window.escapeButton = button;
}
- (void)beginSheetModalForWindow:(NSWindow*)parent
               completionHandler:(void (^)(NSModalResponse))handler {
  NSWindow* window = self.window;
  void (^completion)(NSModalResponse) = [handler copy];
  // The completion retains this prompt (and its button targets) until the
  // sheet ends.
  [parent beginSheet:window
      completionHandler:^(NSModalResponse response) {
        (void)self;
        if (completion) completion(response);
      }];
}
@end
