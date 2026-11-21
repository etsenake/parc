@interface PCNativeShortcutCommand : NSObject
@property(nonatomic, readonly, weak) NSMenuItem* item;
@property(nonatomic, readonly) uint64_t revision;
@property(nonatomic, readonly) NSInteger priority;
- (instancetype)initWithItem:(NSMenuItem*)item revision:(uint64_t)revision priority:(NSInteger)priority;
+ (void)bindingsDidChange;
@end

@implementation PCNativeShortcutCommand
- (instancetype)initWithItem:(NSMenuItem*)item revision:(uint64_t)revision priority:(NSInteger)priority {
  self = [super init];
  if (self) {
    _item = item;
    _revision = revision;
    _priority = priority;
  }
  return self;
}
+ (void)bindingsDidChange {}
@end
