// Copyright 2026 Parc contributors.
#import "native_application_protocols.h"

#include "base/observer_list.h"
#include "content/public/browser/native_event_processor_mac.h"
#include "content/public/browser/native_event_processor_observer_mac.h"

@interface PCNativeApplication () <NativeEventProcessor>
@end

@implementation PCNativeApplication {
  base::ObserverList<content::NativeEventProcessorObserver>::Unchecked observers_;
}
- (void)addNativeEventProcessorObserver:
    (content::NativeEventProcessorObserver*)observer {
  observers_.AddObserver(observer);
}
- (void)removeNativeEventProcessorObserver:
    (content::NativeEventProcessorObserver*)observer {
  observers_.RemoveObserver(observer);
}
- (void)sendEvent:(NSEvent*)event {
  content::ScopedNotifyNativeEventProcessorObserver notify(&observers_, event);
  [super sendEvent:event];
}
@end
