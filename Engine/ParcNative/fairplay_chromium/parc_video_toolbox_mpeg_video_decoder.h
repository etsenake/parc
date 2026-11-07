// Installed by the reviewed overlay at
// //media/gpu/mac/parc_video_toolbox_mpeg_video_decoder.h (media/gpu/mac).
// Parc: MPEG-1 and MPEG-2 video for VideoToolboxVideoDecoder, which only a
// Safari-identity page's Media Source gives it
// (media::mp2t::ParcEsParserMpegVideo). Safari's SourceBuffer decodes these
// samples with VideoToolbox through AVSampleBufferDisplayLayer, in software
// on Macs without an MPEG-2 decoder in hardware, as this does.

#ifndef MEDIA_GPU_MAC_PARC_VIDEO_TOOLBOX_MPEG_VIDEO_DECODER_H_
#define MEDIA_GPU_MAC_PARC_VIDEO_TOOLBOX_MPEG_VIDEO_DECODER_H_

#include <CoreMedia/CoreMedia.h>
#include <stdint.h>

#include <memory>

#include "base/apple/scoped_cftyperef.h"
#include "base/containers/span.h"
#include "base/functional/callback.h"
#include "base/memory/scoped_refptr.h"
#include "media/base/decoder_buffer.h"
#include "media/gpu/accelerated_video_decoder.h"
#include "media/gpu/codec_picture.h"
#include "media/gpu/mac/video_toolbox_decompression_metadata.h"
#include "media/gpu/media_gpu_export.h"
#include "ui/gfx/geometry/size.h"

namespace media {

class MediaLog;

// Submits each DecoderBuffer, one coded frame, as one sample whose format
// (MPEG-1 or MPEG-2 video, size, chroma format) comes from the latest
// sequence header, and outputs pictures in display order: a B-picture when
// decoded, an I- or P-picture when the next one is (ISO/IEC 13818-2 6.1.1.11)
// or at a flush.
class MEDIA_GPU_EXPORT ParcVideoToolboxMpegVideoDecoder
    : public AcceleratedVideoDecoder {
 public:
  using DecodeCB = base::RepeatingCallback<void(
      base::apple::ScopedCFTypeRef<CMSampleBufferRef>,
      VideoToolboxDecompressionSessionMetadata,
      scoped_refptr<CodecPicture>)>;
  using OutputCB = base::RepeatingCallback<void(scoped_refptr<CodecPicture>)>;

  // `extra_data` is the configuration's sequence header and extensions.
  ParcVideoToolboxMpegVideoDecoder(std::unique_ptr<MediaLog> media_log,
                                   DecodeCB decode_cb,
                                   OutputCB output_cb,
                                   base::span<const uint8_t> extra_data);

  ParcVideoToolboxMpegVideoDecoder(const ParcVideoToolboxMpegVideoDecoder&) =
      delete;
  ParcVideoToolboxMpegVideoDecoder& operator=(
      const ParcVideoToolboxMpegVideoDecoder&) = delete;

  ~ParcVideoToolboxMpegVideoDecoder() override;

  // AcceleratedVideoDecoder implementation.
  void SetStream(int32_t id, scoped_refptr<DecoderBuffer> buffer) override;
  [[nodiscard]] bool Flush() override;
  void Reset() override;
  [[nodiscard]] DecodeResult Decode() override;
  gfx::Size GetPicSize() const override;
  gfx::Rect GetVisibleRect() const override;
  VideoCodecProfile GetProfile() const override;
  uint8_t GetBitDepth() const override;
  VideoChromaSampling GetChromaSampling() const override;
  VideoColorSpace GetVideoColorSpace() const override;
  size_t GetRequiredNumOfPictures() const override;
  size_t GetNumReferenceFrames() const override;

 private:
  // Reads `data`'s sequence header and extension into the active format.
  bool ReadSequence(base::span<const uint8_t> data);

  std::unique_ptr<MediaLog> media_log_;

  // Callbacks are called synchronously, which is always re-entrant.
  DecodeCB decode_cb_;
  OutputCB output_cb_;

  scoped_refptr<DecoderBuffer> buffer_;

  // The latest I- or P-picture, until it is displayed.
  scoped_refptr<CodecPicture> held_anchor_;

  base::apple::ScopedCFTypeRef<CMFormatDescriptionRef> format_;
  CMVideoCodecType codec_type_ = 0;
  gfx::Size size_;
  VideoToolboxDecompressionSessionMetadata session_metadata_;
};

}  // namespace media

#endif  // MEDIA_GPU_MAC_PARC_VIDEO_TOOLBOX_MPEG_VIDEO_DECODER_H_
