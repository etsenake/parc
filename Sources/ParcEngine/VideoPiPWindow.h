// Copyright 2026 Parc contributors.
#ifndef CEF_LIBCEF_BROWSER_PARC_NATIVE_VIDEO_PIP_PRESENTER_H_
#define CEF_LIBCEF_BROWSER_PARC_NATIVE_VIDEO_PIP_PRESENTER_H_
#import <Cocoa/Cocoa.h>

#import "native_appkit_bridge.h"

NS_ASSUME_NONNULL_BEGIN
void PCPictureInPicturePointAtControl(BOOL control);

NS_SWIFT_UI_ACTOR
@interface PCVideoPiPPresenter
    : NSObject <NSWindowDelegate, PCNativeVideoPiPWindow>
- (instancetype)initWithVideoView:(NSView*)videoView
                      sourceFrame:(NSRect)sourceFrame
                           action:(void (^)(PCVideoPiPAction, double))action
                          changed:(dispatch_block_t)changed;
@property(nonatomic, readonly) NSPanel* panel;
@property(nonatomic, readonly) NSView* videoView;
@property(nonatomic, readonly, getter=isInvalidated) BOOL invalidated;
- (void)showInactive;
- (void)hide;
- (void)invalidate;
- (void)setNaturalSize:(NSSize)size;
- (void)setAction:(PCVideoPiPAction)action visible:(BOOL)visible;
- (void)setAction:(PCVideoPiPAction)action title:(NSString*)title;
- (void)setControlsVisible:(BOOL)visible;
- (void)setSourceTitle:(NSString*)title;
- (void)setFavicon:(nullable NSImage*)image;
- (void)setCaptions:(nullable NSImage*)image bounds:(NSRect)bounds;
- (void)setPosition:(double)position duration:(double)duration;
- (void)setPosition:(double)position
           duration:(double)duration
      playbackRate:(double)playbackRate;
@end
NS_ASSUME_NONNULL_END
#endif
