// ObjC++-only access from FairPlayRenderer to the key session.
#pragma once

#import <AVFoundation/AVFoundation.h>

#include <vector>

#include "fairplay_key_session.h"

namespace parc::fairplay {

// Makes |recipient| (an AVSampleBufferDisplayLayer or AVSampleBufferAudioRenderer)
// a content key recipient of the key system's AVContentKeySession, so it
// decrypts protected samples with the session's keys, matched by the key ID in
// each sample's format description. Must happen before the recipient processes
// media; a recipient belongs to one session for its lifetime. Owner sequence.
Result AttachContentKeyRecipient(FairPlayCdm::Impl* cdm, id<AVContentKeyRecipient> recipient);

// After this the recipient is inoperable (AVContentKeySession semantics).
void DetachContentKeyRecipient(FairPlayCdm::Impl* cdm, id<AVContentKeyRecipient> recipient);

}  // namespace parc::fairplay
