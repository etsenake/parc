// Native sheet for the real Chromium uninstall DialogModel. Presentation only.
#pragma once
#import <AppKit/AppKit.h>
NS_ASSUME_NONNULL_BEGIN
typedef NS_ENUM(NSInteger, PCUninstallChoice) {
  PCUninstallAccept,
  PCUninstallCancel,
  PCUninstallInterrupted,
};
@interface PCNativeUninstallPresenter : NSObject
- (instancetype)initWithWindow:(NSWindow*)window
                         title:(NSString*)title
                       message:(NSString*)message
                          icon:(nullable NSImage*)icon
                   acceptLabel:(NSString*)acceptLabel
                   cancelLabel:(NSString*)cancelLabel
                 checkboxLabel:(nullable NSString*)checkboxLabel
                       checked:(BOOL)checked
                      validate:(BOOL (^)(void))validate
                       changed:(void (^)(BOOL))changed
                        result:(void (^)(PCUninstallChoice))result;
- (void)start;
- (void)invalidate;
- (void)setAcceptEnabled:(BOOL)enabled cancelEnabled:(BOOL)cancelEnabled;
@property(nonatomic, readonly, nullable) NSWindow* sheet;
@property(nonatomic, readonly, getter=isPresenting) BOOL presenting;
@end
NS_ASSUME_NONNULL_END
