// FairPlay-capable sample-buffer playback, shaped like media::Renderer: a
// video AVSampleBufferDisplayLayer and an AVSampleBufferAudioRenderer under an
// AVSampleBufferRenderSynchronizer. Encrypted samples are enqueued still
// encrypted, as protected CMSampleBuffers (FairPlay sample entry type, 'tenc'
// and 'sinf' in the format description, subsample and IV attachments); both
// renderers are content key recipients of the CDM's AVContentKeySession and
// decrypt with its keys, matched by the format description's key ID.
// Decryption and decode happen inside AVFoundation's protected path.
#pragma once

#include <cstdint>
#include <functional>
#include <memory>
#include <optional>
#include <string>

#include "fairplay_types.h"

namespace parc::fairplay {

class FairPlayCdm;

enum class StreamType { kAudio, kVideo };

enum class RenderingStatus { kUnknown, kRendering, kFailed };

enum class RendererError {
  kConfiguration,  // A format description or sample buffer couldn't be built.
  kDecode,         // The renderer failed to decode (status failed or
                   // a did-fail-to-decode notification).
};

enum class EnqueueResult {
  kEnqueued,
  // Held until the CDM reports a usable key for it; later samples of the same
  // stream queue behind it. Not an error.
  kWaitingForKey,
  kRejected,
};

// media::RendererClient's relevant callbacks.
class FairPlayRendererClient {
 public:
  virtual ~FairPlayRendererClient() = default;
  // |stream| can take more data: enqueue until IsReadyForMoreData() is false.
  virtual void OnNeedData(StreamType stream) = 0;
  // media::WaitingReason::kNoDecryptionKey. Held samples go out by themselves
  // once the key arrives.
  virtual void OnWaitingForKey() = 0;
  virtual void OnEnded() = 0;
  virtual void OnError(RendererError error, const std::string& description) = 0;
  virtual void OnVideoNaturalSizeChange(int32_t width, int32_t height) = 0;
  // media::BUFFERING_HAVE_ENOUGH once every configured renderer has enough
  // data for a reliable start (a stream at end of stream counts once none of
  // its samples wait for a key); BUFFERING_HAVE_NOTHING when the clock reaches
  // the end of a stream's data before its end of stream, or before samples
  // held for a key behind it go out (underflow). On underflow the renderer
  // stops its clock and restarts it at the playback rate once it has enough
  // again. Flush resets to HAVE_NOTHING silently.
  virtual void OnBufferingStateChange(bool have_enough) = 0;
};

struct RendererStatus {
  RenderingStatus video = RenderingStatus::kUnknown;
  RenderingStatus audio = RenderingStatus::kUnknown;
  std::string video_error;
  std::string audio_error;
  bool video_requires_flush = false;
  bool output_obscured = false;  // Insufficient external protection.
  bool video_ready_for_display = false;  // macOS 14.4+.
  bool video_has_enough = false;
  bool audio_has_enough = false;
  float audio_volume = 1;
  bool audio_muted = false;
  uint64_t video_enqueued = 0;
  uint64_t audio_enqueued = 0;
  uint64_t protected_enqueued = 0;
  uint64_t decode_failures = 0;
  uint64_t audio_automatic_flushes = 0;
  uint64_t video_decoder_resets = 0;  // Flushes for requiresFlushToResumeDecoding.
  uint64_t redelivered = 0;  // Samples enqueued again after either.
  float rate = 0;
  MediaTime time;
  // Media subtypes of the clear format description and of the protected one
  // used last (the config's key ID until a protected sample arrives), e.g.
  // 'avc1' and 'qavc'; 0 when absent.
  uint32_t video_format = 0;
  uint32_t video_protected_format = 0;
  uint32_t audio_format = 0;
  uint32_t audio_protected_format = 0;
};

struct VideoMetrics {
  // AVFoundation's counts, cumulative for the renderer's lifetime (Flush
  // doesn't reset them); total includes frames decoded ahead of the clock and
  // the ones decoded without display before a start time. macOS 14.4+.
  bool available = false;
  int64_t total_frames = 0;
  int64_t dropped_frames = 0;
  int64_t corrupted_frames = 0;
  int64_t optimized_composited_frames = 0;
  double accumulated_frame_delay = 0;
  // The core's own count on every macOS version: video samples given to
  // AVFoundation whose presentation time the clock has reached, since
  // Initialize. It stops with the clock (pause, underflow) and leaves out
  // samples a Flush dropped before they came due.
  int64_t frames_passed = 0;
};

class FairPlayRenderer {
 public:
  FairPlayRenderer(FairPlayRendererClient* client, PostTask post_task);
  ~FairPlayRenderer();
  FairPlayRenderer(const FairPlayRenderer&) = delete;
  FairPlayRenderer& operator=(const FairPlayRenderer&) = delete;

  // Builds the format descriptions and renderers. At least one config. Takes
  // Chromium's configs as they are: empty video records and AC-3/E-AC-3
  // boxes are built from the first keyframe or syncframe, and encryption
  // may carry only the scheme.
  Result Initialize(const std::optional<VideoConfig>& video,
                    const std::optional<AudioConfig>& audio);

  // A new decoder config for the samples enqueued from now on (Chromium's
  // DemuxerStream kConfigChanged). Video records are also rebuilt by
  // themselves when a keyframe carries different parameter sets or AV1
  // sequence header; audio changes the bitstream can't signal (a new
  // AudioSpecificConfig) need this call.
  Result Reconfigure(const VideoConfig& config);
  Result Reconfigure(const AudioConfig& config);

  // Joins the renderers to |cdm|'s AVContentKeySession as content key
  // recipients (borrowed; call SetCdm(nullptr) before destroying it). May come
  // before Initialize (Chromium's order when MediaKeys were set first; the
  // CDM is attached when the renderers exist) or after it, but before the
  // first Enqueue, and can't move to another CDM afterwards: AVFoundation
  // allows recipients to join one session, before they process media, and
  // SetCdm(nullptr) leaves them unable to decrypt. Setting the same CDM again
  // is a no-op.
  Result SetCdm(FairPlayCdm* cdm);

  // The AVSampleBufferDisplayLayer to composite, borrowed. Nonnull once
  // Initialize succeeded with a video config.
  void* display_layer() const;

  bool IsReadyForMoreData(StreamType stream) const;

  // Copies the sample into a CMSampleBuffer. Annex B video and ADTS audio are
  // reframed (with subsamples adjusted) as the config declares.
  EnqueueResult Enqueue(StreamType stream, const EncodedSample& sample);

  // No more samples for |stream| until Flush. OnEnded fires when the
  // synchronizer reaches the end of every configured stream.
  void SetEndOfStream(StreamType stream);

  // Sets the media time (rate stays 0 until SetPlaybackRate). Video samples
  // before |time| are decoded but not displayed.
  void StartPlayingFrom(MediaTime time);
  void SetPlaybackRate(double rate);
  // HTMLMediaElement.preservesPitch (true until set): with the rate, picks
  // the audio renderer's pitch algorithm as WebKit does.
  void SetPreservesPitch(bool preserves_pitch);
  void SetVolume(float volume);
  void SetMuted(bool muted);
  // Core Audio device UID for the audio output (HTMLMediaElement.setSinkId).
  // Empty keeps following the system default until a device has been named;
  // after that it picks the default device of the moment (AVFoundation takes
  // no "follow the default" value once a device was set). The audio renderer
  // flushes itself on a switch, and the queued samples are delivered again.
  Result SetAudioOutputDevice(const std::string& unique_id);

  // Stops playback, drops everything enqueued or held, and clears end of
  // stream. |done| runs on the owner sequence.
  void Flush(std::function<void()> done);

  // Callable from any thread (Chromium's TimeSource is read off the owner
  // sequence); everything else runs on the owner sequence.
  MediaTime GetMediaTime() const;
  RendererStatus GetStatus() const;
  // Not const: it brings frames_passed up to the clock. |done| runs on the
  // owner sequence.
  void LoadVideoMetrics(std::function<void(const VideoMetrics&)> done);

  class Impl;

 private:
  std::shared_ptr<Impl> impl_;
};

}  // namespace parc::fairplay
