// Copyright 2026 Parc contributors.
// AirPlay for the media elements of Safari-identity pages
// (fairplay_chromium/NATIVE_HLS.md "AirPlay"), WebKit's
// WebMediaSessionManager and MediaPlaybackTargetPickerMac in the browser:
// one AirPlay route detector, one AVOutputContext (WebKit's
// AVRoutePickerViewTargetPicker uses the iTunes audio context) and the
// system's route list, which only AVKit's view service may fill (listing and
// choosing AirPlay devices needs entitlements only Apple's services hold).
// The element that opened the list plays to the route chosen in it.
#ifndef PARC_NATIVE_NATIVE_AIRPLAY_H_
#define PARC_NATIVE_NATIVE_AIRPLAY_H_

#import <AppKit/AppKit.h>

#include <string>

namespace content {
class WebContents;
}

namespace parc {

// Registers the browser's content::ParcPlaybackTargetHandler. Main thread,
// at startup.
void InstallNativeAirPlay();

// What the Mini Player shows for |contents|' AirPlay player:
// PCNativeAirPlayState's raw value and the device's name.
struct NativeAirPlayState {
  int state = 0;
  std::string device_name;
  bool operator==(const NativeAirPlayState&) const = default;
};
NativeAirPlayState NativeAirPlayStateForContents(content::WebContents* contents);

// Opens the route list at |rect| in |view| for |contents|' AirPlay player;
// |dismissed| runs once when it closes. False (and |dismissed| never runs)
// when |contents| has no such player or the list can't open.
bool ShowNativeAirPlayPicker(content::WebContents* contents,
                             NSView* view,
                             NSRect rect,
                             void (^dismissed)(void));

// Defined in native_media_controls.mm: |contents|' AirPlay state changed, so
// its Mini Player row republishes.
void NativeMediaAirPlayChanged(content::WebContents* contents);

}  // namespace parc

#endif  // PARC_NATIVE_NATIVE_AIRPLAY_H_
