#import "ImportEngineDoubles.h"
#import "ParcEngine.h"
#import <objc/runtime.h>

NS_ASSUME_NONNULL_BEGIN
@interface PCImportedExtensionFailure (ImportDoubles)
- (instancetype)initWithName:(NSString *)name
                  identifier:(nullable NSString *)identifier
                 profilePath:(nullable NSString *)profilePath
                 restriction:(PCNativeExtensionRestriction)restriction;
@end
NS_ASSUME_NONNULL_END

#define IMPORT_DOUBLE(type) ((type *)[(NSObject *)[type alloc] init])

@interface ImportTestSourceDouble : PCNativeImportSource
@property(nonatomic, copy) NSString *fixtureIdentifier;
@property(nonatomic, copy) NSURL *fixtureURL;
@end

@implementation ImportTestSourceDouble
- (NSString *)identifier { return self.fixtureIdentifier; }
- (NSString *)displayName { return self.fixtureIdentifier; }
- (NSURL *)appURL { return self.fixtureURL; }
@end

@interface ImportTestExtensionDouble : PCNativeImportExtension
@property(nonatomic, copy) NSString *fixtureIdentifier;
@property(nonatomic, copy) NSString *fixtureName;
@end

@implementation ImportTestExtensionDouble
- (NSString *)identifier { return self.fixtureIdentifier; }
- (NSString *)displayName { return self.fixtureName; }
@end

@interface ImportTestProfileDouble : PCNativeImportProfile
@property(nonatomic, copy) NSString *fixtureIdentifier;
@property(nonatomic, copy) NSString *fixtureName;
@property(nonatomic, copy) NSString *fixtureDirectory;
@property(nonatomic) PCNativeImportCategories fixtureCategories;
@property(nonatomic) PCNativeImportAccess fixtureAccess;
@property(nonatomic, copy) NSArray<PCNativeImportExtension *> *fixtureExtensions;
@property(atomic) BOOL fixtureDecryptable;
@property(atomic, copy, nullable) NSData *fixtureDecrypted;
@property(atomic, strong, nullable) NSError *fixtureDecryptionError;
@property(atomic, strong) NSMutableArray<NSString *> *fixtureDecryptionRequests;
@end

@implementation ImportTestProfileDouble
- (NSString *)identifier { return self.fixtureIdentifier; }
- (NSString *)displayName { return self.fixtureName; }
- (NSString *)directoryName { return self.fixtureDirectory; }
- (PCNativeImportCategories)supportedCategories { return self.fixtureCategories; }
- (PCNativeImportAccess)access { return self.fixtureAccess; }
- (NSArray<PCNativeImportExtension *> *)extensions { return self.fixtureExtensions; }
- (NSArray<NSString *> *)constraints { return @[]; }
- (BOOL)canDecryptSidebarFiles { return self.fixtureDecryptable; }
- (NSData *)decryptSidebarFile:(NSURL *)file format:(PCNativeImportSidebarFormat)format error:(NSError **)error {
    @synchronized(self) {
        [self.fixtureDecryptionRequests addObject:[NSString stringWithFormat:@"%ld %@", (long)format, file.path]];
    }
    NSData *data = self.fixtureDecrypted;
    if (!data && error) {
        *error = self.fixtureDecryptionError
                     ?: [NSError errorWithDomain:@"ImportEngineDoubles" code:1 userInfo:nil];
    }
    return data;
}
@end

@interface ImportTestProfileResultDouble : PCNativeImportProfileResult
@property(nonatomic, copy) NSArray<PCNativeImportProfile *> *fixtureProfiles;
@property(nonatomic) PCNativeImportAccess fixtureAccess;
@property(nonatomic, copy) NSArray<NSString *> *fixtureConstraints;
@property(nonatomic, strong, nullable) NSError *fixtureError;
@end

@implementation ImportTestProfileResultDouble
- (NSArray<PCNativeImportProfile *> *)profiles { return self.fixtureProfiles; }
- (PCNativeImportAccess)access { return self.fixtureAccess; }
- (NSArray<NSString *> *)constraints { return self.fixtureConstraints; }
- (NSError *)error { return self.fixtureError; }
@end

@interface ImportTestBookmarkDouble : PCNativeImportedBookmark
@property(nonatomic, copy) NSString *fixtureIdentifier;
@property(nonatomic, copy) NSString *fixtureTitle;
@property(nonatomic, copy, nullable) NSURL *fixtureURL;
@property(nonatomic, copy) NSArray<PCNativeImportedBookmark *> *fixtureChildren;
@end

@implementation ImportTestBookmarkDouble
- (NSString *)identifier { return self.fixtureIdentifier; }
- (NSString *)title { return self.fixtureTitle; }
- (NSURL *)url { return self.fixtureURL; }
- (NSArray<PCNativeImportedBookmark *> *)children { return self.fixtureChildren; }
@end

@interface ImportTestEventDouble : PCNativeImportEvent
@property(nonatomic, copy, nullable) NSString *fixtureMessage;
@property(nonatomic) PCNativeImportCategories fixtureCategory;
@property(nonatomic) PCNativeImportPhase fixturePhase;
@end

@implementation ImportTestEventDouble
- (NSString *)message { return self.fixtureMessage; }
- (PCNativeImportCategories)category { return self.fixtureCategory; }
- (PCNativeImportPhase)phase { return self.fixturePhase; }
- (NSUInteger)itemCount { return 0; }
@end

@interface ImportTestResultDouble : PCNativeImportResult
@property(nonatomic) PCNativeImportOutcome fixtureOutcome;
@property(nonatomic, copy) NSArray<PCNativeImportedBookmark *> *fixtureBookmarks;
@property(nonatomic, copy) NSArray<NSString *> *fixtureWarnings;
@property(nonatomic, strong, nullable) NSError *fixtureError;
@end

@implementation ImportTestResultDouble
- (PCNativeImportOutcome)outcome { return self.fixtureOutcome; }
- (PCNativeImportCategories)completedCategories { return 0; }
- (PCNativeImportCategories)failedCategories { return 0; }
- (NSArray<PCNativeImportedBookmark *> *)bookmarks { return self.fixtureBookmarks; }
- (NSDictionary<NSString *, NSNumber *> *)historyVisitCounts { return @{}; }
- (NSArray<NSString *> *)warnings { return self.fixtureWarnings; }
- (NSError *)error { return self.fixtureError; }
@end

static char cancelledKey;

@interface ImportTestDiscoveryDouble : PCNativeImportDiscovery
@end

@implementation ImportTestDiscoveryDouble
- (void)cancel { objc_setAssociatedObject(self, &cancelledKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
@end

@interface ImportTestSessionDouble : PCNativeImportSession
@end

@implementation ImportTestSessionDouble
- (void)cancel { objc_setAssociatedObject(self, &cancelledKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
@end

@interface ImportTestExtensionResultDouble : PCNativeImportExtensionResult
@property(nonatomic) PCNativeImportOutcome fixtureOutcome;
@property(nonatomic, copy) NSSet<NSString *> *fixtureInstalled;
@property(nonatomic, copy) NSSet<NSString *> *fixtureInstalling;
@end

@implementation ImportTestExtensionResultDouble
- (PCNativeImportOutcome)outcome { return self.fixtureOutcome; }
- (NSSet<NSString *> *)installedIdentifiers { return self.fixtureInstalled; }
- (NSSet<NSString *> *)installingIdentifiers { return self.fixtureInstalling; }
- (NSArray<PCNativeImportExtensionFailure *> *)failures { return @[]; }
@end

@interface ImportTestPasswordResultDouble : PCNativePasswordFileImportResult
@property(nonatomic) PCNativeImportOutcome fixtureOutcome;
@property(nonatomic) NSUInteger fixtureImported;
@property(nonatomic) NSUInteger fixtureExisting;
@property(nonatomic) NSUInteger fixtureInvalid;
@property(nonatomic) BOOL fixtureCanRemove;
@property(nonatomic, strong, nullable) NSError *fixtureError;
@end

@implementation ImportTestPasswordResultDouble
- (PCNativeImportOutcome)outcome { return self.fixtureOutcome; }
- (NSUInteger)importedCount { return self.fixtureImported; }
- (NSUInteger)existingCount { return self.fixtureExisting; }
- (NSUInteger)invalidCount { return self.fixtureInvalid; }
- (BOOL)canRemoveSourceFile { return self.fixtureCanRemove; }
- (NSError *)error { return self.fixtureError; }
@end

@interface ImportTestPasswordSessionDouble : PCNativePasswordFileImportSession
@property(nonatomic, strong) NSMutableArray *removals;
@end

@implementation ImportTestPasswordSessionDouble
- (void)cancel { objc_setAssociatedObject(self, &cancelledKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
- (void)removeSourceFileWithCompletion:(void (^)(NSError *_Nullable))completion {
    [self.removals addObject:[completion copy]];
}
@end

static char requestSourceKey, requestPathKey, requestIdentifiersKey;

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wobjc-protocol-method-implementation"
#pragma clang diagnostic ignored "-Wobjc-designated-initializers"
@implementation PCNativeImportExtensionRequest (ImportDoubles)
- (instancetype)initWithSource:(PCNativeImportProfile *)source
                   profilePath:(NSString *)profilePath
                  extensionIDs:(NSSet<NSString *> *)extensionIDs {
    self = (PCNativeImportExtensionRequest *)[(NSObject *)self init];
    objc_setAssociatedObject(self, &requestSourceKey, source, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(self, &requestPathKey, profilePath, OBJC_ASSOCIATION_COPY_NONATOMIC);
    objc_setAssociatedObject(self, &requestIdentifiersKey, extensionIDs, OBJC_ASSOCIATION_COPY_NONATOMIC);
    return self;
}
@end
#pragma clang diagnostic pop

NSObject *ImportTestSource(NSString *identifier, NSURL *appURL) {
    ImportTestSourceDouble *source = IMPORT_DOUBLE(ImportTestSourceDouble);
    source.fixtureIdentifier = identifier;
    source.fixtureURL = appURL;
    return source;
}

NSObject *ImportTestExtension(NSString *identifier, NSString *displayName) {
    ImportTestExtensionDouble *extension = IMPORT_DOUBLE(ImportTestExtensionDouble);
    extension.fixtureIdentifier = identifier;
    extension.fixtureName = displayName;
    return extension;
}

NSObject *ImportTestProfile(NSString *identifier, NSString *displayName, NSString *directoryName,
                            NSUInteger categories, NSInteger access, NSArray *extensions) {
    ImportTestProfileDouble *profile = IMPORT_DOUBLE(ImportTestProfileDouble);
    profile.fixtureIdentifier = identifier;
    profile.fixtureName = displayName;
    profile.fixtureDirectory = directoryName;
    profile.fixtureCategories = categories;
    profile.fixtureAccess = access;
    profile.fixtureExtensions = extensions;
    profile.fixtureDecryptionRequests = [NSMutableArray array];
    return profile;
}

void ImportTestSetSidebarDecryption(NSObject *profile, BOOL available, NSData *data, NSError *error) {
    ImportTestProfileDouble *fixture = (ImportTestProfileDouble *)profile;
    fixture.fixtureDecryptable = available;
    fixture.fixtureDecrypted = data;
    fixture.fixtureDecryptionError = error;
}

NSArray<NSString *> *ImportTestSidebarDecryptionRequests(NSObject *profile) {
    ImportTestProfileDouble *fixture = (ImportTestProfileDouble *)profile;
    @synchronized(fixture) {
        return [fixture.fixtureDecryptionRequests copy];
    }
}

NSObject *ImportTestProfileResult(NSArray *profiles, NSInteger access, NSArray<NSString *> *constraints, NSError *error) {
    ImportTestProfileResultDouble *result = IMPORT_DOUBLE(ImportTestProfileResultDouble);
    result.fixtureProfiles = profiles;
    result.fixtureAccess = access;
    result.fixtureConstraints = constraints;
    result.fixtureError = error;
    return result;
}

NSObject *ImportTestBookmark(NSString *identifier, NSString *title, NSURL *url, NSArray *children) {
    ImportTestBookmarkDouble *bookmark = IMPORT_DOUBLE(ImportTestBookmarkDouble);
    bookmark.fixtureIdentifier = identifier;
    bookmark.fixtureTitle = title;
    bookmark.fixtureURL = url;
    bookmark.fixtureChildren = children;
    return bookmark;
}

NSObject *ImportTestEvent(NSString *message, NSUInteger category, NSInteger phase) {
    ImportTestEventDouble *event = IMPORT_DOUBLE(ImportTestEventDouble);
    event.fixtureMessage = message;
    event.fixtureCategory = category;
    event.fixturePhase = phase;
    return event;
}

NSObject *ImportTestResult(NSInteger outcome, NSArray *bookmarks, NSArray<NSString *> *warnings, NSError *error) {
    ImportTestResultDouble *result = IMPORT_DOUBLE(ImportTestResultDouble);
    result.fixtureOutcome = outcome;
    result.fixtureBookmarks = bookmarks;
    result.fixtureWarnings = warnings;
    result.fixtureError = error;
    return result;
}

NSObject *ImportTestDiscovery(void) { return IMPORT_DOUBLE(ImportTestDiscoveryDouble); }

NSObject *ImportTestSession(void) { return IMPORT_DOUBLE(ImportTestSessionDouble); }

BOOL ImportTestCancelled(NSObject *lease) { return [objc_getAssociatedObject(lease, &cancelledKey) boolValue]; }

NSObject *ImportTestExtensionResult(NSInteger outcome, NSSet<NSString *> *installed, NSSet<NSString *> *installing) {
    ImportTestExtensionResultDouble *result = IMPORT_DOUBLE(ImportTestExtensionResultDouble);
    result.fixtureOutcome = outcome;
    result.fixtureInstalled = installed;
    result.fixtureInstalling = installing;
    return result;
}

NSObject *ImportTestExtensionFailure(NSString *name, NSString *identifier, NSString *profilePath, NSInteger restriction) {
    return [[PCImportedExtensionFailure alloc] initWithName:name identifier:identifier profilePath:profilePath
                                                restriction:restriction];
}

NSObject *ImportTestRequestSource(NSObject *request) { return objc_getAssociatedObject(request, &requestSourceKey); }

NSString *ImportTestRequestPath(NSObject *request) { return objc_getAssociatedObject(request, &requestPathKey); }

NSSet<NSString *> *ImportTestRequestIdentifiers(NSObject *request) {
    return objc_getAssociatedObject(request, &requestIdentifiersKey);
}

NSObject *ImportTestPasswordResult(NSInteger outcome, NSUInteger imported, NSUInteger existing, NSUInteger invalid,
                                   BOOL canRemove, NSError *error) {
    ImportTestPasswordResultDouble *result = IMPORT_DOUBLE(ImportTestPasswordResultDouble);
    result.fixtureOutcome = outcome;
    result.fixtureImported = imported;
    result.fixtureExisting = existing;
    result.fixtureInvalid = invalid;
    result.fixtureCanRemove = canRemove;
    result.fixtureError = error;
    return result;
}

NSObject *ImportTestPasswordSession(void) {
    ImportTestPasswordSessionDouble *session = IMPORT_DOUBLE(ImportTestPasswordSessionDouble);
    session.removals = [NSMutableArray array];
    return session;
}

NSUInteger ImportTestRemovalCount(NSObject *session) {
    return ((ImportTestPasswordSessionDouble *)session).removals.count;
}

void ImportTestCompleteRemoval(NSObject *session, NSUInteger index, NSError *error) {
    void (^completion)(NSError *) = ((ImportTestPasswordSessionDouble *)session).removals[index];
    completion(error);
}
