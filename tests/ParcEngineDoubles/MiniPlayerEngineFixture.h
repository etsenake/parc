#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface ParcMiniPlayerEngineFixture : NSObject
- (instancetype)initWithIdentifier:(NSString *)identifier title:(NSString *)title;
@property(nonatomic, readonly) NSObject *page;
@property(nonatomic, readonly) NSObject *state;
@property(nonatomic) BOOL available;
@property(nonatomic) BOOL refusesActions;
@property(nonatomic) BOOL playing;
@property(nonatomic) BOOL canSetVolume;
@property(nonatomic) BOOL muted;
@property(nonatomic) BOOL canToggleCamera;
@property(nonatomic) BOOL canToggleMicrophone;
@property(nonatomic) BOOL cameraOn;
@property(nonatomic) BOOL microphoneOn;
@property(nonatomic) NSInteger airPlayState;
@property(nonatomic) NSInteger castState;
@property(nonatomic, copy, nullable) NSString *airPlayDeviceName;
@property(nonatomic, copy, nullable) NSString *castDeviceName;
@property(nonatomic, readonly) NSArray<NSNumber *> *actions;
@property(nonatomic, readonly) NSArray<NSString *> *chooserRequests;
- (void)dismissChooser;
@end

NS_ASSUME_NONNULL_END
