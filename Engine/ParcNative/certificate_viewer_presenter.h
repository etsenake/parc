// Copyright 2026 Parc contributors.
#pragma once
#import <AppKit/AppKit.h>

#import "dialog_style.h"

NS_ASSUME_NONNULL_BEGIN
@class SFCertificatePanel;
@protocol PCCertificatePresentation <PCNativePresentation>
- (void)beginSheetForPanel:(SFCertificatePanel*)panel
                    window:(NSWindow*)window
             modalDelegate:(id)delegate
            didEndSelector:(SEL)didEndSelector
               contextInfo:(nullable void*)contextInfo
              certificates:(NSArray*)certificates
                 showGroup:(BOOL)showGroup;
@end
// Real SecurityInterface certificate details, not a certificate trust decision.
// The owner retains this object; invalidate is terminal and idempotent. The
// presenter additionally retains itself until the OS sheet's didEnd callback.
@interface PCServerCertificatePresenter : NSObject
- (instancetype)initWithPage:(NSView*)page
                      window:(NSWindow*)window
                certificates:(NSArray*)certificates
                    validate:(BOOL (^)(void))validate
                    finished:(void (^)(void))finished;
@property(nonatomic, readonly, nullable) NSWindow* panel;
@property(nonatomic, strong) id<PCCertificatePresentation> presentation;
@property(nonatomic, strong) id<PCNativeScheduling> scheduler;
- (void)show;
- (void)invalidate;
@end
NS_ASSUME_NONNULL_END
