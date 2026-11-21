#import "SiteFilmMedia.h"

@interface PCSiteFilmMediaState : PCNativeMediaState
@property(nonatomic, readwrite, copy, nonnull) NSString* identifier;
@property(nonatomic, readwrite, copy, nonnull) NSString* title;
@property(nonatomic, readwrite, copy, nonnull) NSString* sourceURL;
@end

@implementation PCSiteFilmMediaState
@synthesize identifier = _identifier, title = _title, sourceURL = _sourceURL;
- (BOOL)playing { return YES; }
- (BOOL)canPlayPause { return YES; }
- (BOOL)hasPreviousTrack { return YES; }
- (BOOL)hasNextTrack { return YES; }
- (BOOL)muted { return NO; }
- (double)volume { return 1; }
- (BOOL)canSetVolume { return YES; }
- (BOOL)canToggleMicrophone { return NO; }
- (BOOL)canToggleCamera { return NO; }
- (BOOL)microphoneOn { return NO; }
- (BOOL)cameraOn { return NO; }
- (BOOL)canEnterPictureInPicture { return YES; }
- (PCNativeAirPlayState)airPlayState { return PCNativeAirPlayStateUnavailable; }
- (NSString*)airPlayDeviceName { return nil; }
- (PCNativeCastState)castState { return PCNativeCastStateAvailable; }
- (NSString*)castDeviceName { return nil; }
@end

@interface PCSiteFilmMediaPageFixture : PCNativePage
@property(nonatomic, readwrite, strong, nullable) PCNativeMediaState* mediaState;
@end

@implementation PCSiteFilmMediaPageFixture
@synthesize mediaState = _mediaState;
- (BOOL)isClosed { return NO; }
@end

PCNativePage* PCSiteFilmMediaPage(NSString* identifier, NSString* title, NSString* url) {
    PCSiteFilmMediaState* state = (PCSiteFilmMediaState*)[(NSObject*)[PCSiteFilmMediaState alloc] init];
    state.identifier = identifier;
    state.title = title;
    state.sourceURL = url;
    PCSiteFilmMediaPageFixture* page = (PCSiteFilmMediaPageFixture*)[(NSObject*)[PCSiteFilmMediaPageFixture alloc] init];
    page.mediaState = state;
    return page;
}
