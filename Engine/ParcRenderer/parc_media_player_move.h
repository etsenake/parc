// Copyright 2026 Parc contributors.
// Installed by the reviewed overlay at
// //third_party/blink/renderer/core/html/media/parc_media_player_move.h.
// How a Safari-identity element that moved to another frame has that frame
// take its player (HTMLMediaElement::ParcMovePlayerToFrame()). Modules
// installs it (ModulesInitializer::Initialize(), as it does AXObjectCache's
// and the paint image generators'), since the move needs the element's audio
// output device; content then adopts the player through
// WebLocalFrameClient::ParcAdoptMediaPlayer(). A hook here keeps it off
// LocalFrameClient and CoreInitializer.
#ifndef THIRD_PARTY_BLINK_RENDERER_CORE_HTML_MEDIA_PARC_MEDIA_PLAYER_MOVE_H_
#define THIRD_PARTY_BLINK_RENDERER_CORE_HTML_MEDIA_PARC_MEDIA_PLAYER_MOVE_H_

#include "third_party/blink/renderer/core/core_export.h"

namespace blink {

class HTMLMediaElement;

namespace parc_hooks {

// Makes the player of `element`, made by another frame, the player of the
// frame of `element`'s document. Returns false if the player can't move.
using MoveWebMediaPlayer = bool (*)(HTMLMediaElement& element);

// Returns the hook it replaces, so a test can put it back.
CORE_EXPORT MoveWebMediaPlayer SetMoveWebMediaPlayer(MoveWebMediaPlayer hook);

}  // namespace parc_hooks

}  // namespace blink

#endif  // THIRD_PARTY_BLINK_RENDERER_CORE_HTML_MEDIA_PARC_MEDIA_PLAYER_MOVE_H_
