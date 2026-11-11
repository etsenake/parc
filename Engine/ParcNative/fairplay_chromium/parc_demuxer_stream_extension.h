// Copyright 2026 Parc contributors.
// Installed by the reviewed overlay at
// //media/base/parc_demuxer_stream_extension.h.
// Parc's answers about a media::DemuxerStream, reached through
// DemuxerStream::GetParcExtension(), which is null for a stream without them.
// Kept out of demuxer_stream.h so that changing them rebuilds only what uses
// them.
#ifndef MEDIA_BASE_PARC_DEMUXER_STREAM_EXTENSION_H_
#define MEDIA_BASE_PARC_DEMUXER_STREAM_EXTENSION_H_

#include "media/base/demuxer_stream.h"

namespace media {

class ParcDemuxerStreamExtension {
 public:
  // False for a stream the page turned off (a disabled ChunkDemuxerStream
  // answers reads with end of stream).
  virtual bool ParcIsEnabled() const = 0;

  // The stream this one reads for a renderer that took over from another
  // (ChunkDemuxerStream::ParcHandOffReader()), else this one.
  virtual DemuxerStream* ParcHandOffSource() = 0;

 protected:
  virtual ~ParcDemuxerStreamExtension() = default;
};

// The answers for any stream: one without the extension is enabled and reads
// for itself.
inline bool ParcStreamIsEnabled(DemuxerStream* stream) {
  ParcDemuxerStreamExtension* parc = stream->GetParcExtension();
  return !parc || parc->ParcIsEnabled();
}

inline DemuxerStream* ParcStreamHandOffSource(DemuxerStream* stream) {
  ParcDemuxerStreamExtension* parc = stream->GetParcExtension();
  return parc ? parc->ParcHandOffSource() : stream;
}

}  // namespace media

#endif  // MEDIA_BASE_PARC_DEMUXER_STREAM_EXTENSION_H_
