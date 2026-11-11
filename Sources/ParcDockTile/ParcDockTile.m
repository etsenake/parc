#import <AppKit/AppKit.h>

@interface ParcDockTile : NSObject <NSDockTilePlugIn>
@property(nonatomic, strong) NSDockTile *tile;
@property(nonatomic, strong) id observer;
@property(nonatomic, strong) NSBundle *applicationBundle;
@end

@implementation ParcDockTile
- (void)setDockTile:(NSDockTile *)tile {
  if (self.observer) {
    [[NSDistributedNotificationCenter defaultCenter] removeObserver:self.observer];
    self.observer = nil;
  }
  self.tile = tile;
  if (!tile) return;
  NSURL *plugin = [NSBundle bundleForClass:self.class].bundleURL;
  NSURL *application = plugin.URLByDeletingLastPathComponent
                              .URLByDeletingLastPathComponent
                              .URLByDeletingLastPathComponent;
  self.applicationBundle = [NSBundle bundleWithURL:application];
  if (!self.applicationBundle) return;
  __weak ParcDockTile *weakSelf = self;
  self.observer = [[NSDistributedNotificationCenter defaultCenter]
      addObserverForName:@"org.parc.Browser.appIconChanged"
      object:application.URLByResolvingSymlinksInPath.path
      queue:NSOperationQueue.mainQueue
      usingBlock:^(__unused NSNotification *notification) { [weakSelf refreshIcon]; }];
  [self refreshIcon];
}

- (void)refreshIcon {
  NSURL *resources = [self.applicationBundle.resourceURL URLByAppendingPathComponent:@"AppIcons" isDirectory:YES];
  NSData *catalogData = [NSData dataWithContentsOfURL:[resources URLByAppendingPathComponent:@"catalog.json"]];
  id catalog = catalogData ? [NSJSONSerialization JSONObjectWithData:catalogData options:0 error:NULL] : nil;
  if (![catalog isKindOfClass:NSDictionary.class]) return;
  id variants = catalog[@"variants"];
  if (![variants isKindOfClass:NSArray.class] || ![catalog[@"default"] isEqual:@"Original"]) return;
  NSString *selected = @"Original";
  NSURL *support = [[NSFileManager defaultManager] URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
  NSURL *preference = [[support URLByAppendingPathComponent:@"Parc" isDirectory:YES] URLByAppendingPathComponent:@"app-icon.json"];
  NSData *selectionData = [NSData dataWithContentsOfURL:preference];
  id selection = selectionData ? [NSJSONSerialization JSONObjectWithData:selectionData options:0 error:NULL] : nil;
  if ([selection isKindOfClass:NSDictionary.class] && [selection[@"version"] isKindOfClass:NSNumber.class] &&
      [selection[@"version"] integerValue] == 1 && [selection[@"icon"] isKindOfClass:NSString.class]) {
    NSString *candidate = selection[@"icon"];
    if ([variants containsObject:candidate] && [candidate.lastPathComponent isEqual:candidate] &&
        [candidate rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"/\\."]].location == NSNotFound) {
      selected = candidate;
    }
  }
  NSURL *url = [resources URLByAppendingPathComponent:[selected stringByAppendingPathExtension:@"icns"]];
  NSImage *image = [[NSImage alloc] initWithContentsOfURL:url];
  if (!image || !self.tile) return;
  NSImageView *view = [[NSImageView alloc] initWithFrame:NSMakeRect(0, 0, self.tile.size.width, self.tile.size.height)];
  view.image = image;
  view.imageScaling = NSImageScaleProportionallyUpOrDown;
  view.wantsLayer = YES;
  self.tile.contentView = view;
  [self.tile display];
}

- (void)dealloc {
  if (_observer) [[NSDistributedNotificationCenter defaultCenter] removeObserver:_observer];
}
@end
