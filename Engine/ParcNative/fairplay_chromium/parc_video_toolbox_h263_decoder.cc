// Installed by the reviewed overlay at
// //media/gpu/mac/parc_video_toolbox_h263_decoder.cc (media/gpu/mac).

#include "media/gpu/mac/parc_video_toolbox_h263_decoder.h"

#include <utility>

#include "base/apple/osstatus_logging.h"
#include "base/containers/span.h"
#include "media/base/media_log.h"
#include "media/base/video_types.h"

namespace media {

ParcVideoToolboxH263Decoder::ParcVideoToolboxH263Decoder(
    std::unique_ptr<MediaLog> media_log,
    DecodeCB decode_cb,
    OutputCB output_cb,
    const gfx::Size& coded_size)
    : media_log_(std::move(media_log)),
      decode_cb_(std::move(decode_cb)),
      output_cb_(std::move(output_cb)),
      coded_size_(coded_size) {}

ParcVideoToolboxH263Decoder::~ParcVideoToolboxH263Decoder() = default;

void ParcVideoToolboxH263Decoder::SetStream(
    int32_t id,
    scoped_refptr<DecoderBuffer> decoder_buffer) {
  buffer_ = std::move(decoder_buffer);
}

bool ParcVideoToolboxH263Decoder::Flush() {
  // Every picture was output as it was submitted.
  return true;
}

void ParcVideoToolboxH263Decoder::Reset() {
  buffer_.reset();
}

AcceleratedVideoDecoder::DecodeResult ParcVideoToolboxH263Decoder::Decode() {
  scoped_refptr<DecoderBuffer> buffer = std::move(buffer_);
  if (!buffer || buffer->empty()) {
    return kRanOutOfStreamData;
  }

  if (!format_) {
    // The picture headers carry the size; VideoToolbox needs no other
    // configuration.
    OSStatus status = CMVideoFormatDescriptionCreate(
        kCFAllocatorDefault, kCMVideoCodecType_H263, coded_size_.width(),
        coded_size_.height(), /*extensions=*/nullptr, format_.InitializeInto());
    if (status != noErr) {
      OSSTATUS_MEDIA_LOG(ERROR, status, media_log_.get())
          << "CMVideoFormatDescriptionCreate()";
      return kDecodeError;
    }
  }

  // VideoToolbox decodes after this returns, so it gets its own copy.
  const base::span<const uint8_t> data = base::span(*buffer);
  base::apple::ScopedCFTypeRef<CMBlockBufferRef> block;
  OSStatus status = CMBlockBufferCreateWithMemoryBlock(
      /*structureAllocator=*/kCFAllocatorDefault,
      /*memoryBlock=*/nullptr,
      /*blockLength=*/data.size(),
      /*blockAllocator=*/kCFAllocatorDefault,
      /*customBlockSource=*/nullptr,
      /*offsetToData=*/0,
      /*dataLength=*/data.size(),
      /*flags=*/kCMBlockBufferAssureMemoryNowFlag, block.InitializeInto());
  if (status != noErr) {
    OSSTATUS_MEDIA_LOG(ERROR, status, media_log_.get())
        << "CMBlockBufferCreateWithMemoryBlock()";
    return kDecodeError;
  }
  status = CMBlockBufferReplaceDataBytes(data.data(), block.get(), 0,
                                         data.size());
  if (status != noErr) {
    OSSTATUS_MEDIA_LOG(ERROR, status, media_log_.get())
        << "CMBlockBufferReplaceDataBytes()";
    return kDecodeError;
  }

  base::apple::ScopedCFTypeRef<CMSampleBufferRef> sample;
  const size_t size = data.size();
  status = CMSampleBufferCreate(
      /*allocator=*/kCFAllocatorDefault,
      /*dataBuffer=*/block.get(),
      /*dataReady=*/true,
      /*makeDataReadyCallback=*/nullptr,
      /*makeDataReadyRefcon=*/nullptr,
      /*formatDescription=*/format_.get(),
      /*numSamples=*/1,
      /*numSampleTimingEntries=*/0,
      /*sampleTimingArray=*/nullptr,
      /*numSampleSizeEntries=*/1,
      /*sampleSizeArray=*/&size, sample.InitializeInto());
  if (status != noErr) {
    OSSTATUS_MEDIA_LOG(ERROR, status, media_log_.get())
        << "CMSampleBufferCreate()";
    return kDecodeError;
  }

  auto picture = base::MakeRefCounted<CodecPicture>();
  picture->set_visible_rect(GetVisibleRect());
  decode_cb_.Run(std::move(sample),
                 VideoToolboxDecompressionSessionMetadata{
                     // macOS has no H.263 hardware decoder.
                     /*allow_software_decoding=*/true,
                     /*bit_depth=*/8,
                     /*chroma_sampling=*/VideoChromaSampling::k420,
                     /*has_alpha=*/false,
                     /*visible_rect=*/GetVisibleRect()},
                 picture);
  output_cb_.Run(std::move(picture));
  return kRanOutOfStreamData;
}

gfx::Size ParcVideoToolboxH263Decoder::GetPicSize() const {
  return coded_size_;
}

gfx::Rect ParcVideoToolboxH263Decoder::GetVisibleRect() const {
  return gfx::Rect(coded_size_);
}

VideoCodecProfile ParcVideoToolboxH263Decoder::GetProfile() const {
  return VIDEO_CODEC_PROFILE_UNKNOWN;
}

uint8_t ParcVideoToolboxH263Decoder::GetBitDepth() const {
  return 8;
}

VideoChromaSampling ParcVideoToolboxH263Decoder::GetChromaSampling() const {
  return VideoChromaSampling::k420;
}

VideoColorSpace ParcVideoToolboxH263Decoder::GetVideoColorSpace() const {
  // H.263 codes ITU-R BT.601 pictures.
  return VideoColorSpace::REC601();
}

size_t ParcVideoToolboxH263Decoder::GetRequiredNumOfPictures() const {
  return 1;
}

size_t ParcVideoToolboxH263Decoder::GetNumReferenceFrames() const {
  return 1;
}

}  // namespace media
