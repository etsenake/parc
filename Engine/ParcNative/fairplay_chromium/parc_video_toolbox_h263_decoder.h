// Installed by the reviewed overlay at
// //media/gpu/mac/parc_video_toolbox_h263_decoder.h (media/gpu/mac). 3GPP's
// H.263 video for VideoToolboxVideoDecoder, which macOS decodes in software,
// as Safari plays it. Only Safari-identity pages produce H.263 configs
// (MP4StreamParser under Safari's init segment rules,
// FFmpegDemuxer::ParcSetSafariCodecs()).

#ifndef MEDIA_GPU_MAC_PARC_VIDEO_TOOLBOX_H263_DECODER_H_
#define MEDIA_GPU_MAC_PARC_VIDEO_TOOLBOX_H263_DECODER_H_

#include <CoreMedia/CoreMedia.h>

#include <memory>

#include "base/apple/scoped_cftyperef.h"
#include "base/functional/callback.h"
#include "base/memory/scoped_refptr.h"
#include "media/gpu/accelerated_video_decoder.h"
#include "media/gpu/codec_picture.h"
#include "media/gpu/mac/video_toolbox_decompression_metadata.h"
#include "media/gpu/media_gpu_export.h"
#include "ui/gfx/geometry/size.h"

namespace media {

class MediaLog;

// A 3GPP H.263 sample is one picture, and pictures come out in decode order
// (3GPP's profiles 0 and 3 have no B pictures), so nothing is parsed: each
// buffer becomes one VideoToolbox sample and, at once, one output picture.
class MEDIA_GPU_EXPORT ParcVideoToolboxH263Decoder
    : public AcceleratedVideoDecoder {
 public:
  using DecodeCB = base::RepeatingCallback<void(
      base::apple::ScopedCFTypeRef<CMSampleBufferRef>,
      VideoToolboxDecompressionSessionMetadata,
      scoped_refptr<CodecPicture>)>;
  using OutputCB = base::RepeatingCallback<void(scoped_refptr<CodecPicture>)>;

  ParcVideoToolboxH263Decoder(std::unique_ptr<MediaLog> media_log,
                              DecodeCB decode_cb,
                              OutputCB output_cb,
                              const gfx::Size& coded_size);
  ~ParcVideoToolboxH263Decoder() override;

  // AcceleratedVideoDecoder implementation.
  void SetStream(int32_t id,
                 scoped_refptr<DecoderBuffer> decoder_buffer) override;
  bool Flush() override;
  void Reset() override;
  DecodeResult Decode() override;
  gfx::Size GetPicSize() const override;
  gfx::Rect GetVisibleRect() const override;
  VideoCodecProfile GetProfile() const override;
  uint8_t GetBitDepth() const override;
  VideoChromaSampling GetChromaSampling() const override;
  VideoColorSpace GetVideoColorSpace() const override;
  size_t GetRequiredNumOfPictures() const override;
  size_t GetNumReferenceFrames() const override;

 private:
  std::unique_ptr<MediaLog> media_log_;
  DecodeCB decode_cb_;
  OutputCB output_cb_;
  const gfx::Size coded_size_;
  base::apple::ScopedCFTypeRef<CMFormatDescriptionRef> format_;
  scoped_refptr<DecoderBuffer> buffer_;
};

}  // namespace media

#endif  // MEDIA_GPU_MAC_PARC_VIDEO_TOOLBOX_H263_DECODER_H_
