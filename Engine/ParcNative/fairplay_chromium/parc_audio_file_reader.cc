#include "media/filters/audio_file_reader.h"

#include <memory>
#include <utility>
#include <vector>

#include "media/base/audio_buffer.h"
#include "media/base/audio_bus.h"
#include "media/base/decoder_buffer.h"
#include "media/ffmpeg/scoped_av_packet.h"

namespace media {

bool AudioFileReader::OpenWithoutDecoder() {
  if (!OpenDemuxer() || !OpenConfig()) {
    return false;
  }
  output_sample_rate_.reset();
  output_channels_.reset();
  decoded_audio_packets_ = &decoded_output_;
  return true;
}

scoped_refptr<DecoderBuffer> AudioFileReader::ReadNextBuffer() {
  auto packet = ScopedAVPacket::Allocate();
  if (!ReadPacket(packet.get())) {
    return nullptr;
  }
  return CreateDecoderBuffer(packet);
}

void AudioFileReader::AddDecodedOutput(scoped_refptr<AudioBuffer> buffer) {
  OnOutput(std::move(buffer));
}

std::vector<std::unique_ptr<AudioBus>> AudioFileReader::TakeDecodedOutput(
    bool all_packets_decoded) {
  if (pending_output_buffer_) {
    FinalizeDecodedBuffer(std::move(pending_output_buffer_),
                          all_packets_decoded && !on_output_error_);
  }
  decoded_audio_packets_ = nullptr;
  return std::move(decoded_output_);
}

}
