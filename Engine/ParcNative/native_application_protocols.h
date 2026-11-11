// Copyright 2026 Parc contributors.
// Chromium's NSApplication event-control protocols for the Swift application,
// which cannot import base/. The Objective-C runtime matches protocols by name,
// so these satisfy base/message_loop/message_pump_apple.h and
// base/mac/scoped_sending_event.h. Keep the selectors identical to those.
#ifndef PARC_NATIVE_APPLICATION_PROTOCOLS_H_
#define PARC_NATIVE_APPLICATION_PROTOCOLS_H_

#import <Foundation/Foundation.h>

@protocol CrAppProtocol
- (BOOL)isHandlingSendEvent;
@end

@protocol CrAppControlProtocol <CrAppProtocol>
- (void)setHandlingSendEvent:(BOOL)handlingSendEvent;
@end

#endif  // PARC_NATIVE_APPLICATION_PROTOCOLS_H_
