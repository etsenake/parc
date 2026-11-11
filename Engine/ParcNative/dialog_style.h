// Parc's native dialog look, shared by the engine's own sheets: the extension
// install and remove sheets and the page's JavaScript dialogs. The app's
//
#pragma once
#import <AppKit/AppKit.h>
NS_ASSUME_NONNULL_BEGIN
namespace parc_dialog {
inline constexpr CGFloat kWidth = 450;
inline constexpr CGFloat kInset = 38;
inline constexpr CGFloat kArtSize = 62;
//
NSColor* PopoverBackground();
NSColor* PopoverTitle();
NSColor* PopoverMessage();
NSColor* PopoverArrowIcon();
NSColor* SelectionColor();
NSBezierPath* ContinuousRect(NSRect rect, CGFloat radius);
NSTextField* Label(NSString* text, NSFont* font, NSColor* color, CGFloat lineSpacing);
// Places the label's text, not its inset cell, at (x, y, width) like SwiftUI Text.
CGFloat PlaceLabel(NSTextField* label, CGFloat x, CGFloat y, CGFloat width);
NSFont* TitleFont();
NSFont* BodyFont();
// A transparent full-size titlebar; the content view paints the background.
void PrepareSheet(NSWindow* sheet);
// Parc's Borderless mark and its rect inside a 62-point tile.
NSImage* ParcMark(NSRect* imageRect);
// A 62-point extension image, aspect-fitted, or the puzzle-piece fallback.
NSImageView* ExtensionArt(NSImage* _Nullable icon);
// Adds the title, then the message (scrolling past maxMessageHeight), at y and
// returns the y below them.
CGFloat AddHeading(NSView* root, NSString* title, NSString* _Nullable message,
                   CGFloat y, CGFloat maxMessageHeight);
//
// the sides and bottom. Returns the dialog height.
CGFloat PlaceFooter(NSView* root, CGFloat y, NSButton* _Nullable checkbox,
                    NSArray<NSButton*>* buttons);
}  // namespace parc_dialog

@interface PCDialogFlippedView : NSView
@end
// Fills PopoverBackground itself: an attached sheet's frame view puts the
// system sheet material over the window background color.
@interface PCDialogBaseView : PCDialogFlippedView
@end
//
@interface PCDialogPictureIcon : NSView
- (instancetype)initWithImage:(NSImage*)image imageRect:(NSRect)imageRect;
@end
// Dialogs.DialogButtonStyleView with its label and ESC or return key badge.
@interface PCDialogButton : NSButton
- (instancetype)initWithTitle:(NSString*)title primary:(BOOL)primary;
- (instancetype)initWithTitle:(NSString*)title
                      primary:(BOOL)primary
                  destructive:(BOOL)destructive;
@property(nonatomic, readonly) CGFloat bodyWidth;
// NO for an auxiliary button without a key, such as "Never on this site".
@property(nonatomic) BOOL showsHint;
// The key event whose key equivalent is dispatching the action, if any.
@property(nonatomic, readonly, nullable) NSEvent* keyEvent;
@end
// Parc's onboarding selection mark as a checkbox: `circle` / filled checkmark
// circle at large scale in the selection color, 8 points, then a 14-point label.
@interface PCDialogCheckbox : NSButton
- (instancetype)initWithTitle:(NSString*)title target:(nullable id)target action:(nullable SEL)action;
- (NSSize)sizeForWidth:(CGFloat)width;
@end
// A rounded single-line input whose border takes the selection color while
// it is being edited, instead of the system focus ring.
@interface PCDialogInputField : PCDialogFlippedView
- (instancetype)initWithText:(NSString*)text;
@property(nonatomic, readonly) NSTextField* field;
@end
NS_ASSUME_NONNULL_END
