// Copyright 2026 Parc contributors.
#ifndef MEDIA_BASE_PARC_AV1_SUPPORT_H_
#define MEDIA_BASE_PARC_AV1_SUPPORT_H_

#include "base/command_line.h"

namespace media {
// Supplied by the browser before sandboxing; WebKit's
// AV1UtilitiesCocoa::av1HardwareDecoderAvailableInProcess uses the same query.
inline constexpr char kParcAV1HardwareDecoder[] = "parc-av1-hardware-decoder";
inline bool ParcAV1HardwareDecoderAvailable() {
  return base::CommandLine::ForCurrentProcess()->GetSwitchValueASCII(
             kParcAV1HardwareDecoder) == "1";
}
}  // namespace media
#endif  // MEDIA_BASE_PARC_AV1_SUPPORT_H_
