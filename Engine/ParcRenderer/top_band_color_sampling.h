// Copyright 2026 Parc contributors.
#ifndef THIRD_PARTY_BLINK_PUBLIC_COMMON_PARC_TOP_BAND_COLOR_SAMPLING_H_
#define THIRD_PARTY_BLINK_PUBLIC_COMMON_PARC_TOP_BAND_COLOR_SAMPLING_H_

//
// the renderer's TopBandColorTracker and the browser's frame sampler.
//

#include <algorithm>
#include <array>
#include <bit>
#include <cmath>
#include <cstdint>
#include <optional>
#include <string_view>

namespace parc::top_band {

// The renderer samples an image's first 8 rows and skips its right 24
// pixels; the browser samples the composited frame's top 8 DIP and skips the
// right 24 DIP (0x40c04c0: both scaled by the device scale factor).
inline constexpr int kBandRows = 8;
inline constexpr int kRightMargin = 24;
// A sample point's element must be at least this tall (0x4686a2c: 10 < h).
inline constexpr int kMinimumBandHeight = 11;
// FireDetection's throttle (0x4684a40: 100000 us).
inline constexpr int kDetectionIntervalMs = 100;
// SameElementAsLastSample's window (0x4686b58: < 0x16e361 us).
inline constexpr int kSameElementWindowUs = 1500001;
// Generated backgrounds are rasterised at most this large (0x46862e8).
inline constexpr int kMaximumRasterSize = 800;

// SkColor channel distance in RGB, each channel scaled to 0..1; alpha is
// ignored.
inline float ChannelDistance(uint32_t a, uint32_t b) {
  auto channel = [](uint32_t c, int shift) {
    return static_cast<int>((c >> shift) & 0xff);
  };
  const float red = (channel(a, 16) - channel(b, 16)) / 255.0f;
  const float green = (channel(a, 8) - channel(b, 8)) / 255.0f;
  const float blue = (channel(a, 0) - channel(b, 0)) / 255.0f;
  return std::sqrt(red * red + green * green + blue * blue);
}

// 0x40c05c0. Five samples across row 0 and five across row min(rows, h) - 1,
// at x = i/4 of (width - right_margin). Identical samples give that colour,
// a spread above 0.5 gives none, anything else averages row 0's samples.
// `pixel_at(x, y)` returns an unpremultiplied SkColor.
template <typename PixelAt>
std::optional<uint32_t> SampleBand(int width,
                                   int height,
                                   int rows,
                                   int right_margin,
                                   PixelAt pixel_at) {
  if (width < 1 || height < 1) {
    return std::nullopt;
  }
  const int band = std::min(rows, height);
  const float span = static_cast<float>(std::max(width - right_margin, 0));
  auto column = [&](int i) {
    const int x = static_cast<int>((i / 4.0f) * span);
    return x < 0 ? 0 : std::min(width - 1, x);
  };
  const int lower_row = band - 1 < 0 ? 0 : std::min(height - 1, band - 1);
  std::array<uint32_t, 5> top{};
  std::array<uint32_t, 5> lower{};
  for (int i = 0; i < 5; ++i) {
    top[i] = pixel_at(column(i), 0);
  }
  for (int i = 0; i < 5; ++i) {
    lower[i] = pixel_at(column(i), lower_row);
  }
  float spread = 0;
  for (int i = 1; i < 5; ++i) {
    for (int j = 0; j < i; ++j) {
      spread = std::max(spread, ChannelDistance(top[j], top[i]));
    }
  }
  spread = std::max(spread, ChannelDistance(top[0], lower[0]));
  spread = std::max(spread, ChannelDistance(top[4], lower[4]));
  if (spread == 0) {
    return top[0];
  }
  if (spread > 0.5f) {
    return std::nullopt;
  }
  uint32_t average = 0;
  for (int shift : {0, 8, 16, 24}) {
    float sum = 0;
    for (uint32_t sample : top) {
      sum += static_cast<float>((sample >> shift) & 0xff);
    }
    const float rounded = std::round(sum / 5.0f);
    const uint32_t value =
        rounded <= -1 ? 0 : (rounded > 255 ? 255 : static_cast<uint32_t>(rounded));
    average |= value << shift;
  }
  return average;
}

// 0x4686a2c's geometry: an element counts for a sample point when it is at
// least kMinimumBandHeight tall, at least a third of the viewport wide, and
//
// feature (off by default) also accepts one covering all three inner sample
// columns; Parc keeps the default.
inline bool SpansBand(int x, int width, int height, int viewport_width) {
  if (height < kMinimumBandHeight || width < viewport_width / 3) {
    return false;
  }
  return viewport_width <= x + width || x < 1;
}

// Detection's sample points: x = i * (viewport_width / 4) for i in 0..3, at
// y = 1 (0x46850c8, in LayoutUnits of 1/64 px).
inline int SampleColumn(int index, int viewport_width) {
  return index * (viewport_width / 4);
}

// Parc: what decides an element's pixels, folded in the order the renderer
// reads its images: each image's identity and whether it has finished
// loading, and for a generated image its value and what it is drawn with.
// Restyles that leave these alone keep the value; a finished load changes it.
class PixelSource {
 public:
  void AddImage(const void* identity, bool loaded) {
    Add(reinterpret_cast<uintptr_t>(identity));
    Add(loaded ? 1 : 2);
  }
  // `value_hash` hashes the generated image's CSS value; `width` and
  // `height` are the capped raster size; `color`, `color_scheme` and `zoom`
  // are the style inputs a gradient resolves.
  void AddGenerated(uint32_t value_hash,
                    int width,
                    int height,
                    uint32_t color,
                    int color_scheme,
                    float zoom) {
    Add(3);
    Add(value_hash);
    Add(static_cast<uint32_t>(width));
    Add(static_cast<uint32_t>(height));
    Add(color);
    Add(static_cast<uint32_t>(color_scheme));
    Add(std::bit_cast<uint32_t>(zoom));
  }
  uint64_t value() const { return value_; }

 private:
  void Add(uint64_t part) {
    uint64_t x = value_ ^ part;
    x = (x ^ (x >> 30)) * 0xbf58476d1ce4e5b9ull;
    x = (x ^ (x >> 27)) * 0x94d049bb133111ebull;
    value_ = x ^ (x >> 31);
  }
  uint64_t value_ = 0x9e3779b97f4a7c15ull;
};

// Parc: elements whose pixels were read in this detection, and elements whose
// pixels recently gave no colour, so a failing image or gradient is not
//
// re-reads them each time. A key is an element's node id and its
// PixelSource value; a failure is remembered for kSameElementWindowUs.
class PixelSampleMemory {
 public:
  struct Key {
    int64_t node = 0;
    uint64_t source = 0;
    bool operator==(const Key&) const = default;
  };
  static constexpr size_t kRememberedFailures = 4;

  // A new detection pass.
  void BeginPass() { pass_count_ = 0; }
  // A new document or contentful paint: every element may be read again.
  void Forget() { *this = PixelSampleMemory(); }

  // `key`'s colour: this pass's earlier result, nothing for a recent
  // failure, else `sample()`, an optional SkColor.
  template <typename Sample>
  std::optional<uint32_t> Color(const Key& key, int64_t now_us,
                                Sample sample) {
    for (size_t i = 0; i < pass_count_; ++i) {
      if (pass_[i].key == key) {
        return pass_[i].color;
      }
    }
    std::optional<uint32_t> color;
    bool failed_recently = false;
    for (const Failure& failure : failures_) {
      if (failure.key == key && failure.at_us &&
          now_us - failure.at_us < kSameElementWindowUs) {
        failed_recently = true;
      }
    }
    if (!failed_recently) {
      color = sample();
      if (!color) {
        // The key's own slot, else the oldest.
        auto slot = std::find_if(failures_.begin(), failures_.end(),
                                 [&key](const Failure& f) { return f.key == key; });
        if (slot == failures_.end()) {
          slot = std::min_element(failures_.begin(), failures_.end(),
                                  [](const Failure& a, const Failure& b) {
                                    return a.at_us < b.at_us;
                                  });
        }
        *slot = Failure{key, now_us};
      }
    }
    if (pass_count_ < pass_.size()) {
      pass_[pass_count_++] = Result{key, color};
    }
    return color;
  }

 private:
  struct Result {
    Key key;
    std::optional<uint32_t> color;
  };
  struct Failure {
    Key key;
    int64_t at_us = 0;
  };
  // At most one element per sample point and node in the band's hit lists;
  // later elements in a pass are simply read again.
  std::array<Result, 32> pass_{};
  size_t pass_count_ = 0;
  std::array<Failure, kRememberedFailures> failures_{};
};

//
// Entry>), keyed by element. Parc keeps insertion order, so ties go to the
//
template <typename Key, typename Color>
class BandVotes {
 public:
  struct Vote {
    Key key{};
    Color color{};
    bool sample_frame = false;
    int64_t frame_sample_id = 0;
    int count = 0;
  };
  // A point's vote for `key`'s colour, or for a sample of the frame.
  void ForColor(const Key& key, const Color& color) {
    Vote& vote = For(key);
    vote.color = color;
    ++vote.count;
  }
  void ForFrameSample(const Key& key, int64_t id) {
    Vote& vote = For(key);
    vote.sample_frame = true;
    vote.frame_sample_id = id;
    ++vote.count;
  }
  // A point whose hit list voted for nothing, over an opaque canvas.
  void ForCanvas() { ++canvas_votes_; }
  // The element with the most votes, the first on a tie.
  const Vote* Winner() const {
    const Vote* winner = nullptr;
    for (size_t i = 0; i < count_; ++i) {
      if (!winner || votes_[i].count > winner->count) {
        winner = &votes_[i];
      }
    }
    return winner;
  }
  int canvas_votes() const { return canvas_votes_; }

 private:
  Vote& For(const Key& key) {
    for (size_t i = 0; i < count_; ++i) {
      if (votes_[i].key == key) {
        return votes_[i];
      }
    }
    if (count_ == votes_.size()) {
      return overflow_;
    }
    votes_[count_].key = key;
    return votes_[count_++];
  }
  // Four sample points vote at most four times.
  std::array<Vote, 4> votes_{};
  Vote overflow_;
  size_t count_ = 0;
  int canvas_votes_ = 0;
};

// What a detection reports from its votes (0x46858e0–0x46859c0). Without a
// colour or a frame sample the caller falls back to the document background.
template <typename Color>
struct BandChoice {
  std::optional<Color> color;
  bool sample_frame = false;
  int64_t frame_sample_id = 0;
  bool reuse_frame_sample = false;
};

// A frame-sample winner always wins. Otherwise the winner's colour, unless
// the opaque canvas background has more votes; `reuse_frame_sample` marks a
// skipped pixel element while scrolled.
template <typename Key, typename Color>
BandChoice<Color> ChooseBand(const BandVotes<Key, Color>& votes,
                             const std::optional<Color>& canvas,
                             bool reuse_frame_sample) {
  BandChoice<Color> choice;
  const auto* winner = votes.Winner();
  if (winner && winner->sample_frame) {
    choice.sample_frame = true;
    choice.frame_sample_id = winner->frame_sample_id;
    return choice;
  }
  choice.reuse_frame_sample = reuse_frame_sample;
  if (winner) {
    choice.color = winner->color;
  }
  if (canvas && (winner ? winner->count : 0) < votes.canvas_votes()) {
    choice.color = canvas;
  }
  return choice;
}

// Parc: the host the browser reports with a colour, under which the shell
// caches it. Only a website (http or https) has one; Reader, extension and
//
// under its URL's host.
inline std::string_view CacheHost(std::string_view scheme,
                                  std::string_view host) {
  return scheme == "http" || scheme == "https" ? host : std::string_view();
}

// The browser's handling of a renderer sample (0x40c0094, 0x40c0124,
// 0x40c03f0). Colours are SkColor; an empty optional is "no colour".
class FrameSampleDelivery {
 public:
  struct Delivery {
    std::optional<uint32_t> color;
    bool crossfade = false;
  };
  struct Action {
    std::optional<Delivery> deliver;
    // Copy the frame's top band for this sample id.
    std::optional<int64_t> copy;
  };

  // A renderer message. `sample_frame` asks for the composited frame's
  // colour under `frame_sample_id`; `reuse_frame_sample` replaces the
  // renderer's colour with the last frame sample's.
  Action OnRendererSample(std::optional<uint32_t> color,
                          bool sample_frame,
                          int64_t frame_sample_id,
                          bool reuse_frame_sample,
                          bool crossfade) {
    if (!sample_frame) {
      pending_ = false;
      if (reuse_frame_sample && frame_sample_ && frame_sample_->color) {
        color = frame_sample_->color;
      }
      return {Deliver(color, crossfade), std::nullopt};
    }
    pending_ = true;
    pending_id_ = frame_sample_id;
    pending_crossfade_ = crossfade;
    if (copy_in_flight_) {
      return {};
    }
    return ResolvePending();
  }

  // A finished copy: the sampled colour of `id`'s frame, or nothing when the
  // copy failed or the band was mixed.
  Action OnFrameSample(int64_t id, std::optional<uint32_t> color) {
    if (!copy_in_flight_ || copy_id_ != id) {
      return {};
    }
    copy_in_flight_ = false;
    if (!pending_) {
      return {};
    }
    if (pending_id_ != id) {
      return ResolvePending();
    }
    pending_ = false;
    frame_sample_ = FrameSample{id, color};
    return {Deliver(color, pending_crossfade_), std::nullopt};
  }

  // The page had no view to copy: the request stays pending for the next
  // renderer message (0x40c025c).
  void CopyUnavailable() { copy_in_flight_ = false; }

  // A new document: forget the delivered colour and pending requests.
  void Reset() { *this = FrameSampleDelivery(); }

 private:
  struct FrameSample {
    int64_t id = 0;
    std::optional<uint32_t> color;
  };

  Action ResolvePending() {
    if (frame_sample_ && frame_sample_->id == pending_id_) {
      pending_ = false;
      return {Deliver(frame_sample_->color, pending_crossfade_), std::nullopt};
    }
    copy_in_flight_ = true;
    copy_id_ = pending_id_;
    return {std::nullopt, pending_id_};
  }

  // 0x40c0124 delivers only a change.
  std::optional<Delivery> Deliver(std::optional<uint32_t> color,
                                  bool crossfade) {
    if (delivered_ && delivered_color_ == color) {
      return std::nullopt;
    }
    delivered_ = true;
    delivered_color_ = color;
    return Delivery{color, crossfade};
  }

  bool delivered_ = false;
  std::optional<uint32_t> delivered_color_;
  bool pending_ = false;
  int64_t pending_id_ = 0;
  bool pending_crossfade_ = false;
  bool copy_in_flight_ = false;
  int64_t copy_id_ = 0;
  std::optional<FrameSample> frame_sample_;
};

}  // namespace parc::top_band

#endif  // THIRD_PARTY_BLINK_PUBLIC_COMMON_PARC_TOP_BAND_COLOR_SAMPLING_H_
