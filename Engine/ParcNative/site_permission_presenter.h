// Parc-owned presentation for one engine-owned site permission request.
#pragma once
#import <AppKit/AppKit.h>
NS_ASSUME_NONNULL_BEGIN
typedef NS_ENUM(NSInteger, PCSitePermissionChoice) {
  PCSitePermissionAllow,
  PCSitePermissionAllowOnce,
  PCSitePermissionBlock,
  PCSitePermissionDismiss,
  PCSitePermissionInterrupted,
  // Nonterminal actions: the exact request owner retains the native prompt.
  PCSitePermissionOpenSystemSettings,
  PCSitePermissionRequestSystem,
};
typedef NS_ENUM(NSInteger, PCSiteLocationMode) {
  PCSiteLocationNone,
  PCSiteLocationApproximate,
  PCSiteLocationApproximateOrPrecise,
  PCSiteLocationUpgradeToPrecise,
};
// Optional native anchor, answered by the window's controller: a dictionary
// with "view" (NSView), "rect" (NSValue rect in that view) and "edge"
// (NSNumber NSRectEdge). Without one the prompt anchors to the requesting
// page's top leading corner.
@protocol PCSitePermissionAnchorProviding <NSObject>
- (nullable NSDictionary*)parcSitePermissionAnchorForPage:(NSView*)page;
@end
//
// shown from the address bar's site controls; docs/web-interactions.md): a
//
// buttons, Not Now (dismiss) and Allow. Location accuracy follows the engine's
//
@interface PCSitePermissionPresenter : NSObject
- (instancetype)initWithPage:(NSView*)page
                      window:(NSWindow*)window
                       title:(NSString*)title
                locationMode:(PCSiteLocationMode)locationMode
              initialPrecise:(BOOL)initialPrecise
                    validate:(BOOL (^)(void))validate
                   presented:(void (^)(void))presented
                      result:(void (^)(PCSitePermissionChoice,
                                       BOOL precise))result;
//
- (void)configureSymbol:(NSString*)name
              pointSize:(CGFloat)pointSize
                   bold:(BOOL)bold
                offsetY:(CGFloat)offsetY;
// Configure a real permission-element stage before start. Labels and choices
// come from the Chromium flow model; system actions do not dismiss the prompt.
- (void)configureFollowUpWithTitle:(NSString*)title
                           labels:(NSArray<NSString*>*)labels
                          choices:(NSArray<NSNumber*>*)choices
                     systemAction:(void (^)(PCSitePermissionChoice))action;
- (void)setSystemRequestPending:(BOOL)pending;
// Both presentation and completion are deferred. A queued decision is checked
// again against the exact page/window before delivery. Escape or closing the
// transient popover is dismissal; only an explicit Stop allowing blocks.
- (void)start;
- (void)invalidate;
// The popover's window while it is shown.
@property(nonatomic, readonly, nullable) NSWindow* sheet;
// YES while the popover is shown from this request's window.
@property(nonatomic, readonly, getter=isShown) BOOL shown;
@end
NS_ASSUME_NONNULL_END
