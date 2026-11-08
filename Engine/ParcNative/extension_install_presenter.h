// Native presentation for an engine-owned extension consent request.
#pragma once
#import <AppKit/AppKit.h>
NS_ASSUME_NONNULL_BEGIN
typedef NS_ENUM(NSInteger, PCExtensionInstallChoice) {
  PCExtensionInstallAccept,
  PCExtensionInstallCancel,
  PCExtensionInstallInterrupted,
};
@interface PCExtensionInstallPresenter : NSObject
- (instancetype)initWithWindow:(NSWindow*)window
                         title:(NSString*)title
                          icon:(nullable NSImage*)icon
                       heading:(NSString*)heading
                   permissions:(NSArray<NSString*>*)permissions
                       details:(NSArray<NSString*>*)details
                   acceptLabel:(NSString*)acceptLabel
                   cancelLabel:(NSString*)cancelLabel
                 checkboxLabel:(nullable NSString*)checkboxLabel
                      validate:(BOOL (^)(void))validate
                  inputAllowed:(BOOL (^)(NSWindow* sheet))inputAllowed
                        result:(void (^)(PCExtensionInstallChoice,
                                         BOOL grantPermissions))result;
// A parent submission retains the sheet while the genuine reauth runs.
- (void)configureParentAccounts:(NSArray<NSString*>*)accounts
                   instructions:(NSArray<NSString*>*)instructions
                  passwordLabel:(NSString*)label
                         submit:(void (^)(NSInteger, NSString*))submit;
- (void)setParentApprovalPending:(BOOL)pending error:(NSString*)error;
// Ordinary installation education uses the real extension name/icon/permissions.
// Special policy, parent, repair and permission requests retain their own copy.
- (void)configureInstallationEducationWithName:(NSString*)name;
- (void)start;
- (void)invalidate;
// Enterprise requests use the same consent owner, but return a justification
// to Chromium's request controller instead of authorizing installation.
// Configure before start. An empty accept label presents only Close/Cancel.
- (void)configureJustificationLabel:(NSString*)label
                       placeholder:(NSString*)placeholder
                       counterText:(NSString* (^)(NSUInteger length))counter;
@property(nonatomic, readonly, copy) NSString* justification;
@property(nonatomic, readonly, nullable) NSWindow* sheet;
@end
NS_ASSUME_NONNULL_END
