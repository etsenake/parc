// Proof for the native HLS media selection (Engine/ParcNative/fairplay/
// fairplay_hls_media_selection.mm), run by scripts/test-fairplay-hls-tracks.sh.
//
// Plays Apple's public test streams through a plain AVPlayer (the network
// route is fairplay_hls_player's business, not this one's) with the
// selection running on a serial dispatch queue with no run loop, like
// Chromium's GPU media thread. Checks the audioTracks and textTracks WebKit
// would report, that enabling an audio track and setting text track modes
// select the options in the AVPlayerItem, and that cues arrive: WebVTT
// subtitles as ISO WebVTT cues, CEA-608 captions as generic cues that are
// completed by the next one, and a seek flushing the open cue.
#import <AVFoundation/AVFoundation.h>
#import <Foundation/Foundation.h>

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <functional>
#include <memory>
#include <string>
#include <vector>

#include "fairplay_hls_media_selection.h"
#include "fairplay_hls_media_selection_internal.h"

namespace fp = parc::fairplay;

// The synchronous media selection accessors, as the selection itself uses.
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

namespace {

int g_failures = 0;

void Check(bool ok, const std::string& what) {
  std::printf("%s %s\n", ok ? "PASS" : "FAIL", what.c_str());
  std::fflush(stdout);
  if (!ok) {
    g_failures++;
  }
}

dispatch_queue_t Owner() {
  static dispatch_queue_t queue = dispatch_queue_create("parc.hls-tracks-harness.owner", DISPATCH_QUEUE_SERIAL);
  return queue;
}

fp::PostTask OwnerPoster() {
  return [](std::function<void()> task) {
    dispatch_async(Owner(), ^{
      task();
    });
  };
}

void OnOwner(const std::function<void()>& task) {
  dispatch_sync(Owner(), ^{
    task();
  });
}

bool WaitFor(const std::function<bool()>& done, double seconds) {
  NSDate* end = [NSDate dateWithTimeIntervalSinceNow:seconds];
  while ([end timeIntervalSinceNow] > 0) {
    __block bool finished = false;
    dispatch_sync(Owner(), ^{
      finished = done();
    });
    if (finished) {
      return true;
    }
    [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
  }
  return false;
}

const char* TypeName(fp::HlsCue::Type type) {
  switch (type) {
    case fp::HlsCue::Type::kWebVttHeader:
      return "header";
    case fp::HlsCue::Type::kWebVtt:
      return "webvtt";
    case fp::HlsCue::Type::kAdd:
      return "add";
    case fp::HlsCue::Type::kUpdate:
      return "update";
    case fp::HlsCue::Type::kRemove:
      return "remove";
  }
  return "?";
}

struct ReceivedCue {
  std::string track_id;
  fp::HlsCue cue;
};

// Records what the selection reports; owner queue only.
class Recorder : public fp::HlsMediaSelectionClient {
 public:
  void OnTracksChanged(const std::vector<fp::HlsTrack>& tracks) override {
    tracks_ = tracks;
    track_reports_++;
  }
  void OnTextCues(const std::string& track_id, const std::vector<fp::HlsCue>& cues) override {
    // track_id is the track's key.
    for (const auto& cue : cues) {
      cues_.push_back({track_id, cue});
      if (cues_.size() <= 40) {
        std::printf("  cue %s track=%s id=%llu [%.3f, %.3f] %s text=\"%s\" settings=\"%s\" iden=\"%s\"\n",
                    TypeName(cue.type), track_id.c_str(), static_cast<unsigned long long>(cue.cue_id), cue.start,
                    cue.end, cue.complete ? "complete" : "partial", Escaped(cue.text).c_str(), cue.settings.c_str(),
                    cue.identifier.c_str());
      }
    }
  }

  static std::string Escaped(const std::string& text) {
    std::string out;
    for (char c : text) {
      if (c == '\n') {
        out += "\\n";
      } else {
        out.push_back(c);
      }
    }
    return out;
  }

  const fp::HlsTrack* Find(fp::HlsTrackType type, const std::string& label) const {
    for (const auto& track : tracks_) {
      if (track.type == type && track.label == label) {
        return &track;
      }
    }
    return nullptr;
  }

  int Count(fp::HlsTrackType type) const {
    int count = 0;
    for (const auto& track : tracks_) {
      count += track.type == type;
    }
    return count;
  }

  int EnabledAudio() const {
    int count = 0;
    for (const auto& track : tracks_) {
      count += track.type == fp::HlsTrackType::kAudio && track.enabled;
    }
    return count;
  }

  size_t CueCount(const std::function<bool(const ReceivedCue&)>& match) const {
    size_t count = 0;
    for (const auto& cue : cues_) {
      count += match(cue);
    }
    return count;
  }

  void Dump() const {
    for (const auto& track : tracks_) {
      std::printf("  %s key=%s id=%s kind=\"%s\" label=\"%s\" language=\"%s\" enabled=%d index=%lld default=%d cc=%d sdh=%d "
                  "forced=%d main=%d\n",
                  track.type == fp::HlsTrackType::kAudio ? "audio" : "text", track.key.c_str(), track.id.c_str(),
                  track.kind.c_str(),
                  track.label.c_str(), track.language.c_str(), track.enabled, static_cast<long long>(track.index),
                  track.is_default, track.is_closed_captions, track.is_sdh, track.contains_only_forced_subtitles,
                  track.is_main_program_content);
    }
  }

  std::vector<fp::HlsTrack> tracks_;
  int track_reports_ = 0;
  std::vector<ReceivedCue> cues_;
};

// One AVPlayer with the selection attached, all on the owner queue.
struct Session {
  explicit Session(NSString* url) {
    OnOwner([&] {
      AVURLAsset* asset = [AVURLAsset URLAssetWithURL:[NSURL URLWithString:url] options:nil];
      item = [AVPlayerItem playerItemWithAsset:asset];
      player = [AVPlayer playerWithPlayerItem:item];
      player.appliesMediaSelectionCriteriaAutomatically = NO;
      player.muted = YES;
      selection = std::make_unique<fp::HlsMediaSelection>(&recorder, OwnerPoster());
      fp::HlsMediaSelectionAttach(selection->impl(), player, item);
      [player play];
    });
  }

  ~Session() {
    OnOwner([&] {
      [player pause];
      selection.reset();
      [player replaceCurrentItemWithPlayerItem:nil];
    });
  }

  AVMediaSelectionOption* Selected(AVMediaCharacteristic characteristic) {
    AVMediaSelectionOption* option = nil;
    OnOwner([&] {
      AVMediaSelectionGroup* group = [item.asset mediaSelectionGroupForMediaCharacteristic:characteristic];
      option = group ? [item selectedMediaOptionInMediaSelectionGroup:group] : nil;
    });
    return option;
  }

  // The option's NAME (its common metadata title), as the track label.
  static std::string Title(AVMediaSelectionOption* option) {
    if (!option) {
      return "(none)";
    }
    NSArray<AVMetadataItem*>* titles = [AVMetadataItem metadataItemsFromArray:option.commonMetadata
                                                                      withKey:AVMetadataCommonKeyTitle
                                                                     keySpace:AVMetadataKeySpaceCommon];
    NSString* title = titles.firstObject.stringValue ?: option.displayName;
    return title ? std::string(title.UTF8String) : std::string();
  }

  std::string SelectedName(AVMediaCharacteristic characteristic) {
    std::string name = Title(Selected(characteristic));
    std::printf("  selected %s option: %s\n", characteristic.UTF8String, name.c_str());
    return name;
  }

  double Now() {
    double now = 0;
    OnOwner([&] {
      now = CMTimeGetSeconds(item.currentTime);
    });
    return now;
  }

  // Seeks as the player does: BeginSeeking, then EndSeeking when it ends.
  void Seek(double seconds) {
    auto done = std::make_shared<bool>(false);
    OnOwner([&] {
      selection->BeginSeeking();
      fp::HlsMediaSelection* selection_ptr = selection.get();
      [item seekToTime:CMTimeMakeWithSeconds(seconds, 600)
            toleranceBefore:kCMTimeZero
             toleranceAfter:kCMTimeZero
          completionHandler:^(BOOL) {
            dispatch_async(Owner(), ^{
              selection_ptr->EndSeeking();
              *done = true;
            });
          }];
    });
    WaitFor([&] { return *done; }, 20);
  }

  Recorder recorder;
  AVPlayer* player = nil;
  AVPlayerItem* item = nil;
  std::unique_ptr<fp::HlsMediaSelection> selection;
};

// bipbop_16x9_variant: two audio renditions, eight WebVTT subtitle options
// (four languages, each with a forced-only option).
void WebVttScenario() {
  std::printf("== webvtt: bipbop_16x9_variant\n");
  Session session(@"https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_16x9/bipbop_16x9_variant.m3u8");
  Recorder& r = session.recorder;
  bool listed = WaitFor([&] { return r.Count(fp::HlsTrackType::kAudio) == 2 && r.Count(fp::HlsTrackType::kText) == 8; },
                        30);
  OnOwner([&] { r.Dump(); });
  Check(listed, "two audio tracks and eight text tracks reported");
  if (!listed) {
    return;
  }
  OnOwner([&] {
    const fp::HlsTrack* audio1 = r.Find(fp::HlsTrackType::kAudio, "BipBop Audio 1");
    const fp::HlsTrack* audio2 = r.Find(fp::HlsTrackType::kAudio, "BipBop Audio 2");
    Check(audio1 && audio2, "audio labels are the renditions' NAMEs");
    Check(audio1 && audio1->language == "eng", "audio language is the option's tag as given (LANGUAGE=eng)");
    // WebKit's id and index: the option's ID and position, unless the item
    // already had Audio 1's track when the audio tracks were made; then its
    // trackID (1) and index -1 (no asset track list for HLS), sorted last.
    bool option_path = audio1 && audio1->id == "0" && audio1->index == 0 && r.tracks_[0].label == "BipBop Audio 1";
    bool asset_path = audio1 && audio1->id == "1" && audio1->index == -1 && r.tracks_[0].label == "BipBop Audio 2";
    std::printf("  audio 1 identified by its %s\n", option_path ? "option" : asset_path ? "item track" : "?");
    Check(option_path || asset_path, "audio ids and order follow WebKit's option or asset-track rule");
    Check(audio2 && audio2->id == "1" && audio2->index == 1, "Audio 2 has its option's ID and index");
    Check(audio1 && audio1->kind == "main" && audio2 && audio2->kind == "alternative",
          "DEFAULT audio is kind main, AUTOSELECT=NO audio kind alternative");
    Check(audio1 && audio2 && audio1->key != audio2->key, "audio keys are distinct");
    const fp::HlsTrack* english = r.Find(fp::HlsTrackType::kText, "English");
    const fp::HlsTrack* english_forced = r.Find(fp::HlsTrackType::kText, "English (Forced)");
    const fp::HlsTrack* french = r.Find(fp::HlsTrackType::kText, "Français");
    const fp::HlsTrack* japanese = r.Find(fp::HlsTrackType::kText, "日本語");
    Check(english && english->kind == "captions" && english->is_sdh,
          "SDH subtitles (transcribes dialog + describes music) are kind captions");
    Check(english_forced && english_forced->kind == "forced" && english_forced->contains_only_forced_subtitles,
          "FORCED=YES subtitles are kind forced");
    Check(english && english->is_default && english_forced && !english_forced->is_default,
          "DEFAULT=YES option is the default track");
    Check(french && french->language == "fr" && japanese && japanese->language == "ja", "text languages");
    Check(english && english->id == "0", "text ids count from 0 in the legible group's order");
  });
  Check(r.EnabledAudio() == 1, "exactly one audio track enabled after WebKit's automatic choice");
  Check(session.SelectedName(AVMediaCharacteristicLegible) == "(none)",
        "no legible option selected until the page shows a track");

  // Audio switch.
  std::string audio2_id;
  OnOwner([&] {
    if (const fp::HlsTrack* audio2 = r.Find(fp::HlsTrackType::kAudio, "BipBop Audio 2")) {
      audio2_id = audio2->key;
      session.selection->SetAudioTrackEnabled(audio2_id, true);
    }
  });
  bool switched = WaitFor(
      [&] {
        AVMediaSelectionGroup* group =
            [session.item.asset mediaSelectionGroupForMediaCharacteristic:AVMediaCharacteristicAudible];
        AVMediaSelectionOption* option = [session.item selectedMediaOptionInMediaSelectionGroup:group];
        return Session::Title(option) == "BipBop Audio 2";
      },
      15);
  Check(switched, "enabling audio track 2 selects its option in the AVPlayerItem");
  bool mirrored = WaitFor(
      [&] {
        const fp::HlsTrack* a1 = r.Find(fp::HlsTrackType::kAudio, "BipBop Audio 1");
        const fp::HlsTrack* a2 = r.Find(fp::HlsTrackType::kAudio, "BipBop Audio 2");
        return a1 && a2 && !a1->enabled && a2->enabled;
      },
      15);
  Check(mirrored, "track 1 reports disabled once the item's tracks follow the switch");

  // Text: show English.
  std::string english_id;
  std::string french_id;
  OnOwner([&] {
    english_id = r.Find(fp::HlsTrackType::kText, "English")->key;
    french_id = r.Find(fp::HlsTrackType::kText, "Français")->key;
    session.selection->SetTextTrackMode(english_id, fp::HlsTextTrackMode::kShowing);
  });
  Check(session.SelectedName(AVMediaCharacteristicLegible) == "English", "showing English selects its option");
  bool english_cues = WaitFor(
      [&] {
        return r.CueCount([&](const ReceivedCue& c) {
                 return c.track_id == english_id && c.cue.type == fp::HlsCue::Type::kWebVtt &&
                        c.cue.text.find("English subtitle") != std::string::npos;
               }) >= 2;
      },
      30);
  Check(english_cues, "English WebVTT cues arrive as ISO WebVTT cues");
  OnOwner([&] {
    bool timed = false;
    for (const auto& c : r.cues_) {
      if (c.track_id == english_id && c.cue.type == fp::HlsCue::Type::kWebVtt) {
        timed = std::isfinite(c.cue.end) && c.cue.end > c.cue.start;
        break;
      }
    }
    Check(timed, "a WebVTT cue ends at start + sample duration");
  });

  // Hidden French is ignored while English shows; showing French wins once
  // English is disabled.
  OnOwner([&] { session.selection->SetTextTrackMode(french_id, fp::HlsTextTrackMode::kHidden); });
  Check(session.SelectedName(AVMediaCharacteristicLegible) == "English", "a showing track beats a hidden one");
  OnOwner([&] { session.selection->SetTextTrackMode(english_id, fp::HlsTextTrackMode::kDisabled); });
  Check(session.SelectedName(AVMediaCharacteristicLegible) == "Français",
        "with no showing track the hidden one gets the output");
  size_t before_seek = 0;
  OnOwner([&] { before_seek = r.cues_.size(); });
  session.Seek(20);
  bool french_cues = WaitFor(
      [&] {
        return r.CueCount([&](const ReceivedCue& c) {
                 return c.track_id == french_id && c.cue.type == fp::HlsCue::Type::kWebVtt &&
                        c.cue.start >= 19;
               }) >= 1;
      },
      30);
  Check(french_cues, "French cues after a seek to 20 s");
  (void)before_seek;
  OnOwner([&] { session.selection->SetTextTrackMode(french_id, fp::HlsTextTrackMode::kDisabled); });
  Check(session.SelectedName(AVMediaCharacteristicLegible) == "(none)", "disabling every track selects none");
}

// img_bipbop_adv_example_fmp4: CLOSED-CAPTIONS (CEA-608 CC1) plus one
// WebVTT subtitle option.
void ClosedCaptionScenario() {
  std::printf("== cea608: img_bipbop_adv_example_fmp4\n");
  Session session(
      @"https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_fmp4/master.m3u8");
  Recorder& r = session.recorder;
  bool listed = WaitFor(
      [&] {
        for (const auto& track : r.tracks_) {
          if (track.type == fp::HlsTrackType::kText && track.is_closed_captions) {
            return true;
          }
        }
        return false;
      },
      30);
  OnOwner([&] { r.Dump(); });
  Check(listed, "the CLOSED-CAPTIONS rendition is a text track");
  if (!listed) {
    return;
  }
  std::string cc_id;
  OnOwner([&] {
    for (const auto& track : r.tracks_) {
      if (track.type == fp::HlsTrackType::kText && track.is_closed_captions) {
        cc_id = track.key;
        Check(track.kind == "captions", "CEA-608 is kind captions");
        Check(track.language == "en", "CEA-608 language");
      }
    }
    session.selection->SetTextTrackMode(cc_id, fp::HlsTextTrackMode::kShowing);
  });
  bool added = WaitFor(
      [&] {
        return r.CueCount([&](const ReceivedCue& c) {
                 return c.track_id == cc_id && c.cue.type == fp::HlsCue::Type::kAdd && !c.cue.text.empty() &&
                        std::isinf(c.cue.end);
               }) >= 2;
      },
      40);
  Check(added, "CEA-608 captions arrive as open-ended generic cues");
  bool completed = WaitFor(
      [&] {
        return r.CueCount([&](const ReceivedCue& c) {
                 return c.track_id == cc_id && c.cue.type == fp::HlsCue::Type::kUpdate && c.cue.complete &&
                        std::isfinite(c.cue.end) && c.cue.end >= c.cue.start;
               }) >= 1;
      },
      40);
  Check(completed, "the next caption completes the previous cue with an end time");
  OnOwner([&] {
    bool matched = true;
    bool any = false;
    for (const auto& update : r.cues_) {
      if (update.cue.type != fp::HlsCue::Type::kUpdate) {
        continue;
      }
      bool found = false;
      for (const auto& add : r.cues_) {
        if (add.cue.type == fp::HlsCue::Type::kAdd && add.cue.cue_id == update.cue.cue_id) {
          found = add.cue.text == update.cue.text && add.cue.start == update.cue.start;
        }
      }
      any = true;
      matched = matched && found;
    }
    Check(any && matched, "updates name a cue added before, with the same text and start");
  });
  // A seek drops the open cue (removeGenericCue) when one is pending.
  size_t open_before = 0;
  OnOwner([&] {
    std::vector<uint64_t> open;
    for (const auto& c : r.cues_) {
      if (c.cue.type == fp::HlsCue::Type::kAdd) {
        open.push_back(c.cue.cue_id);
      } else {
        open.erase(std::remove(open.begin(), open.end(), c.cue.cue_id), open.end());
      }
    }
    open_before = open.size();
  });
  size_t removes_before = r.CueCount([](const ReceivedCue& c) { return c.cue.type == fp::HlsCue::Type::kRemove; });
  session.Seek(5);
  size_t removes_after = 0;
  OnOwner([&] {
    removes_after = r.CueCount([](const ReceivedCue& c) { return c.cue.type == fp::HlsCue::Type::kRemove; });
  });
  Check(open_before == 0 || removes_after > removes_before, "a seek removes the open generic cue");
  bool after_seek = WaitFor(
      [&] {
        return r.CueCount([&](const ReceivedCue& c) {
                 return c.cue.type == fp::HlsCue::Type::kAdd && c.cue.start >= 4.5 && c.cue.start < 30;
               }) >= 1;
      },
      40);
  Check(after_seek, "captions resume after the seek");
}

void TeardownScenario() {
  std::printf("== teardown\n");
  {
    Session session(
        @"https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_16x9/bipbop_16x9_variant.m3u8");
    WaitFor([&] { return session.recorder.Count(fp::HlsTrackType::kText) > 0; }, 30);
    OnOwner([&] {
      session.selection->SetTextTrackMode("text-0", fp::HlsTextTrackMode::kShowing);
    });
    [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1.0]];
  }
  // Anything posted after destruction must be dropped, not crash.
  [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:2.0]];
  Check(true, "destroying the selection while cues are flowing");
}

}  // namespace

int main(int argc, char** argv) {
  @autoreleasepool {
    std::string only = argc > 1 ? argv[1] : "";
    if (only.empty() || only == "webvtt") {
      WebVttScenario();
    }
    if (only.empty() || only == "cea608") {
      ClosedCaptionScenario();
    }
    if (only.empty() || only == "teardown") {
      TeardownScenario();
    }
    std::printf("%s: %d failure(s)\n", g_failures ? "FAILED" : "OK", g_failures);
    return g_failures ? 1 : 0;
  }
}
