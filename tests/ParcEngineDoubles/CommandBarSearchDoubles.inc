@class PCNativePage;
@class PCNativeBrowserWindow;

@interface PCNativeSearchNavigation : NSObject
@property(nonatomic, copy) NSString* profilePath;
@property(nonatomic) uint64_t revision;
@property(nonatomic, copy) NSURL* URL;
@property(nonatomic, copy) NSString* title;
@property(nonatomic, copy) NSString* detail;
@property(nonatomic) BOOL search;
@property(nonatomic, copy) NSString* editText;
@property(nonatomic, copy) NSString* inlineCompletionText;
@property(nonatomic) BOOL canCompleteWithTab;
@property(nonatomic, copy) NSString* matchType;
@property(nonatomic) NSInteger relevance;
@end

@implementation PCNativeSearchNavigation
@end

@interface PCNativeOmniboxExtensionAction : NSObject
@property(nonatomic, copy) NSString* identifier;
@property(nonatomic, copy) NSString* extensionID;
@property(nonatomic, copy) NSString* title;
@property(nonatomic, copy) NSString* detail;
@property(nonatomic, copy) NSString* editText;
@property(nonatomic) NSUInteger resultIndex;
@end

@implementation PCNativeOmniboxExtensionAction
@end

@interface PCNativeOmniboxScope : NSObject
@property(nonatomic, copy) NSString* identifier;
@property(nonatomic, copy) NSString* name;
@property(nonatomic, copy) NSString* keyword;
@property(nonatomic) uint64_t revision;
@property(nonatomic) BOOL spaceTriggerEnabled;
@property(nonatomic, strong) PCNativeSearchNavigation* result;
@property(nonatomic, strong) PCNativeOmniboxExtensionAction* extensionAction;
@property(nonatomic, getter=isExtension) BOOL extension;
@property(nonatomic, copy) NSString* templateURL;
@property(nonatomic, copy) NSString* searchHost;
@property(nonatomic, getter=isPrepopulated) BOOL prepopulated;
@property(nonatomic, getter=isLearned) BOOL learned;
@end

@implementation PCNativeOmniboxScope
@end

@interface PCNativeOmniboxSnapshot : NSObject
@property(nonatomic) uint64_t revision;
@property(nonatomic, copy) NSString* input;
@property(nonatomic, copy) NSArray<PCNativeSearchNavigation*>* results;
@property(nonatomic, copy) NSArray<PCNativeOmniboxExtensionAction*>* extensionActions;
@property(nonatomic, copy) NSArray<PCNativeOmniboxScope*>* scopeOffers;
@property(nonatomic, copy) NSArray<PCNativeOmniboxScope*>* siteScopes;
@property(nonatomic, strong) PCNativeOmniboxScope* activeScope;
@property(nonatomic, strong) NSError* error;
@end

@implementation PCNativeOmniboxSnapshot
@end

@interface PCNativeOmnibox : NSObject
@property(nonatomic, copy) void (^snapshotChanged)(PCNativeOmniboxSnapshot*);
@property(nonatomic, copy) NSString* profilePath;
@property(nonatomic) uint64_t revision;
@property(nonatomic) BOOL cancelled;
@property(nonatomic, strong) PCNativeOmniboxScope* entered;
- (instancetype)initWithProfilePath:(NSString*)path page:(PCNativePage*)page window:(PCNativeBrowserWindow*)window;
- (void)updateInput:(NSString*)input allowsInlineCompletion:(BOOL)allowed;
- (BOOL)canSubmit;
- (void)cancel;
- (BOOL)enterScope:(PCNativeOmniboxScope*)scope;
- (BOOL)leaveScope;
- (BOOL)canDeleteResult:(PCNativeSearchNavigation*)navigation;
- (BOOL)canExecuteExtensionAction:(PCNativeOmniboxExtensionAction*)action;
- (BOOL)canDeleteExtensionAction:(PCNativeOmniboxExtensionAction*)action;
- (NSNumber*)parcTestPublish:(NSDictionary<NSString*, id>*)message;
@end

@implementation PCNativeOmnibox
- (instancetype)initWithProfilePath:(NSString*)path page:(PCNativePage*)page window:(PCNativeBrowserWindow*)window {
  if ((self = [super init])) { _profilePath = [path copy]; }
  return self;
}
- (void)updateInput:(NSString*)input allowsInlineCompletion:(BOOL)allowed {}
- (BOOL)canSubmit { return !self.cancelled; }
- (void)cancel { self.cancelled = YES; }
- (BOOL)enterScope:(PCNativeOmniboxScope*)scope { self.entered = scope; return YES; }
- (BOOL)leaveScope { self.entered = nil; return YES; }
- (BOOL)canDeleteResult:(PCNativeSearchNavigation*)navigation { return NO; }
- (BOOL)canExecuteExtensionAction:(PCNativeOmniboxExtensionAction*)action { return YES; }
- (BOOL)canDeleteExtensionAction:(PCNativeOmniboxExtensionAction*)action { return NO; }

- (NSNumber*)parcTestPublish:(NSDictionary<NSString*, id>*)message {
  PCNativeOmniboxSnapshot* snapshot = [PCNativeOmniboxSnapshot new];
  snapshot.revision = ++self.revision;
  snapshot.input = message[@"input"] ?: @"";
  NSMutableArray<PCNativeSearchNavigation*>* results = [NSMutableArray array];
  for (NSDictionary* row in message[@"results"]) {
    PCNativeSearchNavigation* navigation = [PCNativeSearchNavigation new];
    navigation.profilePath = self.profilePath;
    navigation.revision = snapshot.revision;
    navigation.URL = [NSURL URLWithString:row[@"url"]];
    navigation.title = row[@"title"] ?: @"";
    navigation.detail = row[@"detail"] ?: @"";
    navigation.search = [row[@"search"] boolValue];
    navigation.editText = row[@"editText"] ?: navigation.title;
    navigation.inlineCompletionText = row[@"inlineCompletion"];
    navigation.canCompleteWithTab = navigation.inlineCompletionText != nil;
    navigation.matchType = row[@"type"] ?: (navigation.search ? @"search-suggest" : @"url-what-you-typed");
    [results addObject:navigation];
  }
  snapshot.results = results;
  NSMutableArray<PCNativeOmniboxExtensionAction*>* extensions = [NSMutableArray array];
  for (NSDictionary* row in message[@"extensions"]) {
    PCNativeOmniboxExtensionAction* action = [PCNativeOmniboxExtensionAction new];
    action.identifier = row[@"id"] ?: @"fixture";
    action.extensionID = action.identifier;
    action.title = row[@"title"] ?: @"Extension search";
    action.detail = row[@"detail"] ?: @"Extension";
    action.editText = row[@"editText"] ?: @"extension";
    action.resultIndex = [row[@"index"] unsignedIntegerValue];
    [extensions addObject:action];
  }
  snapshot.extensionActions = extensions;
  NSMutableArray<PCNativeOmniboxScope*>* sites = [NSMutableArray array], *offers = [NSMutableArray array];
  for (NSDictionary* row in message[@"scopes"]) {
    PCNativeOmniboxScope* scope = [PCNativeOmniboxScope new];
    scope.revision = snapshot.revision;
    scope.searchHost = row[@"host"];
    scope.name = row[@"name"] ?: scope.searchHost;
    scope.identifier = scope.name;
    scope.keyword = scope.searchHost;
    scope.templateURL = row[@"template"] ?: @"";
    scope.learned = [row[@"learned"] boolValue];
    scope.spaceTriggerEnabled = [row[@"space"] boolValue];
    NSNumber* result = row[@"result"];
    NSNumber* extensionIndex = row[@"extension"];
    if (result && result.unsignedIntegerValue < results.count) {
      scope.result = results[result.unsignedIntegerValue];
      [offers addObject:scope];
    } else if (extensionIndex && extensionIndex.unsignedIntegerValue < extensions.count) {
      scope.extension = YES;
      scope.extensionAction = extensions[extensionIndex.unsignedIntegerValue];
      [offers addObject:scope];
    } else {
      [sites addObject:scope];
    }
  }
  snapshot.siteScopes = sites;
  snapshot.scopeOffers = offers;
  snapshot.activeScope = [message[@"showActiveScope"] boolValue] ? self.entered : nil;
  if ([message[@"error"] isKindOfClass:NSString.class]) {
    snapshot.error = [NSError errorWithDomain:@"ParcSearchTests" code:1
                                    userInfo:@{NSLocalizedDescriptionKey:message[@"error"]}];
  }
  if (self.snapshotChanged) { self.snapshotChanged(snapshot); }
  return @YES;
}
@end
