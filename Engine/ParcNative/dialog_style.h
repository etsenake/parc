#pragma once
#import <AppKit/AppKit.h>

#import "page_host.h"

NS_ASSUME_NONNULL_BEGIN
namespace parc_dialog {
inline constexpr CGFloat kWidth = 450;
inline constexpr CGFloat kInset = 38;
inline constexpr CGFloat kArtSize = 62;
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
// returns the y below them. A selectable message can be copied.
CGFloat AddHeading(NSView* root, NSString* title, NSString* _Nullable message,
                   CGFloat y, CGFloat maxMessageHeight, bool selectableMessage = false);
CGFloat PlaceFooter(NSView* root, CGFloat y, NSButton* _Nullable checkbox,
                    NSArray<NSButton*>* buttons);
}  // namespace parc_dialog

@interface PCNativeSystemPresentation : NSObject <PCNativePresentation>
@property(class, nonatomic, readonly) PCNativeSystemPresentation* sharedPresentation;
@end

@interface PCNativeSystemScheduling : NSObject <PCNativeScheduling>
@property(class, nonatomic, readonly) PCNativeSystemScheduling* sharedScheduling;
@end

@interface PCDialogFlippedView : NSView
@end
// Fills PopoverBackground itself: an attached sheet's frame view puts the
// system sheet material over the window background color.
@interface PCDialogBaseView : PCDialogFlippedView
@end
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
// Caps bodyWidth; a longer title is truncated. 0 means no cap.
@property(nonatomic) CGFloat maximumWidth;
// NO for an auxiliary button without a key, such as "Never on this site".
@property(nonatomic) BOOL showsHint;
// The key event whose key equivalent is dispatching the action, if any.
@property(nonatomic, readonly, nullable) NSEvent* keyEvent;
@end
// Parc's onboarding selection mark as a checkbox, matching the app's
// ParcSelectionCheckbox: `circle` / `checkmark.circle.fill` at large scale in
// the selection color beside a 14-point label.
@interface PCDialogCheckbox : NSButton
- (instancetype)initWithTitle:(NSString*)title target:(nullable id)target action:(nullable SEL)action;
- (NSSize)sizeForWidth:(CGFloat)width;
@end
@interface PCDialogCard : PCDialogFlippedView
@property(nonatomic, weak, nullable) NSView* field;
@end
// A single-line input on a tinted rounded card, 36 points tall with 12-point
// padding and no focus ring, matching the app's dialog field.
@interface PCDialogInputField : PCDialogFlippedView
- (instancetype)initWithText:(NSString*)text;
// secure uses an NSSecureTextField with AppKit's secure input behaviour.
- (instancetype)initWithText:(NSString*)text secure:(BOOL)secure;
@property(nonatomic, readonly) NSTextField* field;
@end
// A dialog sheet whose keypad Enter (U+0003, which misses a Return key
// equivalent) clicks enterButton and whose Escape clicks escapeButton. While
// an input method is composing in a field, Return and Escape stay with it.
@interface PCDialogPanel : NSPanel
@property(nonatomic, weak, nullable) NSButton* enterButton;
@property(nonatomic, weak, nullable) NSButton* escapeButton;
@end

typedef NS_ENUM(NSInteger, PCDialogPromptRole) {
  PCDialogPromptPrimary,      // Return, rightmost
  PCDialogPromptDestructive,  // Return, red
  PCDialogPromptCancel,       // Escape
  PCDialogPromptAuxiliary,    // no key, leftmost
};
// A simple decision in Parc's dialog, shaped like NSAlert's sheet API: Parc's
// mark (or icon), title, message and buttons. A button ends the sheet with its
// response; the prompt stays alive until the sheet ends.
@interface PCDialogPrompt : NSObject
- (instancetype)initWithTitle:(NSString*)title message:(nullable NSString*)message;
@property(nonatomic, strong, nullable) NSImage* icon;
- (NSButton*)addButtonWithTitle:(NSString*)title
                           role:(PCDialogPromptRole)role
                       response:(NSModalResponse)response;
// Escape answers this button; it defaults to the Cancel-role button.
@property(nonatomic, weak, nullable) NSButton* escapeButton;
// Laid out on first access; add buttons before.
@property(nonatomic, readonly) NSWindow* window;
@property(nonatomic, strong) id<PCNativePresentation> presentation;
- (void)beginSheetModalForWindow:(NSWindow*)parent
               completionHandler:(nullable void (^)(NSModalResponse))handler;
@end
NS_ASSUME_NONNULL_END
