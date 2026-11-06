// Copyright 2026 Parc contributors.
#pragma once
#import <AppKit/AppKit.h>
NS_ASSUME_NONNULL_BEGIN
//
//
// destination application's icon, the title as message text and buttons in
//
// (Escape). An empty remember label omits that button.
@interface PCExternalProtocolPresenter : NSObject
- (instancetype)initWithPage:(NSView*)page
                      window:(NSWindow*)window
                       title:(NSString*)title
                     message:(NSString*)message
                        icon:(nullable NSImage*)icon
                 acceptLabel:(NSString*)acceptLabel
                 cancelLabel:(NSString*)cancelLabel
               rememberLabel:(NSString*)rememberLabel
                    validate:(BOOL (^)(void))validate
                inputAllowed:(BOOL (^)(NSEvent* _Nullable))inputAllowed
                stateChanged:(void (^)(void))stateChanged
                      result:(void (^)(BOOL accepted, BOOL remember))result;
@property(nonatomic, readonly) NSWindow* sheet;
- (void)show;
- (void)focus;
- (void)invalidate;
@end
NS_ASSUME_NONNULL_END
