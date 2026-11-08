// Copyright 2026 Parc contributors.
#ifndef PARC_NATIVE_GMC_PRESENTATION_H_
#define PARC_NATIVE_GMC_PRESENTATION_H_
#import <AppKit/AppKit.h>
#include <string>
#include "base/functional/callback.h"
namespace content { class WebContents; }
namespace parc {
void InstallNativeGmcPresentationHandler();
bool CloseNativeGmcPresentationForPage(content::WebContents* contents);

// What the Mini Player shows for |contents|' Cast: PCNativeCastState's raw
// value and the receiver's name. Chromium's remote playback of a media
// session's one player, as Chrome's own media controls cast it, on
// Chrome-identity pages.
struct NativeMediaCastState {
  int state = 0;
  std::string device_name;
  bool operator==(const NativeMediaCastState&) const = default;
};
NativeMediaCastState NativeMediaCastStateForContents(content::WebContents* contents);

// Opens Chromium's media controls chooser for |contents|' player at |rect| in
// |view|. |valid| gates every action in it; |dismissed| runs once when it
// closes. False (and |dismissed| never runs) when the player can't cast.
bool ShowNativeMediaCastChooser(content::WebContents* contents,
                                NSView* view,
                                NSRect rect,
                                base::RepeatingCallback<bool()> valid,
                                void (^dismissed)(void));

// Defined in native_media_controls.mm: |contents|' Cast state changed, so its
// Mini Player row republishes.
void NativeMediaCastChanged(content::WebContents* contents);
}  // namespace parc
#endif
