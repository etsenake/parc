// Source-owned AppKit Find presentation. Chromium search lives in find_bar.mm.
#pragma once
#import <AppKit/AppKit.h>
#import "focus_manager.h"

NS_ASSUME_NONNULL_BEGIN
@class PCNativeFindView;
typedef NS_ENUM(NSInteger, PCNativeFindAction) {
  PCNativeFindQueryChanged,
  PCNativeFindNext,
  PCNativeFindPrevious,
  PCNativeFindClose,
};
@protocol PCNativeFindViewDelegate <NSObject>
- (void)findView:(PCNativeFindView *)view
        perform:(PCNativeFindAction)action
           text:(NSString *)text;
- (void)findView:(PCNativeFindView *)view didChangeFocus:(BOOL)focused;
@end

// Main-thread-only. Borrowed page container/window/focus manager; no page or
// Browser ownership. The owner must invalidate before disposing its services.
@interface PCNativeFindView : NSView <NSTextFieldDelegate>
@property(nonatomic, weak, nullable) id<PCNativeFindViewDelegate> delegate;
@property(nonatomic, readonly) NSTextField *textField;
@property(nonatomic, copy) NSString *text;
@property(nonatomic) NSRange selectedRange;
@property(nonatomic, readonly) NSString *matchCountText;
@property(nonatomic, readonly, getter=isPresented) BOOL presented;
@property(nonatomic, readonly, getter=isInvalidated) BOOL invalidated;
@property(nonatomic, readonly) BOOL hasFindFocus;
@property(nonatomic, readonly) BOOL hasMarkedText;

//
// priority250, height32. topInset is10 plus any real upper page panel height.
// Returning NO leaves no stale presentation on the previous page.
- (BOOL)attachToContainer:(nullable NSView *)container
                topInset:(CGFloat)topInset
            focusManager:(nullable PCNativeFocusManager *)manager
                focusKey:(nullable NSString *)focusKey
            pageFocusKey:(nullable NSString *)pageFocusKey;
- (void)presentTakingFocus:(BOOL)focus;
- (void)focusAndSelectAll;
- (void)dismiss;
- (void)restoreSavedFocus;
// Negative values mean not yet known, never a fabricated zero-result state.
- (void)setMatchCount:(NSInteger)count ordinal:(NSInteger)ordinal;
- (void)invalidate;
@end
NS_ASSUME_NONNULL_END
