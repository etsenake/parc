// Copyright 2026 Parc contributors.
#pragma once
#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN
typedef NS_ENUM(NSInteger, PCHTTPAuthChoice) {
  PCHTTPAuthAccept,
  PCHTTPAuthCancel,
  PCHTTPAuthInterrupted,
};
// Only presentation. Authority and the transport warning come from Chromium's
// LoginHandler; this object never stores credentials outside the live request.
@interface PCHTTPAuthPresenter : NSObject
- (instancetype)initWithPage:(NSView*)page
                      window:(NSWindow*)window
                   authority:(NSString*)authority
                 explanation:(NSString*)explanation
                       proxy:(BOOL)proxy
                    validate:(BOOL (^)(void))validate
                      result:(void (^)(PCHTTPAuthChoice, NSString*, NSString*))
                                 result;
// The window exists before presentation for the real web-modal manager.
@property(nonatomic, readonly) NSWindow* sheet;
- (void)show;
- (void)focus;
- (void)autofillUsername:(NSString*)username password:(NSString*)password;
- (void)invalidate;
@end
NS_ASSUME_NONNULL_END
