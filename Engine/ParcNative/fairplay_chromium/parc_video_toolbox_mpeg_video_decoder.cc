// Installed by the reviewed overlay at
// //media/gpu/mac/parc_video_toolbox_mpeg_video_decoder.cc (media/gpu/mac).

#include "media/gpu/mac/parc_video_toolbox_mpeg_video_decoder.h"

#include <utility>

#include "base/numerics/safe_conversions.h"
#include "media/base/bit_reader.h"
#include "media/base/media_log.h"
#include "media/base/video_color_space.h"
#include "media/base/video_types.h"
#include "ui/gfx/geometry/rect.h"

namespace media {

namespace {

// ISO/IEC 13818-2 table 6-1.
constexpr uint8_t kPictureStartCode = 0x00;
constexpr uint8_t kFirstSliceStartCode = 0x01;
constexpr uint8_t kLastSliceStartCode = 0xAF;
constexpr uint8_t kSequenceHeaderCode = 0xB3;
constexpr uint8_t kExtensionStartCode = 0xB5;
// Table 6-2.
constexpr uint32_t kSequenceExtensionId = 1;
// Table 6-12.
constexpr int kIntraCoded = 1;
constexpr int kBidirectionallyPredictiveCoded = 3;
// Table 6-5.
constexpr uint32_t kChroma422 = 2;
constexpr uint32_t kChroma444 = 3;

bool IsStartCode(base::span<const uint8_t> data, size_t i) {
  return i + 3 < data.size() && data[i] == 0 && data[i + 1] == 0 &&
         data[i + 2] == 1;
}

}  // namespace

ParcVideoToolboxMpegVideoDecoder::ParcVideoToolboxMpegVideoDecoder(
    std::unique_ptr<MediaLog> media_log,
    DecodeCB decode_cb,
    OutputCB output_cb,
    base::span<const uint8_t> extra_data)
    : media_log_(std::move(media_log)),
      decode_cb_(std::move(decode_cb)),
      output_cb_(std::move(output_cb)) {
  if (IsStartCode(extra_data, 0) && extra_data[3] == kSequenceHeaderCode) {
    ReadSequence(extra_data);
  }
}

ParcVideoToolboxMpegVideoDecoder::~ParcVideoToolboxMpegVideoDecoder() =
    default;

void ParcVideoToolboxMpegVideoDecoder::SetStream(
    int32_t id,
    scoped_refptr<DecoderBuffer> buffer) {
  buffer_ = std::move(buffer);
}

bool ParcVideoToolboxMpegVideoDecoder::Flush() {
  if (held_anchor_) {
    output_cb_.Run(std::move(held_anchor_));
  }
  return true;
}

void ParcVideoToolboxMpegVideoDecoder::Reset() {
  buffer_.reset();
  held_anchor_.reset();
}

AcceleratedVideoDecoder::DecodeResult
ParcVideoToolboxMpegVideoDecoder::Decode() {
  if (!buffer_) {
    return kRanOutOfStreamData;
  }
  const scoped_refptr<DecoderBuffer> buffer = std::move(buffer_);
  const base::span<const uint8_t> data(*buffer);

  // The headers before the first slice: a sequence header, and the picture
  // header of the frame (or its first field).
  int picture_coding_type = 0;
  for (size_t i = 0; i < data.size(); ++i) {
    if (!IsStartCode(data, i)) {
      continue;
    }
    const uint8_t code = data[i + 3];
    if (code >= kFirstSliceStartCode && code <= kLastSliceStartCode) {
      break;
    }
    if (code == kSequenceHeaderCode && !ReadSequence(data.subspan(i))) {
      MEDIA_LOG(ERROR, media_log_.get()) << "Invalid sequence header";
      return kDecodeError;
    }
    if (code == kPictureStartCode && !picture_coding_type &&
        i + 5 < data.size()) {
      // 6.2.3: temporal_reference, then picture_coding_type.
      picture_coding_type = (data[i + 5] >> 3) & 7;
    }
    i += 3;
  }
  // Only I-, P- and B-pictures decode, once a sequence header has come.
  if (!format_ || picture_coding_type < kIntraCoded ||
      picture_coding_type > kBidirectionallyPredictiveCoded) {
    return kRanOutOfStreamData;
  }

  base::apple::ScopedCFTypeRef<CMBlockBufferRef> block;
  OSStatus status = CMBlockBufferCreateWithMemoryBlock(
      kCFAllocatorDefault, /*memoryBlock=*/nullptr, data.size(),
      kCFAllocatorDefault, /*customBlockSource=*/nullptr, /*offsetToData=*/0,
      data.size(), /*flags=*/0, block.InitializeInto());
  if (status != noErr) {
    OSSTATUS_MEDIA_LOG(ERROR, status, media_log_.get())
        << "CMBlockBufferCreateWithMemoryBlock()";
    return kDecodeError;
  }
  status =
      CMBlockBufferReplaceDataBytes(data.data(), block.get(), 0, data.size());
  if (status != noErr) {
    OSSTATUS_MEDIA_LOG(ERROR, status, media_log_.get())
        << "CMBlockBufferReplaceDataBytes()";
    return kDecodeError;
  }
  base::apple::ScopedCFTypeRef<CMSampleBufferRef> sample;
  const size_t sample_size = data.size();
  status = CMSampleBufferCreate(
      kCFAllocatorDefault, block.get(), /*dataReady=*/true,
      /*makeDataReadyCallback=*/nullptr, /*makeDataReadyRefcon=*/nullptr,
      format_.get(), /*numSamples=*/1, /*numSampleTimingEntries=*/0,
      /*sampleTimingArray=*/nullptr, /*numSampleSizeEntries=*/1, &sample_size,
      sample.InitializeInto());
  if (status != noErr) {
    OSSTATUS_MEDIA_LOG(ERROR, status, media_log_.get())
        << "CMSampleBufferCreate()";
    return kDecodeError;
  }

  auto picture = base::MakeRefCounted<CodecPicture>();
  picture->set_visible_rect(session_metadata_.visible_rect);
  if (picture_coding_type == kBidirectionallyPredictiveCoded) {
    decode_cb_.Run(std::move(sample), session_metadata_, picture);
    output_cb_.Run(std::move(picture));
  } else {
    if (held_anchor_) {
      output_cb_.Run(std::move(held_anchor_));
    }
    decode_cb_.Run(std::move(sample), session_metadata_, picture);
    held_anchor_ = std::move(picture);
  }
  return kRanOutOfStreamData;
}

bool ParcVideoToolboxMpegVideoDecoder::ReadSequence(
    base::span<const uint8_t> data) {
  // 6.2.2.1: horizontal_size_value, vertical_size_value.
  BitReader header(data.subspan(4u));
  uint32_t width, height;
  if (!header.ReadBits(12, &width) || !header.ReadBits(12, &height)) {
    return false;
  }
  // A sequence_extension right after the header makes it MPEG-2 (6.2.2.3):
  // profile_and_level_indication and progressive_sequence, chroma_format,
  // then the size extensions.
  CMVideoCodecType codec_type = kCMVideoCodecType_MPEG1Video;
  VideoChromaSampling chroma_sampling = VideoChromaSampling::k420;
  for (size_t i = 4; i < data.size(); ++i) {
    if (!IsStartCode(data, i)) {
      continue;
    }
    BitReader extension(data.subspan(i + 3));
    uint32_t code, id, chroma_format, horizontal_size_extension,
        vertical_size_extension;
    if (extension.ReadBits(8, &code) && code == kExtensionStartCode &&
        extension.ReadBits(4, &id) && id == kSequenceExtensionId &&
        extension.SkipBits(8 + 1) && extension.ReadBits(2, &chroma_format) &&
        extension.ReadBits(2, &horizontal_size_extension) &&
        extension.ReadBits(2, &vertical_size_extension)) {
      codec_type = kCMVideoCodecType_MPEG2Video;
      width |= horizontal_size_extension << 12;
      height |= vertical_size_extension << 12;
      if (chroma_format == kChroma422) {
        chroma_sampling = VideoChromaSampling::k422;
      } else if (chroma_format == kChroma444) {
        chroma_sampling = VideoChromaSampling::k444;
      }
    }
    break;
  }
  const gfx::Size size(base::checked_cast<int>(width),
                       base::checked_cast<int>(height));
  if (size.IsEmpty()) {
    return false;
  }
  if (format_ && codec_type == codec_type_ && size == size_ &&
      chroma_sampling == session_metadata_.chroma_sampling) {
    return true;
  }

  // No extensions: AVStreamDataParser's format carries no color either, so
  // VideoToolbox tags the images as it does for Safari.
  format_.reset();
  OSStatus status = CMVideoFormatDescriptionCreate(
      kCFAllocatorDefault, codec_type, size.width(), size.height(),
      /*extensions=*/nullptr, format_.InitializeInto());
  if (status != noErr) {
    OSSTATUS_MEDIA_LOG(ERROR, status, media_log_.get())
        << "CMVideoFormatDescriptionCreate()";
    return false;
  }
  codec_type_ = codec_type;
  size_ = size;
  // VideoToolbox decodes MPEG-1 and MPEG-2 in software on a Mac without a
  // hardware decoder for them (Apple silicon).
  session_metadata_ = VideoToolboxDecompressionSessionMetadata{
      /*allow_software_decoding=*/true,
      /*bit_depth=*/8,
      /*chroma_sampling=*/chroma_sampling,
      /*has_alpha=*/false,
      /*visible_rect=*/gfx::Rect(size)};
  return true;
}

gfx::Size ParcVideoToolboxMpegVideoDecoder::GetPicSize() const {
  return size_;
}

gfx::Rect ParcVideoToolboxMpegVideoDecoder::GetVisibleRect() const {
  return gfx::Rect(size_);
}

VideoCodecProfile ParcVideoToolboxMpegVideoDecoder::GetProfile() const {
  return VIDEO_CODEC_PROFILE_UNKNOWN;
}

uint8_t ParcVideoToolboxMpegVideoDecoder::GetBitDepth() const {
  return 8;
}

VideoChromaSampling ParcVideoToolboxMpegVideoDecoder::GetChromaSampling()
    const {
  return session_metadata_.chroma_sampling;
}

VideoColorSpace ParcVideoToolboxMpegVideoDecoder::GetVideoColorSpace() const {
  return VideoColorSpace();
}

size_t ParcVideoToolboxMpegVideoDecoder::GetRequiredNumOfPictures() const {
  // Two reference pictures and the one being decoded.
  return 3;
}

size_t ParcVideoToolboxMpegVideoDecoder::GetNumReferenceFrames() const {
  return 2;
}

}  // namespace media
