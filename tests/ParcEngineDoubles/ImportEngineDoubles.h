#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

NSObject *ImportTestSource(NSString *identifier, NSURL *appURL) NS_SWIFT_NAME(ImportTestSource(identifier:appURL:));
NSObject *ImportTestExtension(NSString *identifier, NSString *displayName)
    NS_SWIFT_NAME(ImportTestExtension(identifier:displayName:));
NSObject *ImportTestProfile(NSString *identifier, NSString *displayName, NSString *directoryName,
                            NSUInteger categories, NSInteger access, NSArray *extensions)
    NS_SWIFT_NAME(ImportTestProfile(identifier:displayName:directoryName:categories:access:extensions:));
NSObject *ImportTestProfileResult(NSArray *profiles, NSInteger access, NSArray<NSString *> *constraints,
                                  NSError *_Nullable error)
    NS_SWIFT_NAME(ImportTestProfileResult(profiles:access:constraints:error:));
NSObject *ImportTestBookmark(NSString *identifier, NSString *title, NSURL *_Nullable url, NSArray *children)
    NS_SWIFT_NAME(ImportTestBookmark(identifier:title:url:children:));
NSObject *ImportTestEvent(NSString *_Nullable message, NSUInteger category, NSInteger phase)
    NS_SWIFT_NAME(ImportTestEvent(message:category:phase:));
NSObject *ImportTestResult(NSInteger outcome, NSArray *bookmarks, NSArray<NSString *> *warnings, NSError *_Nullable error)
    NS_SWIFT_NAME(ImportTestResult(outcome:bookmarks:warnings:error:));
NSObject *ImportTestDiscovery(void) NS_SWIFT_NAME(ImportTestDiscovery());
NSObject *ImportTestSession(void) NS_SWIFT_NAME(ImportTestSession());
BOOL ImportTestCancelled(NSObject *lease) NS_SWIFT_NAME(ImportTestCancelled(_:));
NSObject *ImportTestExtensionResult(NSInteger outcome, NSSet<NSString *> *installed, NSSet<NSString *> *installing)
    NS_SWIFT_NAME(ImportTestExtensionResult(outcome:installed:installing:));
NSObject *ImportTestExtensionFailure(NSString *name, NSString *_Nullable identifier, NSString *_Nullable profilePath,
                                     NSInteger restriction)
    NS_SWIFT_NAME(ImportTestExtensionFailure(name:identifier:profilePath:restriction:));
NSObject *ImportTestRequestSource(NSObject *request) NS_SWIFT_NAME(ImportTestRequestSource(_:));
NSString *ImportTestRequestPath(NSObject *request) NS_SWIFT_NAME(ImportTestRequestPath(_:));
NSSet<NSString *> *ImportTestRequestIdentifiers(NSObject *request) NS_SWIFT_NAME(ImportTestRequestIdentifiers(_:));
NSObject *ImportTestPasswordResult(NSInteger outcome, NSUInteger imported, NSUInteger existing, NSUInteger invalid,
                                   BOOL canRemove, NSError *_Nullable error)
    NS_SWIFT_NAME(ImportTestPasswordResult(outcome:imported:existing:invalid:canRemove:error:));
NSObject *ImportTestPasswordSession(void) NS_SWIFT_NAME(ImportTestPasswordSession());
NSUInteger ImportTestRemovalCount(NSObject *session) NS_SWIFT_NAME(ImportTestRemovalCount(_:));
void ImportTestCompleteRemoval(NSObject *session, NSUInteger index, NSError *_Nullable error)
    NS_SWIFT_NAME(ImportTestCompleteRemoval(_:at:error:));

NS_ASSUME_NONNULL_END
