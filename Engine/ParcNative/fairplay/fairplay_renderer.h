// FairPlay-capable sample-buffer playback, shaped like media::Renderer: a
// video AVSampleBufferDisplayLayer and an AVSampleBufferAudioRenderer per audio
// track under an AVSampleBufferRenderSynchronizer. Encrypted samples are enqueued still
// encrypted, as protected CMSampleBuffers (FairPlay sample entry type, 'tenc'
// and 'sinf' in the format description, subsample and IV attachments); the
// renderers are content key recipients of the CDM's AVContentKeySession and
// decrypt with its keys, matched by the format description's key ID.
// Decryption and decode happen inside AVFoundation's protected path.
#pragma once

#include <cstdint>
#include <functional>
#include <memory>
#include <optional>
#include <string>
#include <vector>

#include "fairplay_types.h"

namespace parc::fairplay {

class FairPlayCdm;

enum class StreamType { kAudio, kVideo };

// One of the renderer's streams: its video, or one of its audio tracks. Each
// audio track has its own AVSampleBufferAudioRenderer, and they play mixed, as
// WebKit's AudioVideoRendererAVFObjC keeps one per enabled track. Initialize's
// audio is track 0, so StreamType::kAudio names it.
struct StreamId {
  StreamId(StreamType type, uint32_t audio_track = 0) : type(type), audio_track(audio_track) {}
  bool operator==(const StreamId& other) const {
    return type == other.type && (type == StreamType::kVideo || audio_track == other.audio_track);
  }
  StreamType type;
  uint32_t audio_track;  // Audio only.
};

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
  virtual void OnNeedData(StreamId stream) = 0;
  // media::WaitingReason::kNoDecryptionKey. Held samples go out by themselves
  // once the key arrives.
  virtual void OnWaitingForKey() = 0;
  virtual void OnEnded() = 0;
  virtual void OnError(RendererError error, const std::string& description) = 0;
  virtual void OnVideoNaturalSizeChange(int32_t width, int32_t height) = 0;
  // media::BUFFERING_HAVE_ENOUGH as WebKit's MediaSource sets readyState,
  // from the data given whether or not keys are usable: every configured
  // stream reached end of stream, was given samples (enqueued or held for a
  // key) 3 s past the clock, or has a renderer with enough for a reliable
  // start. After start/seek/reset video also waits for a decoded frame.
  // The clock runs from then once every renderer also has samples to
  // play (so it waits for keys at the start, but samples held for a key later
  // don't stop it: the picture freezes and time runs on, as in Safari).
  // BUFFERING_HAVE_NOTHING only when the clock reaches the end of what a
  // stream without end of stream was given (a stall at the buffered end); the
  // clock stops there and restarts at HAVE_ENOUGH. A stream added during
  // playback (AddVideo, AddAudio) reports HAVE_NOTHING too, until it has
  // enough. Flush resets to HAVE_NOTHING silently.
  virtual void OnBufferingStateChange(bool have_enough) = 0;
};

// The audio fields describe the first audio track; the counts cover them all.
struct RendererStatus {
  RenderingStatus video = RenderingStatus::kUnknown;
  RenderingStatus audio = RenderingStatus::kUnknown;
  size_t audio_renderers = 0;
  std::string video_error;
  std::string audio_error;
  bool video_requires_flush = false;
  bool output_obscured = false;  // Insufficient external protection.
  bool video_ready_for_display = false;  // Display notification or legacy preroll.
  bool video_has_enough = false;
  bool audio_has_enough = false;
  float audio_volume = 1;
  bool audio_muted = false;
  // The audioOutputDeviceUniqueID of every audio renderer still playing,
  // outgoing ones included; empty while one follows the system default.
  std::vector<std::string> audio_output_devices;
  uint64_t video_enqueued = 0;
  uint64_t audio_enqueued = 0;
  uint64_t protected_enqueued = 0;
  uint64_t decode_failures = 0;
  uint64_t audio_automatic_flushes = 0;
  uint64_t video_decoder_resets = 0;  // Flushes for requiresFlushToResumeDecoding.
  uint64_t redelivered = 0;  // Samples enqueued again after either.
  // Audio samples enqueued while more than half of them was already in the
  // renderer since its last flush, which plays them twice. 0 unless a page
  // appends over audio already read in a misaligned frame grid.
  uint64_t audio_double_enqueues = 0;
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
  Result Reconfigure(const AudioConfig& config, uint32_t audio_track = 0);

  // A stream that joins after Initialize, as WebKit's AudioVideoRendererAVFObjC
  // adds a display layer or audio renderer to its synchronizer for a track
  // enabled during playback (addTrack). The other renderers, the layer and
  // the clock's time stay; the clock waits until the new stream has samples
  // (and video a decoded frame), samples before the current time aren't
  // shown, and it joins the CDM's key session if one is set. AddVideo fails
  // when there is video already; AddAudio names the new track in |track|.
  Result AddVideo(const VideoConfig& config);
  Result AddAudio(const AudioConfig& config, uint32_t* track);
  // Another video track replaces the one playing (a video track switch), fed
  // from the keyframe before the current time. The picture stays until the
  // new track's frame at the current time decodes, the clock waiting for it,
  // as WebKit's AudioVideoRendererAVFObjC flushes its video renderer for a
  // new track; the display layer, the audio and the buffering state stay.
  Result ReplaceVideo(const VideoConfig& config);
  // Takes an audio track's renderer off the synchronizer, dropping what it
  // holds (AudioVideoRendererAVFObjC::removeAudioRenderer).
  void RemoveAudio(uint32_t track);

  // Joins the renderers to |cdm|'s AVContentKeySession as content key
  // recipients (borrowed; call SetCdm(nullptr) before destroying it); streams
  // added later join it as they are created. May come before Initialize
  // (Chromium's order when MediaKeys were set first; the CDM is attached when
  // the renderers exist) or after it. AVFoundation takes recipients only
  // before they process media, so once samples were enqueued new renderers
  // join instead and take over on the same clock: they get the samples the
  // others hold, the display layer with a frame from the keyframe before the
  // current time, and each audio renderer from a sample a moment ahead, where
  // the one it replaces leaves. The picture, the sound and the clock carry on
  // as WebKit's per-sample keys let Safari's. Another CDM (MediaKeys replaced
  // during playback) takes new renderers the same way, since a recipient
  // can't move between key sessions: the outgoing ones keep the old CDM's
  // keys until they leave, so it must outlive them (until this renderer is
  // destroyed), and samples the new CDM has no key for are held.
  // SetCdm(nullptr) leaves the recipients unable to decrypt. Setting the same
  // CDM again is a no-op, except after DetachCdm, which it undoes.
  Result SetCdm(FairPlayCdm* cdm);

  // setMediaKeys(null) during playback, as WebKit's renderer takes it
  // (AudioVideoRendererAVFObjC::setCDMInstance(nullptr)): samples already
  // given to AVFoundation play out with their keys, clear samples go on, and
  // every protected sample from now on, including one a flush makes the
  // renderer deliver again, is held (kWaitingForKey) until SetCdm sets the
  // same CDM again. The renderers stay recipients of its key session, which
  // they can't leave or change once they processed media (above), so another
  // CDM takes another renderer.
  void DetachCdm();

  // The CALayer to composite, borrowed: it holds the
  // AVSampleBufferDisplayLayer, which SetCdm may replace inside it, filling
  // its bounds. Nonnull once Initialize or AddVideo succeeded with a video
  // config.
  void* display_layer() const;
  // Clears the picture, before the compositor may keep showing the layer
  // until its next commit (teardown).
  void RemoveDisplayedImage();

  bool IsReadyForMoreData(StreamId stream) const;

  // Copies the sample into a CMSampleBuffer. Annex B video and ADTS audio are
  // reframed (with subsamples adjusted) as the config declares.
  EnqueueResult Enqueue(StreamId stream, const EncodedSample& sample);

  // No more samples for |stream| until Flush. OnEnded fires when the
  // synchronizer reaches the end of every configured stream.
  void SetEndOfStream(StreamId stream);

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
