#import "MiniPlayerEngineFixture.h"
#import "../../Engine/ParcNative/native_appkit_bridge.h"
#import <objc/runtime.h>

@interface ParcFixtureMediaState : PCNativeMediaState
@property(nonatomic, readwrite, copy) NSString *identifier;
@property(nonatomic, readwrite, copy) NSString *title;
@property(nonatomic, readwrite) BOOL playing;
@property(nonatomic, readwrite) BOOL canSetVolume;
@property(nonatomic, readwrite) BOOL muted;
@property(nonatomic, readwrite) BOOL canToggleCamera;
@property(nonatomic, readwrite) BOOL canToggleMicrophone;
@property(nonatomic, readwrite) BOOL cameraOn;
@property(nonatomic, readwrite) BOOL microphoneOn;
@property(nonatomic, readwrite) PCNativeAirPlayState airPlayState;
@property(nonatomic, readwrite) PCNativeCastState castState;
@property(nonatomic, readwrite, copy, nullable) NSString *airPlayDeviceName;
@property(nonatomic, readwrite, copy, nullable) NSString *castDeviceName;
@end

@implementation ParcFixtureMediaState
@synthesize identifier = _identifier, title = _title, playing = _playing, canSetVolume = _canSetVolume, muted = _muted;
@synthesize canToggleCamera = _canToggleCamera, canToggleMicrophone = _canToggleMicrophone, cameraOn = _cameraOn, microphoneOn = _microphoneOn;
@synthesize airPlayState = _airPlayState, castState = _castState, airPlayDeviceName = _airPlayDeviceName, castDeviceName = _castDeviceName;
- (NSString *)sourceURL { return @"https://example.test/media"; }
- (BOOL)canPlayPause { return YES; }
- (BOOL)hasPreviousTrack { return YES; }
- (BOOL)hasNextTrack { return YES; }
- (BOOL)canEnterPictureInPicture { return YES; }
- (double)volume { return 1; }
@end

@interface ParcFixtureMediaPage : PCNativePage
@property(nonatomic, strong, nullable) PCNativeMediaState *mediaState;
@property(nonatomic) BOOL refusesActions;
@property(nonatomic, strong) NSMutableArray<NSNumber *> *actions;
@property(nonatomic, strong) NSMutableArray<NSString *> *chooserRequests;
@property(nonatomic, copy, nullable) void (^dismissChooser)(void);
@end

@implementation ParcFixtureMediaPage
- (BOOL)isClosed { return NO; }
- (BOOL)acceptsState:(PCNativeMediaState *)state { return !self.refusesActions && self.mediaState == state; }
- (BOOL)performMediaAction:(PCNativeMediaAction)action state:(PCNativeMediaState *)state inWindow:(NSWindow *)window {
    (void)window;
    if (![self acceptsState:state]) return NO;
    [self.actions addObject:@(action)];
    return YES;
}
- (BOOL)setMediaVolume:(double)volume state:(PCNativeMediaState *)state inWindow:(NSWindow *)window {
    (void)volume;
    (void)window;
    return [self acceptsState:state];
}
- (BOOL)dismissMediaState:(PCNativeMediaState *)state inWindow:(NSWindow *)window {
    (void)window;
    return [self acceptsState:state];
}
- (BOOL)showAirPlayPickerForMediaState:(PCNativeMediaState *)state relativeToRect:(NSRect)rect
    ofView:(NSView *)view inWindow:(NSWindow *)window dismissed:(void (^)(void))dismissed {
    (void)rect;
    (void)view;
    (void)window;
    if (![self acceptsState:state]) return NO;
    [self.chooserRequests addObject:@"airplay"];
    self.dismissChooser = dismissed;
    return YES;
}
- (BOOL)showCastChooserForMediaState:(PCNativeMediaState *)state relativeToRect:(NSRect)rect
    ofView:(NSView *)view inWindow:(NSWindow *)window dismissed:(void (^)(void))dismissed {
    (void)rect;
    (void)view;
    (void)window;
    if (![self acceptsState:state]) return NO;
    [self.chooserRequests addObject:@"cast"];
    self.dismissChooser = dismissed;
    return YES;
}
@end

@implementation ParcMiniPlayerEngineFixture {
    ParcFixtureMediaPage *_fixturePage;
    ParcFixtureMediaState *_fixtureState;
}

- (instancetype)initWithIdentifier:(NSString *)identifier title:(NSString *)title {
    self = [super init];
    if (self) {
        _fixturePage = class_createInstance(ParcFixtureMediaPage.class, 0);
        _fixtureState = class_createInstance(ParcFixtureMediaState.class, 0);
        _fixtureState.identifier = identifier;
        _fixtureState.title = title;
        _fixtureState.playing = YES;
        _fixtureState.canSetVolume = YES;
        _fixturePage.actions = [NSMutableArray array];
        _fixturePage.chooserRequests = [NSMutableArray array];
        _fixturePage.mediaState = _fixtureState;
    }
    return self;
}

- (NSObject *)page { return _fixturePage; }
- (NSObject *)state { return _fixtureState; }
- (BOOL)available { return _fixturePage.mediaState != nil; }
- (void)setAvailable:(BOOL)available { _fixturePage.mediaState = available ? _fixtureState : nil; }
- (BOOL)refusesActions { return _fixturePage.refusesActions; }
- (void)setRefusesActions:(BOOL)refusesActions { _fixturePage.refusesActions = refusesActions; }
- (BOOL)playing { return _fixtureState.playing; }
- (void)setPlaying:(BOOL)playing { _fixtureState.playing = playing; }
- (BOOL)canSetVolume { return _fixtureState.canSetVolume; }
- (void)setCanSetVolume:(BOOL)canSetVolume { _fixtureState.canSetVolume = canSetVolume; }
- (BOOL)muted { return _fixtureState.muted; }
- (void)setMuted:(BOOL)muted { _fixtureState.muted = muted; }
- (BOOL)canToggleCamera { return _fixtureState.canToggleCamera; }
- (void)setCanToggleCamera:(BOOL)canToggleCamera { _fixtureState.canToggleCamera = canToggleCamera; }
- (BOOL)canToggleMicrophone { return _fixtureState.canToggleMicrophone; }
- (void)setCanToggleMicrophone:(BOOL)canToggleMicrophone { _fixtureState.canToggleMicrophone = canToggleMicrophone; }
- (BOOL)cameraOn { return _fixtureState.cameraOn; }
- (void)setCameraOn:(BOOL)cameraOn { _fixtureState.cameraOn = cameraOn; }
- (BOOL)microphoneOn { return _fixtureState.microphoneOn; }
- (void)setMicrophoneOn:(BOOL)microphoneOn { _fixtureState.microphoneOn = microphoneOn; }
- (NSInteger)airPlayState { return _fixtureState.airPlayState; }
- (void)setAirPlayState:(NSInteger)state { _fixtureState.airPlayState = (PCNativeAirPlayState)state; }
- (NSInteger)castState { return _fixtureState.castState; }
- (void)setCastState:(NSInteger)state { _fixtureState.castState = (PCNativeCastState)state; }
- (NSString *)airPlayDeviceName { return _fixtureState.airPlayDeviceName; }
- (void)setAirPlayDeviceName:(NSString *)name { _fixtureState.airPlayDeviceName = name; }
- (NSString *)castDeviceName { return _fixtureState.castDeviceName; }
- (void)setCastDeviceName:(NSString *)name { _fixtureState.castDeviceName = name; }
- (NSArray<NSNumber *> *)actions { return [_fixturePage.actions copy]; }
- (NSArray<NSString *> *)chooserRequests { return [_fixturePage.chooserRequests copy]; }
- (void)dismissChooser {
    void (^dismissed)(void) = _fixturePage.dismissChooser;
    _fixturePage.dismissChooser = nil;
    if (dismissed) dismissed();
}
@end
