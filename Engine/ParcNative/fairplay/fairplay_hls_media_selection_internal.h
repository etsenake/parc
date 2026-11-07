// ObjC++-only attachment of the HLS media selection to the player's
// AVFoundation objects. Owner sequence.
#pragma once

#import <AVFoundation/AVFoundation.h>

#include "fairplay_hls_media_selection.h"

namespace parc::fairplay {

// Starts tracking |item| (played by |player|, whose
// appliesMediaSelectionCriteriaAutomatically must be NO, as WebKit sets it):
// adds the legible output, observes the item's tracks and loads the asset's
// media selection groups. Call once, right after the item is created. The
// selection detaches when destroyed.
void HlsMediaSelectionAttach(HlsMediaSelection::Impl* selection, AVPlayer* player, AVPlayerItem* item);

}  // namespace parc::fairplay
