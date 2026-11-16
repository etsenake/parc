// Copyright 2026 Parc contributors.
#ifndef PARC_NATIVE_NATIVE_BLOCKED_POPUPS_H_
#define PARC_NATIVE_NATIVE_BLOCKED_POPUPS_H_

#import <Foundation/Foundation.h>

#import "native_appkit_bridge.h"

#define PCNativePageBlockedContentDidChangeNotification \
  @"PCNativePageBlockedContentDidChange"

NS_ASSUME_NONNULL_BEGIN

NS_SWIFT_UI_ACTOR
@interface PCNativePage (BlockedContent)
@property(nonatomic, readonly, nullable, copy)
    NSDictionary<NSString*, id>* blockedContent;
- (BOOL)openBlockedContentItem:(NSString*)kind
                    identifier:(NSInteger)identifier
                      revision:(NSUInteger)revision
    NS_SWIFT_NAME(openBlockedContentItem(kind:identifier:revision:));
- (BOOL)openAllBlockedPopupsWithRevision:(NSUInteger)revision
    NS_SWIFT_NAME(openAllBlockedPopups(revision:));
- (BOOL)allowBlockedPopupsWithRevision:(NSUInteger)revision
    NS_SWIFT_NAME(allowBlockedPopups(revision:));
@end

NS_ASSUME_NONNULL_END

#ifdef __cplusplus
namespace parc {
void InstallNativeBlockedPopups();
}
#endif

#endif
