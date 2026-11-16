// Copyright 2026 Parc contributors.
#import "native_blocked_popups.h"

#include "base/strings/sys_string_conversions.h"
#include "content/public/browser/web_contents.h"
#include "native_appkit_page.h"
#include "native_page_info.h"
#include "native_page_retirement.h"
#include "native_popup_blocking.h"

namespace parc {
namespace {

void PublishBlockedContent(content::WebContents& contents) {
  PCNativePage* page = ExistingNativePage(&contents);
  if (!page || page.closed) {
    return;
  }
  [NSNotificationCenter.defaultCenter
      postNotificationName:PCNativePageBlockedContentDidChangeNotification
                    object:page];
}

content::WebContents* BlockedContentContents(PCNativePage* page) {
  content::WebContents* contents = ContentsForNativePage(page);
  if (!contents || page.closed || contents->IsBeingDestroyed() ||
      IsNativePageRetiring(page)) {
    return nullptr;
  }
  return contents;
}

}

void InstallNativeBlockedPopups() {
  InstallNativePopupBlocking(&PublishBlockedContent);
}

}

@implementation PCNativePage (BlockedContent)

- (NSDictionary<NSString*, id>*)blockedContent {
  content::WebContents* contents = parc::BlockedContentContents(self);
  if (!contents) {
    return nil;
  }
  std::optional<parc::NativeBlockedContent> snapshot =
      parc::GetNativeBlockedContent(*contents);
  if (!snapshot) {
    return nil;
  }
  NSMutableArray<NSDictionary<NSString*, id>*>* items = [NSMutableArray array];
  for (const parc::NativeBlockedItem& item : snapshot->items) {
    [items addObject:@{
      @"kind" : item.kind == parc::NativeBlockedItem::Kind::kPopup
          ? @"popup"
          : @"redirect",
      @"identifier" : @(static_cast<NSInteger>(item.id)),
      @"url" : base::SysUTF8ToNSString(item.url.spec()),
    }];
  }
  return @{
    @"revision" : @(static_cast<NSUInteger>(snapshot->revision)),
    @"items" : items,
    @"site" : base::SysUTF8ToNSString(snapshot->site.spec()),
    @"allowed" : @(snapshot->allowed),
    @"canAllow" : @(snapshot->can_allow),
  };
}

- (BOOL)openBlockedContentItem:(NSString*)kind
                    identifier:(NSInteger)identifier
                      revision:(NSUInteger)revision {
  content::WebContents* contents = parc::BlockedContentContents(self);
  const bool popup = [kind isEqualToString:@"popup"];
  if (!contents || (!popup && ![kind isEqualToString:@"redirect"]) ||
      identifier < 0 || identifier > INT32_MAX) {
    return NO;
  }
  return parc::OpenNativeBlockedItem(
      *contents,
      popup ? parc::NativeBlockedItem::Kind::kPopup
            : parc::NativeBlockedItem::Kind::kRedirect,
      static_cast<int32_t>(identifier), revision);
}

- (BOOL)openAllBlockedPopupsWithRevision:(NSUInteger)revision {
  content::WebContents* contents = parc::BlockedContentContents(self);
  return contents && parc::OpenAllNativeBlockedPopups(*contents, revision);
}

- (BOOL)allowBlockedPopupsWithRevision:(NSUInteger)revision {
  content::WebContents* contents = parc::BlockedContentContents(self);
  if (!contents || !parc::AllowNativeBlockedPopups(*contents, revision)) {
    return NO;
  }
  if (content::WebContents* current = parc::BlockedContentContents(self)) {
    parc::RefreshNativeSiteControls(current);
  }
  return YES;
}

@end
