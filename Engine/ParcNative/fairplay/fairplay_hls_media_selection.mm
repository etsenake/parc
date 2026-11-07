#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <Foundation/Foundation.h>
#import <MediaAccessibility/MediaAccessibility.h>

#include <dlfcn.h>

#include <algorithm>
#include <atomic>
#include <cmath>
#include <limits>
#include <map>
#include <utility>

#include "fairplay_hls_media_selection.h"
#include "fairplay_hls_media_selection_internal.h"

// WebKit's media selection code uses the synchronous AVAsset and
// AVMediaSelectionGroup accessors that macOS 13 deprecates; this port keeps
// them so its answers match WebKit's step for step.
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

// SPI WebKit uses (AVTrackPrivateAVFObjCImpl.mm, MediaSelectionGroupAVFObjC.mm);
// both are checked with respondsToSelector: before use.
@interface AVMediaSelectionOption (ParcHlsMediaSelection)
- (id)optionID;
- (AVAssetTrack*)track;
@end

@interface PCHlsSelectionObserver : NSObject <AVPlayerItemLegibleOutputPushDelegate>
- (instancetype)initWithImpl:(std::weak_ptr<parc::fairplay::HlsMediaSelection::Impl>)impl
                      poster:(std::shared_ptr<const parc::fairplay::PostTask>)poster;
- (void)observeItem:(AVPlayerItem*)item;
- (void)observeTracks:(NSArray<AVPlayerItemTrack*>*)tracks;
- (void)stop;
@end

// Foundation SPI WebKit declares (NSLocaleSPI.h) for its language matching.
@interface NSLocale (ParcLanguageMatching)
+ (NSArray<NSString*>*)matchedLanguagesFromAvailableLanguages:(NSArray<NSString*>*)availableLanguages
                                        forPreferredLanguages:(NSArray<NSString*>*)preferredLanguages;
@end

namespace parc::fairplay {
namespace {

// MediaPlayerPrivateAVFoundationObjC's avPlayerOutputAdvanceInterval.
constexpr NSTimeInterval kOutputAdvanceInterval = 2;

constexpr double kInfinity = std::numeric_limits<double>::infinity();

NSString* const kMediaSelectionKey = @"availableMediaCharacteristicsWithMediaSelectionOptions";

std::string ToStdString(NSString* string) {
  if (!string) {
    return {};
  }
  const char* utf8 = string.UTF8String;
  return utf8 ? std::string(utf8) : std::string();
}

// WTF::userPreferredLanguages(ShouldMinimizeLanguages::No) on Cocoa:
// CFLocaleCopyPreferredLanguages, canonicalized, '_' after a two-letter
// code turned into '-', "en" when the list is empty.
NSArray<NSString*>* UserPreferredLanguages() {
  NSMutableArray<NSString*>* languages = [NSMutableArray array];
  CFArrayRef platform = CFLocaleCopyPreferredLanguages();
  CFIndex count = platform ? CFArrayGetCount(platform) : 0;
  for (CFIndex i = 0; i < count; ++i) {
    CFStringRef language = static_cast<CFStringRef>(CFArrayGetValueAtIndex(platform, i));
    if (!language || CFGetTypeID(language) != CFStringGetTypeID()) {
      continue;
    }
    CFStringRef canonical = CFLocaleCreateCanonicalLanguageIdentifierFromString(kCFAllocatorDefault, language);
    NSMutableString* code = [(canonical ? (__bridge NSString*)canonical : (__bridge NSString*)language) mutableCopy];
    if (canonical) {
      CFRelease(canonical);
    }
    if (code.length >= 3 && [code characterAtIndex:2] == '_') {
      [code replaceCharactersInRange:NSMakeRange(2, 1) withString:@"-"];
    }
    [languages addObject:code];
  }
  if (platform) {
    CFRelease(platform);
  }
  if (!languages.count) {
    [languages addObject:@"en"];
  }
  return languages;
}

// CaptionUserPreferencesMediaAF::preferredAudioCharacteristics: the
// accessibility setting (audio descriptions), empty when unset.
NSArray<NSString*>* PreferredAudioCharacteristics() {
  CFArrayRef characteristics = MAAudibleMediaCopyPreferredCharacteristics();
  if (!characteristics) {
    return @[];
  }
  NSArray<NSString*>* result = [(__bridge NSArray*)characteristics copy];
  CFRelease(characteristics);
  return result ?: @[];
}

// WTF::indexOfBestMatchingLanguageInList on Cocoa: Foundation's match of
// |language| against |list|; |list|'s size when nothing matches.
size_t IndexOfBestMatchingLanguage(const std::string& language,
                                   const std::vector<std::string>& list,
                                   bool* exact_match) {
  *exact_match = false;
  NSString* preferred = language.empty() ? nil : @(language.c_str());
  if (!preferred || list.empty()) {
    return list.size();
  }
  NSMutableArray<NSString*>* available = [NSMutableArray array];
  std::vector<size_t> positions;
  for (size_t i = 0; i < list.size(); ++i) {
    NSString* entry = list[i].empty() ? nil : @(list[i].c_str());
    if (entry) {
      [available addObject:entry];
      positions.push_back(i);
    }
  }
  if (!available.count) {
    return list.size();
  }
  if (![NSLocale respondsToSelector:@selector(matchedLanguagesFromAvailableLanguages:forPreferredLanguages:)]) {
    // WTF's portable rule where the SPI is missing: an exact match, else the
    // first entry of the same language.
    auto primary = [](const std::string& tag) {
      std::string lower;
      for (char c : tag.substr(0, tag.find_first_of("-_"))) {
        lower.push_back(static_cast<char>(c >= 'A' && c <= 'Z' ? c + 32 : c));
      }
      return lower;
    };
    size_t same_language = list.size();
    for (size_t i = 0; i < list.size(); ++i) {
      NSString* entry = list[i].empty() ? nil : @(list[i].c_str());
      // (A nil receiver would answer NSOrderedSame.)
      if (entry && [entry caseInsensitiveCompare:preferred] == NSOrderedSame) {
        *exact_match = true;
        return i;
      }
      if (same_language == list.size() && !list[i].empty() && primary(list[i]) == primary(language)) {
        same_language = i;
      }
    }
    return same_language;
  }
  NSArray<NSString*>* matched = [NSLocale matchedLanguagesFromAvailableLanguages:available
                                                           forPreferredLanguages:@[ preferred ]];
  NSString* first = matched.firstObject;
  if (!first) {
    return list.size();
  }
  *exact_match = [first isEqualToString:preferred];
  NSUInteger index = [available indexOfObject:first];
  return index == NSNotFound ? list.size() : positions[index];
}

// TrackBase's isValidBCP47LanguageTag: what validBCP47Language keeps.
bool IsValidBcp47LanguageTag(const std::string& tag) {
  auto alpha = [](char c) { return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z'); };
  auto alnum = [&](char c) { return alpha(c) || (c >= '0' && c <= '9'); };
  size_t length = tag.size();
  if (length < 2 || length > 100 || !alpha(tag[0])) {
    return false;
  }
  if (length == 2) {
    return alpha(tag[1]);
  }
  bool irregular = (tag[0] == 'i' || tag[0] == 'x') && tag[1] == '-';
  size_t next;
  if (!irregular) {
    if (!alpha(tag[1])) {
      return false;
    }
    if (length == 3) {
      return alpha(tag[2]);
    }
    if (alpha(tag[2])) {
      if (tag[3] != '-') {
        return false;
      }
      next = 4;
    } else if (tag[2] == '-') {
      next = 3;
    } else {
      return false;
    }
  } else {
    next = 2;
  }
  for (; next < length; ++next) {
    if (!alnum(tag[next]) && tag[next] != '-') {
      return false;
    }
  }
  return true;
}

// The system caption settings CaptionUserPreferencesMediaAF reads from
// MediaAccessibility.
struct CaptionPreferences {
  enum class DisplayMode { kForcedOnly, kAutomatic, kAlwaysOn };
  DisplayMode display_mode = DisplayMode::kForcedOnly;
  // userPrefersCaptions: an SDH/CC captioning characteristic is preferred.
  bool prefers_captions = false;
  // preferredLanguages(): the caption languages, then the user's languages.
  std::vector<std::string> languages;
  // defaultLanguage(ShouldMinimizeLanguages::No): the user's first language.
  std::string default_language;
};

std::vector<std::string> StringsFromCFArray(CFArrayRef array) {
  std::vector<std::string> result;
  CFIndex count = array ? CFArrayGetCount(array) : 0;
  for (CFIndex i = 0; i < count; ++i) {
    CFTypeRef value = CFArrayGetValueAtIndex(array, i);
    if (value && CFGetTypeID(value) == CFStringGetTypeID()) {
      result.push_back(ToStdString((__bridge NSString*)value));
    }
  }
  return result;
}

CaptionPreferences ReadCaptionPreferences() {
  CaptionPreferences preferences;
  switch (MACaptionAppearanceGetDisplayType(kMACaptionAppearanceDomainUser)) {
    case kMACaptionAppearanceDisplayTypeAutomatic:
      preferences.display_mode = CaptionPreferences::DisplayMode::kAutomatic;
      break;
    case kMACaptionAppearanceDisplayTypeAlwaysOn:
      preferences.display_mode = CaptionPreferences::DisplayMode::kAlwaysOn;
      break;
    case kMACaptionAppearanceDisplayTypeForcedOnly:
    default:
      preferences.display_mode = CaptionPreferences::DisplayMode::kForcedOnly;
      break;
  }
  CFArrayRef characteristics =
      MACaptionAppearanceCopyPreferredCaptioningMediaCharacteristics(kMACaptionAppearanceDomainUser);
  preferences.prefers_captions = characteristics && CFArrayGetCount(characteristics) > 0;
  if (characteristics) {
    CFRelease(characteristics);
  }
  std::vector<std::string> user;
  for (NSString* language in UserPreferredLanguages()) {
    user.push_back(ToStdString(language));
  }
  preferences.default_language = user.empty() ? std::string() : user.front();
  CFArrayRef selected = MACaptionAppearanceCopySelectedLanguages(kMACaptionAppearanceDomainUser);
  preferences.languages = StringsFromCFArray(selected);
  if (selected) {
    CFRelease(selected);
  }
  preferences.languages.insert(preferences.languages.end(), user.begin(), user.end());
  return preferences;
}

// CaptionUserPreferences::textTrackLanguageSelectionScore.
int TextTrackLanguageSelectionScore(const std::string& language,
                                    const std::vector<std::string>& preferred) {
  if (language.empty()) {
    return 0;
  }
  bool exact = false;
  size_t index = IndexOfBestMatchingLanguage(language, preferred, &exact);
  if (index >= preferred.size()) {
    return 0;
  }
  return static_cast<int>((preferred.size() + (exact ? 1 : 0) - index) * 10);
}

// CaptionUserPreferences::textTrackSelectionScore for an in-band track
// (CaptionUserPreferencesMediaAF's display mode and preferences; WebKit has
// no Manual mode from MediaAccessibility, and in-band tracks have no
// descriptions kind). |audio_language| is the first enabled audio track's.
int TextTrackSelectionScore(const HlsTrack& track,
                            const CaptionPreferences& preferences,
                            const std::string& audio_language) {
  using Mode = CaptionPreferences::DisplayMode;
  const Mode mode = preferences.display_mode;
  // AlwaysOn with neither captions nor subtitles preferred can't happen:
  // userPrefersSubtitles is !userPrefersCaptions.
  if (track.kind != "captions" && track.kind != "subtitles" && track.kind != "forced") {
    return 0;
  }
  if (!track.is_main_program_content) {
    return 0;
  }
  const bool forced_only = track.contains_only_forced_subtitles;
  if ((forced_only && mode != Mode::kForcedOnly) || (!forced_only && mode == Mode::kForcedOnly)) {
    return 0;
  }
  std::vector<std::string> languages = preferences.languages;
  const std::string language = IsValidBcp47LanguageTag(track.language) ? track.language : std::string();
  if (mode == Mode::kAutomatic || forced_only) {
    if (language.empty() || audio_language.empty()) {
      return 0;
    }
    std::vector<std::string> list;
    bool exact = false;
    if (forced_only) {
      // Only a forced-only track in the audio's language.
      list.push_back(audio_language);
      if (IndexOfBestMatchingLanguage(language, list, &exact) != 0) {
        return 0;
      }
    } else {
      // Only when the audio isn't in the user's language, and the track is.
      list.push_back(preferences.default_language);
      if (IndexOfBestMatchingLanguage(audio_language, list, &exact) == 0) {
        return 0;
      }
      if (IndexOfBestMatchingLanguage(language, list, &exact) != 0) {
        return 0;
      }
    }
    languages = list;
  }
  int score;
  if (preferences.prefers_captions) {
    // SDH, then CC, then subtitles.
    score = track.kind == "subtitles" ? 1 : (track.is_closed_captions ? 2 : 3);
  } else {
    // Subtitles, then SDH, then CC.
    score = track.kind == "subtitles" ? 3 : (!track.is_closed_captions ? 2 : 1);
  }
  return score + TextTrackLanguageSelectionScore(language, languages);
}

// The common metadata title in one of the user's languages
// (AVTrackPrivateAVFObjCImpl::label, InbandTextTrackPrivateAVFObjC::label).
std::string TitleFromCommonMetadata(NSArray<AVMetadataItem*>* common_metadata) {
  if (!common_metadata) {
    return {};
  }
  NSArray<AVMetadataItem*>* titles = [AVMetadataItem metadataItemsFromArray:common_metadata
                                                                    withKey:AVMetadataCommonKeyTitle
                                                                   keySpace:AVMetadataKeySpaceCommon];
  if (!titles.count) {
    return {};
  }
  NSArray<AVMetadataItem*>* preferred =
      [AVMetadataItem metadataItemsFromArray:titles
          filteredAndSortedAccordingToPreferredLanguages:[NSLocale preferredLanguages]];
  if (preferred.count) {
    NSString* title = preferred.firstObject.stringValue;
    if (title) {
      return ToStdString(title);
    }
  }
  return ToStdString(titles.firstObject.stringValue);
}

std::string LanguageForAssetTrack(AVAssetTrack* track) {
  NSString* language = track.extendedLanguageTag;
  // A QuickTime packed language code has no RFC 4646 tag.
  if (!language) {
    language = track.languageCode;
  }
  if (!language || [language isEqualToString:@"und"]) {
    return {};
  }
  return ToStdString(language);
}

std::string LanguageForOption(AVMediaSelectionOption* option) {
  NSString* language = option.extendedLanguageTag;
  if (!language) {
    language = [option.locale objectForKey:NSLocaleLanguageCode];
  }
  if (!language || [language isEqualToString:@"und"]) {
    return {};
  }
  return ToStdString(language);
}

// AVTrackPrivateAVFObjCImpl::textKindForAVMediaSelectionOption.
std::string TextKindForOption(AVMediaSelectionOption* option) {
  NSString* media_type = option.mediaType;
  if ([media_type isEqualToString:AVMediaTypeClosedCaption]) {
    return "captions";
  }
  if ([media_type isEqualToString:AVMediaTypeSubtitle]) {
    if ([option hasMediaCharacteristic:AVMediaCharacteristicContainsOnlyForcedSubtitles]) {
      return "forced";
    }
    // SDH subtitles are WebVTT "captions" (for the hard of hearing).
    if ([option hasMediaCharacteristic:AVMediaCharacteristicTranscribesSpokenDialogForAccessibility]) {
      return "captions";
    }
    if ([option hasMediaCharacteristic:AVMediaCharacteristicDescribesMusicAndSoundForAccessibility]) {
      return "captions";
    }
    return "subtitles";
  }
  return "captions";
}

// GenericCueData.
struct GenericCue {
  enum class Status { kUninitialized, kPartial, kComplete };
  uint64_t unique_id = 0;
  double start = 0;
  double end = 0;
  std::string content;
  std::string font_name;
  double line = -1;
  double position = -1;
  double size = -1;
  double base_font_size = 0;
  double relative_font_size = 0;
  std::optional<uint32_t> foreground_color;
  std::optional<uint32_t> background_color;
  std::optional<uint32_t> highlight_color;
  HlsCueAlign position_align = HlsCueAlign::kNone;
  HlsCueAlign align = HlsCueAlign::kNone;
  Status status = Status::kUninitialized;
  bool prevent_line_wrapping = true;

  // GenericCueData::equalNotConsideringTimesOrId (the cue id is always
  // empty here).
  bool Extends(const GenericCue& other) const {
    return relative_font_size == other.relative_font_size && base_font_size == other.base_font_size &&
           position == other.position && line == other.line && size == other.size && align == other.align &&
           foreground_color == other.foreground_color && background_color == other.background_color &&
           highlight_color == other.highlight_color && font_name == other.font_name &&
           content == other.content && prevent_line_wrapping == other.prevent_line_wrapping;
  }

  HlsCue ToCue(HlsCue::Type type) const {
    HlsCue cue;
    cue.type = type;
    cue.cue_id = unique_id;
    cue.start = start;
    cue.end = end;
    cue.complete = status == Status::kComplete;
    cue.text = content;
    cue.line = line;
    cue.position = position;
    cue.size = size;
    cue.base_font_size = base_font_size;
    cue.relative_font_size = relative_font_size;
    cue.font_name = font_name;
    cue.align = align;
    cue.position_align = position_align;
    cue.foreground_color = foreground_color;
    cue.background_color = background_color;
    cue.highlight_color = highlight_color;
    cue.prevent_line_wrapping = prevent_line_wrapping;
    return cue;
  }
};

// makeSimpleColorFromARGBCFArray: four float components, alpha first.
std::optional<uint32_t> ColorFromARGBArray(CFTypeRef value) {
  if (!value || CFGetTypeID(value) != CFArrayGetTypeID()) {
    return std::nullopt;
  }
  CFArrayRef array = static_cast<CFArrayRef>(value);
  if (CFArrayGetCount(array) < 4) {
    return std::nullopt;
  }
  float components[4];
  for (CFIndex i = 0; i < 4; ++i) {
    CFTypeRef number = CFArrayGetValueAtIndex(array, i);
    if (!number || CFGetTypeID(number) != CFNumberGetTypeID()) {
      return std::nullopt;
    }
    CFNumberGetValue(static_cast<CFNumberRef>(number), kCFNumberFloatType, &components[i]);
  }
  // convertColor<SRGBA<uint8_t>>: each component rounded and clamped.
  auto byte = [](float component) -> uint32_t {
    long value = std::lround(component * 255.0f);
    return static_cast<uint32_t>(std::clamp(value, 0L, 255L));
  };
  return (byte(components[1]) << 24) | (byte(components[2]) << 16) | (byte(components[3]) << 8) | byte(components[0]);
}

bool KeyIs(CFStringRef key, CFStringRef name) {
  return name && CFStringCompare(key, name, 0) == kCFCompareEqualTo;
}

CFStringRef PreventLineWrappingKey() {
  // Not in the SDK; WebKit soft-links it and skips it when absent.
  static CFStringRef key = [] {
    auto* symbol = static_cast<CFStringRef*>(dlsym(RTLD_DEFAULT, "kCMTextMarkupAttribute_PreventLineWrapping"));
    return symbol ? *symbol : nullptr;
  }();
  return key;
}

bool IsTrue(CFTypeRef value) {
  return value == kCFBooleanTrue;
}

bool ReadDouble(CFTypeRef value, double* out) {
  if (!value || CFGetTypeID(value) != CFNumberGetTypeID()) {
    return false;
  }
  CFNumberGetValue(static_cast<CFNumberRef>(value), kCFNumberFloat64Type, out);
  return true;
}

// InbandTextTrackPrivateAVF::processCueAttributes.
GenericCue ProcessCueAttributes(NSAttributedString* attributed_string, uint64_t unique_id) {
  enum AttributeFlags : unsigned {
    kLine = 1 << 0,
    kPosition = 1 << 1,
    kSize = 1 << 2,
    kVertical = 1 << 3,
    kAlign = 1 << 4,
    kFontName = 1 << 5,
  };
  unsigned processed = 0;

  GenericCue cue;
  cue.unique_id = unique_id;
  CFAttributedStringRef cf_string = (__bridge CFAttributedStringRef)attributed_string;
  NSString* value = attributed_string.string;
  CFIndex length = static_cast<CFIndex>(value.length);
  if (!length) {
    return cue;
  }
  NSMutableString* content = [NSMutableString string];
  CFRange effective_range = CFRangeMake(0, 0);
  while ((effective_range.location + effective_range.length) < length) {
    CFDictionaryRef attributes =
        CFAttributedStringGetAttributes(cf_string, effective_range.location + effective_range.length, &effective_range);
    if (!attributes) {
      continue;
    }
    NSMutableString* tag_start = [NSMutableString string];
    NSString* tag_end = @"";
    CFIndex attribute_count = CFDictionaryGetCount(attributes);
    std::vector<const void*> keys(static_cast<size_t>(attribute_count));
    std::vector<const void*> values(static_cast<size_t>(attribute_count));
    CFDictionaryGetKeysAndValues(attributes, keys.data(), values.data());

    for (CFIndex i = 0; i < attribute_count; ++i) {
      CFTypeRef key_object = keys[static_cast<size_t>(i)];
      CFTypeRef attribute = values[static_cast<size_t>(i)];
      if (!key_object || CFGetTypeID(key_object) != CFStringGetTypeID()) {
        continue;
      }
      CFStringRef key = static_cast<CFStringRef>(key_object);
      if (!CFStringGetLength(key)) {
        continue;
      }

      if (KeyIs(key, PreventLineWrappingKey())) {
        cue.prevent_line_wrapping = IsTrue(attribute);
      }

      if (KeyIs(key, kCMTextMarkupAttribute_Alignment)) {
        if (!attribute || CFGetTypeID(attribute) != CFStringGetTypeID() ||
            !CFStringGetLength(static_cast<CFStringRef>(attribute))) {
          continue;
        }
        if (processed & kAlign) {
          continue;
        }
        processed |= kAlign;
        CFStringRef alignment = static_cast<CFStringRef>(attribute);
        if (KeyIs(alignment, kCMTextMarkupAlignmentType_Start)) {
          cue.align = HlsCueAlign::kStart;
        } else if (KeyIs(alignment, kCMTextMarkupAlignmentType_Middle)) {
          cue.align = HlsCueAlign::kMiddle;
        } else if (KeyIs(alignment, kCMTextMarkupAlignmentType_End)) {
          cue.align = HlsCueAlign::kEnd;
        }
        continue;
      }

      if (KeyIs(key, kCMTextMarkupAttribute_BoldStyle)) {
        if (!IsTrue(attribute)) {
          continue;
        }
        [tag_start appendString:@"<b>"];
        tag_end = [@"</b>" stringByAppendingString:tag_end];
        continue;
      }

      if (KeyIs(key, kCMTextMarkupAttribute_ItalicStyle)) {
        if (!IsTrue(attribute)) {
          continue;
        }
        [tag_start appendString:@"<i>"];
        tag_end = [@"</i>" stringByAppendingString:tag_end];
        continue;
      }

      if (KeyIs(key, kCMTextMarkupAttribute_UnderlineStyle)) {
        if (!IsTrue(attribute)) {
          continue;
        }
        [tag_start appendString:@"<u>"];
        tag_end = [@"</u>" stringByAppendingString:tag_end];
        continue;
      }

      if (KeyIs(key, kCMTextMarkupAttribute_OrthogonalLinePositionPercentageRelativeToWritingDirection)) {
        double line;
        if (!ReadDouble(attribute, &line)) {
          continue;
        }
        if (processed & kLine) {
          continue;
        }
        processed |= kLine;
        cue.line = line;
        continue;
      }

      if (KeyIs(key, kCMTextMarkupAttribute_TextPositionPercentageRelativeToWritingDirection)) {
        double position;
        if (!ReadDouble(attribute, &position)) {
          continue;
        }
        if (processed & kPosition) {
          continue;
        }
        processed |= kPosition;
        cue.position = position;
        continue;
      }

      if (KeyIs(key, kCMTextMarkupAttribute_WritingDirectionSizePercentage)) {
        double size;
        if (!ReadDouble(attribute, &size)) {
          continue;
        }
        if (processed & kSize) {
          continue;
        }
        processed |= kSize;
        cue.size = size;
        continue;
      }

      if (KeyIs(key, kCMTextMarkupAttribute_VerticalLayout)) {
        if (!attribute || CFGetTypeID(attribute) != CFStringGetTypeID() ||
            !CFStringGetLength(static_cast<CFStringRef>(attribute))) {
          continue;
        }
        CFStringRef layout = static_cast<CFStringRef>(attribute);
        if (KeyIs(layout, kCMTextVerticalLayout_LeftToRight)) {
          [tag_start appendString:@"‎"];
        } else if (KeyIs(layout, kCMTextVerticalLayout_RightToLeft)) {
          [tag_start appendString:@"‏"];
        }
        continue;
      }

      if (KeyIs(key, kCMTextMarkupAttribute_BaseFontSizePercentageRelativeToVideoHeight)) {
        double base_font_size;
        if (!ReadDouble(attribute, &base_font_size)) {
          continue;
        }
        cue.base_font_size = base_font_size;
        continue;
      }

      if (KeyIs(key, kCMTextMarkupAttribute_RelativeFontSize)) {
        double relative_font_size;
        if (!ReadDouble(attribute, &relative_font_size)) {
          continue;
        }
        cue.relative_font_size = relative_font_size;
        continue;
      }

      if (KeyIs(key, kCMTextMarkupAttribute_FontFamilyName)) {
        if (!attribute || CFGetTypeID(attribute) != CFStringGetTypeID() ||
            !CFStringGetLength(static_cast<CFStringRef>(attribute))) {
          continue;
        }
        if (processed & kFontName) {
          continue;
        }
        processed |= kFontName;
        cue.font_name = ToStdString((__bridge NSString*)attribute);
        continue;
      }

      if (KeyIs(key, kCMTextMarkupAttribute_ForegroundColorARGB)) {
        if (auto color = ColorFromARGBArray(attribute)) {
          cue.foreground_color = color;
        }
        continue;
      }

      if (KeyIs(key, kCMTextMarkupAttribute_BackgroundColorARGB)) {
        if (auto color = ColorFromARGBArray(attribute)) {
          cue.background_color = color;
        }
        continue;
      }

      if (KeyIs(key, kCMTextMarkupAttribute_CharacterBackgroundColorARGB)) {
        if (auto color = ColorFromARGBArray(attribute)) {
          cue.highlight_color = color;
        }
        continue;
      }
    }

    [content appendString:tag_start];
    [content appendString:[value substringWithRange:NSMakeRange(static_cast<NSUInteger>(effective_range.location),
                                                                static_cast<NSUInteger>(effective_range.length))]];
    [content appendString:tag_end];
  }

  // AVFoundation's position is the centre of the text: move it to the edge
  // the cue's alignment names.
  if (cue.position >= 0 && cue.size >= 0) {
    switch (cue.align) {
      case HlsCueAlign::kNone:
      case HlsCueAlign::kMiddle:
      case HlsCueAlign::kStart:
        cue.position_align = HlsCueAlign::kStart;
        cue.position = cue.position - cue.size / 2;
        break;
      case HlsCueAlign::kEnd:
        cue.position_align = HlsCueAlign::kEnd;
        cue.position = cue.position + cue.size / 2;
        break;
    }
  }

  if (content.length) {
    cue.content = ToStdString(content);
  }
  return cue;
}

// ISOBox::peekBox: size clamped to what remains, 0 meaning "to the end".
// WebKit clamps rather than waiting for the rest of a box that runs past the
// sample, so a split box is read truncated, as here.
struct BoxHeader {
  uint32_t type = 0;
  uint64_t size = 0;
  size_t header_size = 0;
};

uint32_t ReadBigEndian32(const uint8_t* bytes) {
  return (uint32_t{bytes[0]} << 24) | (uint32_t{bytes[1]} << 16) | (uint32_t{bytes[2]} << 8) | uint32_t{bytes[3]};
}

std::optional<BoxHeader> ParseBoxHeader(const std::vector<uint8_t>& buffer, size_t offset) {
  if (offset > buffer.size()) {
    return std::nullopt;
  }
  size_t available = buffer.size() - offset;
  if (available < 8) {
    return std::nullopt;
  }
  BoxHeader header;
  header.size = ReadBigEndian32(&buffer[offset]);
  header.type = ReadBigEndian32(&buffer[offset + 4]);
  header.header_size = 8;
  if (header.size == 1) {
    if (available < 16) {
      return std::nullopt;
    }
    header.size = (uint64_t{ReadBigEndian32(&buffer[offset + 8])} << 32) | ReadBigEndian32(&buffer[offset + 12]);
    header.header_size = 16;
  }
  if (header.size > available || !header.size) {
    header.size = available;
  }
  return header;
}

constexpr uint32_t FourCC(const char (&code)[5]) {
  return (uint32_t(uint8_t(code[0])) << 24) | (uint32_t(uint8_t(code[1])) << 16) | (uint32_t(uint8_t(code[2])) << 8) |
         uint32_t(uint8_t(code[3]));
}

// String::fromUTF8: invalid UTF-8 gives the null (empty) string.
std::string Utf8OrEmpty(const uint8_t* bytes, size_t size) {
  if (!size) {
    return {};
  }
  NSString* string = [[NSString alloc] initWithBytes:bytes length:size encoding:NSUTF8StringEncoding];
  return string ? std::string(reinterpret_cast<const char*>(bytes), size) : std::string();
}

// ISOWebVTTCue::parse over the remaining buffer, as WebKit calls it: the
// cue box's header, then string boxes until one doesn't parse.
void ParseWebVttCue(const std::vector<uint8_t>& buffer, HlsCue& cue) {
  auto header = ParseBoxHeader(buffer, 0);
  if (!header) {
    return;
  }
  size_t offset = header->header_size;
  while (true) {
    auto box = ParseBoxHeader(buffer, offset);
    if (!box) {
      return;
    }
    uint64_t character_count = box->size - box->header_size;
    if (box->size < box->header_size) {
      return;
    }
    size_t contents = offset + box->header_size;
    if (character_count > buffer.size() - contents) {
      return;
    }
    std::string text = Utf8OrEmpty(buffer.data() + contents, static_cast<size_t>(character_count));
    if (box->type == FourCC("vsid")) {
      cue.source_id = std::move(text);
    } else if (box->type == FourCC("iden")) {
      cue.identifier = std::move(text);
    } else if (box->type == FourCC("ctim")) {
      cue.original_start_time = std::move(text);
    } else if (box->type == FourCC("sttg")) {
      cue.settings = std::move(text);
    } else if (box->type == FourCC("payl")) {
      cue.text = std::move(text);
    }
    offset += static_cast<size_t>(box->size);
  }
}

// makeString(span<const uint8_t>, "\n\n"): the header bytes as Latin-1.
std::string Latin1ToUtf8(const uint8_t* bytes, size_t size) {
  std::string out;
  out.reserve(size);
  for (size_t i = 0; i < size; ++i) {
    uint8_t c = bytes[i];
    if (c < 0x80) {
      out.push_back(static_cast<char>(c));
    } else {
      out.push_back(static_cast<char>(0xC0 | (c >> 6)));
      out.push_back(static_cast<char>(0x80 | (c & 0x3F)));
    }
  }
  return out;
}

}  // namespace

class HlsMediaSelection::Impl : public std::enable_shared_from_this<HlsMediaSelection::Impl> {
 public:
  Impl(HlsMediaSelectionClient* client, PostTask post_task)
      : client_(client), poster_(std::make_shared<const PostTask>(std::move(post_task))) {}

  ~Impl() { Detach(); }

  void Attach(AVPlayer* player, AVPlayerItem* item) {
    if (item_ || !player || !item) {
      return;
    }
    player_ = player;
    item_ = item;
    asset_ = item.asset;
    std::weak_ptr<Impl> weak = weak_from_this();

    // createAVPlayerItem: WebVTT samples natively, everything else as
    // attributed strings; AVFoundation draws none of it.
    legible_output_ = [[AVPlayerItemLegibleOutput alloc]
        initWithMediaSubtypesForNativeRepresentation:@[ @(kCMSubtitleFormatType_WebVTT) ]];
    legible_output_.suppressesPlayerRendering = YES;
    observer_ = [[PCHlsSelectionObserver alloc] initWithImpl:weak poster:poster_];
    [legible_output_ setDelegate:observer_ queue:LegibleQueue()];
    legible_output_.advanceIntervalForDelegateInvocation = kOutputAdvanceInterval;
    legible_output_.textStylingResolution = AVPlayerItemLegibleOutputTextStylingResolutionSourceAndRulesOnly;
    [item_ addOutput:legible_output_];

    [observer_ observeItem:item_];

    // hasLoadedMediaSelectionGroups needs this key loaded (WebKit loads it
    // with the asset's metadata).
    std::shared_ptr<const PostTask> poster = poster_;
    [asset_ loadValuesAsynchronouslyForKeys:@[ kMediaSelectionKey ]
                          completionHandler:^{
                            (*poster)([weak] {
                              if (auto impl = weak.lock()) {
                                impl->TracksChanged();
                              }
                            });
                          }];
    if (item_.tracks.count) {
      TracksDidChange();
    }
  }

  void Detach() {
    if (!item_) {
      return;
    }
    [observer_ stop];
    [legible_output_ setDelegate:nil queue:nil];
    [item_ removeOutput:legible_output_];
    legible_output_ = nil;
    // A KVO notification or delegate call already running on another thread
    // when observation stopped still uses the observer: keep it alive for
    // one more hop.
    (*poster_)([observer = observer_] { (void)observer; });
    observer_ = nil;
    audible_group_.reset();
    audio_tracks_.clear();
    text_tracks_.clear();
    current_text_track_ = nullptr;
    reported_.clear();
    item_ = nil;
    player_ = nil;
    asset_ = nil;
    cached_tracks_ = nil;
  }

  // MediaPlayerPrivateAVFoundationObjC::tracksDidChange: the item tracks
  // that belong to no media selection group.
  void TracksDidChange() {
    if (!item_) {
      return;
    }
    NSArray<AVPlayerItemTrack*>* tracks = item_.tracks ?: @[];
    NSArray<AVAssetTrack*>* asset_tracks = asset_.tracks;
    NSIndexSet* indexes = [tracks indexesOfObjectsPassingTest:^BOOL(AVPlayerItemTrack* track, NSUInteger, BOOL*) {
      AVAssetTrack* asset_track = track.assetTrack;
      if ([asset_tracks containsObject:asset_track]) {
        return YES;
      }
      // A streaming track: omitted when it belongs to a media selection group.
      if (!HasLoadedMediaSelectionGroups()) {
        return NO;
      }
      if ([asset_track hasMediaCharacteristic:AVMediaCharacteristicAudible] && AudibleGroup()) {
        return NO;
      }
      if ([asset_track hasMediaCharacteristic:AVMediaCharacteristicVisual] && VisualGroup()) {
        return NO;
      }
      if ([asset_track hasMediaCharacteristic:AVMediaCharacteristicLegible] && LegibleGroup()) {
        return NO;
      }
      return YES;
    }];
    cached_tracks_ = [tracks objectsAtIndexes:indexes];
    // WebKit observes each cached track's enabled state.
    [observer_ observeTracks:cached_tracks_];
    TracksChanged();
  }

  // MediaPlayerPrivateAVFoundationObjC::tracksChanged, the track parts.
  void TracksChanged() {
    // WebKit makes the HLS player item only once the asset's metadata (with
    // the media selection groups) has loaded, so its first track update
    // comes from the item's first tracks change. Waiting for that here gives
    // the same tracks whichever of the two finishes first.
    if (!item_ || !asset_ || !cached_tracks_) {
      return;
    }
    UpdateAudioTracks();
    AVMediaSelectionGroup* legible_group = LegibleGroup();
    if (legible_group && cached_tracks_) {
      if ([AVMediaSelectionGroup playableMediaSelectionOptionsFromArray:legible_group.options].count) {
        ProcessMediaSelectionOptions();
      }
    }
    ReportTracks();
  }

  void SetAudioTrackEnabled(const std::string& key, bool enabled) {
    AudioTrack* track = FindAudioTrack(key);
    if (!track) {
      return;
    }
    // AudioTrackPrivateAVFObjC::setEnabled: the private's flag first, then
    // the option or item track.
    track->enabled = enabled;
    if (track->item_track) {
      track->item_track.enabled = enabled;
    } else if (track->option && audible_group_) {
      SetOptionSelected(track->option, enabled);
    }
    ReportTracks();
  }

  void SetTextTrackMode(const std::string& key, HlsTextTrackMode mode) {
    TextTrack* track = FindTextTrack(key);
    if (!track || track->mode == mode) {
      return;
    }
    track->mode = mode;
    ConfigureInbandTracks();
  }

  void BeginSeeking() {
    if (TextTrack* track = current_text_track_) {
      // Forget partial cue data: the next cue could be outside its range.
      std::vector<HlsCue> cues;
      ResetCueValues(*track, cues);
      track->seeking = true;
      SendCues(*track, std::move(cues));
    }
  }

  void EndSeeking() {
    if (TextTrack* track = current_text_track_) {
      track->seeking = false;
    }
  }

  std::vector<HlsTrack> Tracks() const { return reported_; }

  // Legible output callbacks, on the owner sequence.
  void ProcessCue(NSArray* strings, NSArray* samples, double time) {
    TextTrack* track = current_text_track_;
    if (!track) {
      return;
    }
    std::vector<HlsCue> cues;
    ProcessAttributedStrings(*track, strings, time, cues);
    if (samples.count) {
      ProcessVttSamples(*track, samples, time, cues);
    }
    SendCues(*track, std::move(cues));
  }

  void FlushCues() {
    if (TextTrack* track = current_text_track_) {
      std::vector<HlsCue> cues;
      ResetCueValues(*track, cues);
      SendCues(*track, std::move(cues));
    }
  }

 private:
  // AudioTrackPrivateAVFObjC over AVTrackPrivateAVFObjCImpl.
  struct AudioTrack {
    AVMediaSelectionOption* option = nil;  // Group path.
    AVPlayerItemTrack* item_track = nil;   // No audible group.
    AVAssetTrack* asset_track = nil;       // Fixed when the track is made.
    bool enabled = false;                  // The private's flag.
    HlsTrack info;
  };

  // InbandTextTrackPrivateAVFObjC over InbandTextTrackPrivateAVF.
  struct TextTrack {
    enum class PendingCueStatus { kNone, kDeliveredDuringSeek, kValid };
    AVMediaSelectionOption* option = nil;
    uint64_t number = 0;  // m_currentTextTrackID when made.
    HlsTextTrackMode mode = HlsTextTrackMode::kDisabled;
    int64_t index = 0;
    std::vector<GenericCue> cues;
    PendingCueStatus pending = PendingCueStatus::kNone;
    double current_cue_start = 0;
    double current_cue_end = 0;
    bool seeking = false;
    bool reported_vtt_header = false;
    std::vector<uint8_t> sample_input;
    HlsTrack info;
  };

  // MediaSelectionGroupAVFObjC (the audible group only: WebKit gives the
  // legible group to its text tracks directly).
  struct SelectionGroup {
    AVMediaSelectionGroup* group = nil;
    std::vector<AVMediaSelectionOption*> options;  // m_options' keys.
    AVMediaSelectionOption* selected = nil;
    bool should_select_automatically = true;
    uint64_t timer_generation = 0;
    bool Contains(AVMediaSelectionOption* option) const {
      return std::find(options.begin(), options.end(), option) != options.end();
    }
  };

  static dispatch_queue_t LegibleQueue() {
    static dispatch_queue_t queue = dispatch_queue_create("parc.fairplay.hls-legible", DISPATCH_QUEUE_SERIAL);
    return queue;
  }

  bool HasLoadedMediaSelectionGroups() const {
    return asset_ && [asset_ statusOfValueForKey:kMediaSelectionKey error:nil] == AVKeyValueStatusLoaded;
  }

  AVMediaSelectionGroup* LegibleGroup() const {
    return HasLoadedMediaSelectionGroups()
               ? [asset_ mediaSelectionGroupForMediaCharacteristic:AVMediaCharacteristicLegible]
               : nil;
  }

  AVMediaSelectionGroup* AudibleGroup() const {
    return HasLoadedMediaSelectionGroups()
               ? [asset_ mediaSelectionGroupForMediaCharacteristic:AVMediaCharacteristicAudible]
               : nil;
  }

  AVMediaSelectionGroup* VisualGroup() const {
    return HasLoadedMediaSelectionGroups()
               ? [asset_ mediaSelectionGroupForMediaCharacteristic:AVMediaCharacteristicVisual]
               : nil;
  }

  // MediaSelectionOptionAVFObjC::assetTrack.
  AVAssetTrack* AssetTrackForOption(AVMediaSelectionOption* option) const {
    if ([option respondsToSelector:@selector(track)]) {
      if (AVAssetTrack* track = [option track]) {
        return track;
      }
    }
    if (audible_group_ && audible_group_->selected == option) {
      for (AVPlayerItemTrack* track in item_.tracks) {
        if (!track.enabled || !track.assetTrack) {
          continue;
        }
        if ([track.assetTrack.mediaType isEqualToString:option.mediaType] &&
            track.assetTrack.playable == option.playable) {
          return track.assetTrack;
        }
      }
    }
    return nil;
  }

  // MediaSelectionGroupAVFObjC::updateOptions.
  void UpdateGroupOptions(SelectionGroup& group, NSArray<NSString*>* characteristics) {
    NSSet* new_options = [NSSet setWithArray:[AVMediaSelectionGroup
                                                 playableMediaSelectionOptionsFromArray:group.group.options]];
    NSMutableSet* old_options = [NSMutableSet set];
    for (AVMediaSelectionOption* option : group.options) {
      [old_options addObject:option];
    }
    NSMutableSet* added = [new_options mutableCopy];
    [added minusSet:old_options];
    NSMutableSet* removed = [old_options mutableCopy];
    [removed minusSet:new_options];

    for (AVMediaSelectionOption* option in removed) {
      if (group.selected && option == group.selected) {
        group.selected = nil;
      }
      group.options.erase(std::remove(group.options.begin(), group.options.end(), option), group.options.end());
    }
    AVMediaSelectionOption* item_selected = [item_ selectedMediaOptionInMediaSelectionGroup:group.group];
    // Keep AVFoundation's order for the options added together.
    for (AVMediaSelectionOption* option in group.group.options) {
      if (![added containsObject:option] || group.Contains(option)) {
        continue;
      }
      group.options.push_back(option);
      if (option == item_selected) {
        group.selected = option;
      }
    }

    if (!group.should_select_automatically) {
      return;
    }
    NSArray<AVMediaSelectionOption*>* filtered =
        [AVMediaSelectionGroup mediaSelectionOptionsFromArray:group.group.options
                  filteredAndSortedAccordingToPreferredLanguages:UserPreferredLanguages()];
    if (!filtered.count && !characteristics.count) {
      return;
    }
    // No option in the user's languages: match the characteristics across
    // all of the group's options.
    if (!filtered.count) {
      filtered = group.group.options;
    }
    NSArray<AVMediaSelectionOption*>* with_characteristics =
        [AVMediaSelectionGroup mediaSelectionOptionsFromArray:filtered withMediaCharacteristics:characteristics];
    if (with_characteristics.count) {
      filtered = with_characteristics;
    }
    if (!filtered.count) {
      return;
    }
    AVMediaSelectionOption* preferred = filtered.firstObject;
    if (group.selected && group.selected == preferred) {
      return;
    }
    group.selected = group.Contains(preferred) ? preferred : nil;
    StartSelectionTimer(group);
  }

  // MediaSelectionGroupAVFObjC::setSelectedOption.
  void SetGroupSelectedOption(SelectionGroup& group, AVMediaSelectionOption* option) {
    if (group.selected == option) {
      return;
    }
    group.should_select_automatically = false;
    group.selected = option;
    StartSelectionTimer(group);
  }

  // MediaSelectionOptionAVFObjC::setSelected.
  void SetOptionSelected(AVMediaSelectionOption* option, bool selected) {
    if (!audible_group_ || !audible_group_->Contains(option)) {
      return;
    }
    bool is_selected = audible_group_->selected == option;
    if (selected == is_selected) {
      return;
    }
    SetGroupSelectedOption(*audible_group_, selected ? option : nil);
  }

  // The group's zero-delay selection timer: restarting it supersedes a
  // pending firing.
  void StartSelectionTimer(SelectionGroup& group) {
    uint64_t generation = ++group.timer_generation;
    std::weak_ptr<Impl> weak = weak_from_this();
    (*poster_)([weak, generation] {
      auto impl = weak.lock();
      if (!impl || !impl->audible_group_ || impl->audible_group_->timer_generation != generation) {
        return;
      }
      impl->SelectionTimerFired(*impl->audible_group_);
    });
  }

  void SelectionTimerFired(SelectionGroup& group) {
    if (!item_) {
      return;
    }
    @try {
      [item_ selectMediaOption:group.selected inMediaSelectionGroup:group.group];
    } @catch (NSException*) {
      // WebKit reports and continues.
    }
  }

  // MediaPlayerPrivateAVFoundationObjC::updateAudioTracks.
  void UpdateAudioTracks() {
    NSArray<NSString*>* characteristics = PreferredAudioCharacteristics();
    if (!audible_group_) {
      if (AVMediaSelectionGroup* group = AudibleGroup()) {
        audible_group_ = std::make_unique<SelectionGroup>();
        audible_group_->group = group;
        UpdateGroupOptions(*audible_group_, characteristics);
      }
    }
    if (audible_group_) {
      UpdateAudioTracksFromGroup(characteristics);
    } else {
      UpdateAudioTracksFromItemTracks();
    }
    for (auto& track : audio_tracks_) {
      ResetPropertiesFromTrack(*track);
    }
  }

  // determineChangedTracksFromNewTracksAndOldItems for a selection group.
  void UpdateAudioTracksFromGroup(NSArray<NSString*>* characteristics) {
    SelectionGroup& group = *audible_group_;
    UpdateGroupOptions(group, characteristics);
    std::vector<std::unique_ptr<AudioTrack>> replacement;
    for (auto& track : audio_tracks_) {
      if (track->option && group.Contains(track->option)) {
        replacement.push_back(std::move(track));
      }
    }
    for (AVMediaSelectionOption* option : group.options) {
      bool known = std::any_of(replacement.begin(), replacement.end(),
                               [option](const auto& track) { return track->option == option; });
      if (known) {
        continue;
      }
      auto track = std::make_unique<AudioTrack>();
      track->option = option;
      track->asset_track = AssetTrackForOption(option);
      track->info.key = "audio-" + std::to_string(next_audio_key_++);
      replacement.push_back(std::move(track));
    }
    audio_tracks_ = std::move(replacement);
  }

  // determineChangedTracksFromNewTracksAndOldItems for the item's audio
  // tracks (no audible group).
  void UpdateAudioTracksFromItemTracks() {
    NSMutableArray<AVPlayerItemTrack*>* tracks = [NSMutableArray array];
    for (AVPlayerItemTrack* track in cached_tracks_) {
      if ([track.assetTrack.mediaType isEqualToString:AVMediaTypeAudio]) {
        [tracks addObject:track];
      }
    }
    std::vector<std::unique_ptr<AudioTrack>> replacement;
    for (auto& track : audio_tracks_) {
      if (track->item_track && [tracks containsObject:track->item_track]) {
        replacement.push_back(std::move(track));
      }
    }
    for (AVPlayerItemTrack* item_track in tracks) {
      bool known = std::any_of(replacement.begin(), replacement.end(),
                               [item_track](const auto& track) { return [track->item_track isEqual:item_track]; });
      if (known) {
        continue;
      }
      auto track = std::make_unique<AudioTrack>();
      track->item_track = item_track;
      track->asset_track = item_track.assetTrack;
      track->info.key = "audio-" + std::to_string(next_audio_key_++);
      replacement.push_back(std::move(track));
    }
    audio_tracks_ = std::move(replacement);
  }

  // AudioTrackPrivateAVFObjC::resetPropertiesFromTrack.
  void ResetPropertiesFromTrack(AudioTrack& track) {
    track.enabled = AudioEnabled(track);
    HlsTrack& info = track.info;
    info.type = HlsTrackType::kAudio;
    info.enabled = track.enabled;
    info.index = AudioIndex(track);
    info.kind = AudioKind(track);
    info.id = AudioId(track);
    info.label = AudioLabel(track);
    info.language = AudioLanguage(track);
  }

  bool AudioEnabled(const AudioTrack& track) const {
    if (track.item_track) {
      return track.item_track.enabled;
    }
    return audible_group_ && track.option && audible_group_->selected == track.option;
  }

  // AVTrackPrivateAVFObjCImpl::index.
  int64_t AudioIndex(const AudioTrack& track) const {
    NSUInteger index = NSNotFound;
    if (track.asset_track) {
      index = [track.asset_track.asset.tracks indexOfObject:track.asset_track];
    } else if (track.option && audible_group_) {
      index = [audible_group_->group.options indexOfObject:track.option];
    }
    // TrackPrivateBase keeps an int.
    return static_cast<int>(index);
  }

  // AVTrackPrivateAVFObjCImpl::audioKind.
  std::string AudioKind(const AudioTrack& track) const {
    if (track.asset_track) {
      bool describes = [track.asset_track hasMediaCharacteristic:AVMediaCharacteristicDescribesVideoForAccessibility];
      if (!describes && track.option &&
          [track.option hasMediaCharacteristic:AVMediaCharacteristicDescribesVideoForAccessibility]) {
        return "description";
      }
      if ([track.asset_track hasMediaCharacteristic:AVMediaCharacteristicIsAuxiliaryContent]) {
        return "alternative";
      }
      if (describes) {
        return "description";
      }
      if ([track.asset_track hasMediaCharacteristic:AVMediaCharacteristicIsMainProgramContent]) {
        return "main";
      }
      return "";
    }
    if (track.option) {
      if ([track.option hasMediaCharacteristic:AVMediaCharacteristicIsAuxiliaryContent]) {
        return "alternative";
      }
      if ([track.option hasMediaCharacteristic:AVMediaCharacteristicDescribesVideoForAccessibility]) {
        return "description";
      }
      if ([track.option hasMediaCharacteristic:AVMediaCharacteristicIsMainProgramContent]) {
        return "main";
      }
    }
    return "";
  }

  // AVTrackPrivateAVFObjCImpl::id, as TrackBase prints it.
  std::string AudioId(const AudioTrack& track) const {
    if (track.asset_track) {
      return std::to_string(track.asset_track.trackID);
    }
    if (track.option && [track.option respondsToSelector:@selector(optionID)]) {
      id option_id = [track.option optionID];
      if ([option_id respondsToSelector:@selector(unsignedLongLongValue)]) {
        return std::to_string([option_id unsignedLongLongValue]);
      }
    }
    return "0";
  }

  std::string AudioLabel(const AudioTrack& track) const {
    NSArray<AVMetadataItem*>* common_metadata = nil;
    if (track.asset_track) {
      common_metadata = track.asset_track.commonMetadata;
    }
    if (!common_metadata.count && track.option) {
      common_metadata = track.option.commonMetadata;
    }
    return TitleFromCommonMetadata(common_metadata);
  }

  std::string AudioLanguage(const AudioTrack& track) const {
    if (track.asset_track) {
      std::string language = LanguageForAssetTrack(track.asset_track);
      if (!language.empty()) {
        return language;
      }
    }
    if (track.option) {
      return LanguageForOption(track.option);
    }
    return {};
  }

  // MediaPlayerPrivateAVFoundationObjC::processMediaSelectionOptions.
  void ProcessMediaSelectionOptions() {
    AVMediaSelectionGroup* legible_group = LegibleGroup();
    if (!legible_group) {
      return;
    }
    // Text tracks are chosen by the page, never automatically.
    if (text_tracks_.empty()) {
      @try {
        [item_ selectMediaOption:nil inMediaSelectionGroup:legible_group];
      } @catch (NSException*) {
      }
    }
    std::vector<TextTrack*> removed;
    for (auto& track : text_tracks_) {
      removed.push_back(track.get());
    }
    NSArray<AVMediaSelectionOption*>* options =
        [AVMediaSelectionGroup playableMediaSelectionOptionsFromArray:legible_group.options];
    for (AVMediaSelectionOption* option in options) {
      bool new_track = true;
      for (size_t i = removed.size(); i > 0; --i) {
        if ([removed[i - 1]->option isEqual:option]) {
          removed.erase(removed.begin() + static_cast<std::ptrdiff_t>(i - 1));
          new_track = false;
          break;
        }
      }
      if (!new_track) {
        continue;
      }
      auto track = std::make_unique<TextTrack>();
      track->option = option;
      track->number = next_text_track_number_++;
      text_tracks_.push_back(std::move(track));
    }
    ProcessNewAndRemovedTextTracks(legible_group, removed);
  }

  // MediaPlayerPrivateAVFoundation::processNewAndRemovedTextTracks.
  void ProcessNewAndRemovedTextTracks(AVMediaSelectionGroup* legible_group, const std::vector<TextTrack*>& removed) {
    for (TextTrack* track : removed) {
      if (current_text_track_ == track) {
        current_text_track_ = nullptr;
      }
    }
    text_tracks_.erase(std::remove_if(text_tracks_.begin(), text_tracks_.end(),
                                      [&removed](const auto& track) {
                                        return std::find(removed.begin(), removed.end(), track.get()) !=
                                               removed.end();
                                      }),
                       text_tracks_.end());
    int64_t in_band_count = 0;
    for (auto& track : text_tracks_) {
      track->index = in_band_count++;
      FillTextTrackInfo(legible_group, *track);
    }
  }

  void FillTextTrackInfo(AVMediaSelectionGroup* legible_group, TextTrack& track) {
    AVMediaSelectionOption* option = track.option;
    HlsTrack& info = track.info;
    info.type = HlsTrackType::kText;
    info.key = "text-" + std::to_string(track.number);
    info.id = std::to_string(track.number);
    info.kind = TextKindForOption(option);
    info.label = TitleFromCommonMetadata(option.commonMetadata);
    info.language = LanguageForOption(option);
    info.enabled = false;
    info.index = track.index;
    info.is_default = legible_group.defaultOption == option;
    bool subtitle = [option.mediaType isEqualToString:AVMediaTypeSubtitle];
    info.is_closed_captions = [option.mediaType isEqualToString:AVMediaTypeClosedCaption];
    info.is_sdh =
        subtitle &&
        [option hasMediaCharacteristic:AVMediaCharacteristicTranscribesSpokenDialogForAccessibility] &&
        [option hasMediaCharacteristic:AVMediaCharacteristicDescribesMusicAndSoundForAccessibility];
    info.contains_only_forced_subtitles =
        [option hasMediaCharacteristic:AVMediaCharacteristicContainsOnlyForcedSubtitles];
    info.is_main_program_content = [option hasMediaCharacteristic:AVMediaCharacteristicIsMainProgramContent];
    info.is_easy_to_read = [option hasMediaCharacteristic:AVMediaCharacteristicEasyToRead];
  }

  // MediaPlayerPrivateAVFoundation::configureInbandTracks: AVFoundation
  // emits cues for one track, the first showing one, else the last hidden.
  void ConfigureInbandTracks() {
    TextTrack* to_enable = nullptr;
    for (auto& track : text_tracks_) {
      if (track->mode == HlsTextTrackMode::kShowing) {
        to_enable = track.get();
        break;
      }
      if (track->mode == HlsTextTrackMode::kHidden) {
        to_enable = track.get();
      }
    }
    SetCurrentTextTrack(to_enable);
  }

  // MediaPlayerPrivateAVFoundationObjC::setCurrentTextTrack.
  void SetCurrentTextTrack(TextTrack* track) {
    if (current_text_track_ == track || !item_) {
      return;
    }
    if (track) {
      current_text_track_ = track;
      @try {
        [item_ selectMediaOption:track->option inMediaSelectionGroup:LegibleGroup()];
      } @catch (NSException*) {
      }
      return;
    }
    current_text_track_ = nullptr;
    @try {
      [item_ selectMediaOption:nil inMediaSelectionGroup:LegibleGroup()];
    } @catch (NSException*) {
    }
    player_.closedCaptionDisplayEnabled = NO;
  }

  // InbandTextTrackPrivateAVF::processAttributedStrings.
  void ProcessAttributedStrings(TextTrack& track, NSArray* strings, double time, std::vector<HlsCue>& out) {
    std::vector<GenericCue> arriving;
    for (id object in strings) {
      if (![object isKindOfClass:[NSAttributedString class]]) {
        continue;
      }
      NSAttributedString* string = object;
      if (!string.length) {
        continue;
      }
      GenericCue cue = ProcessCueAttributes(string, ++last_cue_id_);
      if (cue.content.empty()) {
        continue;
      }
      cue.start = time;
      cue.end = kInfinity;
      cue.status = GenericCue::Status::kPartial;
      arriving.push_back(std::move(cue));
    }

    if (track.pending != TextTrack::PendingCueStatus::kNone) {
      // A cue has no duration: it shows until the next one, maybe empty.
      track.current_cue_end = time;
      if (track.current_cue_end >= track.current_cue_start) {
        for (GenericCue& cue : track.cues) {
          // An arriving cue that matches this one extends it.
          std::vector<GenericCue> non_extension;
          for (auto& arriving_cue : arriving) {
            if (!arriving_cue.Extends(cue)) {
              non_extension.push_back(std::move(arriving_cue));
            }
          }
          bool extended = arriving.size() != non_extension.size();
          arriving = std::move(non_extension);
          if (extended) {
            continue;
          }
          if (track.pending == TextTrack::PendingCueStatus::kValid) {
            cue.end = track.current_cue_end;
            cue.status = GenericCue::Status::kComplete;
            out.push_back(cue.ToCue(HlsCue::Type::kUpdate));
          }
          // Cues delivered during a seek keep no end: AVFoundation may not
          // have decoded every cue in between.
        }
      }
      RemoveCompletedCues(track);
    }

    if (arriving.empty()) {
      return;
    }
    track.current_cue_start = time;
    for (auto& cue : arriving) {
      out.push_back(cue.ToCue(HlsCue::Type::kAdd));
      track.cues.push_back(std::move(cue));
    }
    track.pending =
        track.seeking ? TextTrack::PendingCueStatus::kDeliveredDuringSeek : TextTrack::PendingCueStatus::kValid;
  }

  void RemoveCompletedCues(TextTrack& track) {
    track.cues.erase(std::remove_if(track.cues.begin(), track.cues.end(),
                                    [](const GenericCue& cue) {
                                      return cue.status == GenericCue::Status::kComplete;
                                    }),
                     track.cues.end());
    if (track.cues.empty()) {
      track.pending = TextTrack::PendingCueStatus::kNone;
    }
    track.current_cue_start = 0;
    track.current_cue_end = 0;
  }

  // InbandTextTrackPrivateAVF::resetCueValues.
  void ResetCueValues(TextTrack& track, std::vector<HlsCue>& out) {
    for (const GenericCue& cue : track.cues) {
      out.push_back(cue.ToCue(HlsCue::Type::kRemove));
    }
    track.cues.clear();
    track.pending = TextTrack::PendingCueStatus::kNone;
    track.current_cue_start = 0;
    track.current_cue_end = 0;
  }

  void ProcessVttSamples(TextTrack& track, NSArray* samples, double time, std::vector<HlsCue>& out) {
    for (id sample in samples) {
      CMSampleBufferRef buffer = (__bridge CMSampleBufferRef)sample;
      if (buffer && CFGetTypeID(buffer) == CMSampleBufferGetTypeID()) {
        ProcessVttSample(track, buffer, time, out);
      }
    }
  }

  // InbandTextTrackPrivateAVF::processVTTSample.
  void ProcessVttSample(TextTrack& track, CMSampleBufferRef sample, double time, std::vector<HlsCue>& out) {
    CMFormatDescriptionRef format_description = nullptr;
    if (!ReadVttSampleBuffer(track, sample, &format_description)) {
      return;
    }
    CMSampleTimingInfo timing;
    if (CMSampleBufferGetSampleTimingInfo(sample, 0, &timing) != noErr) {
      return;
    }
    double duration = CMTIME_IS_NUMERIC(timing.duration) ? CMTimeGetSeconds(timing.duration)
                                                         : std::numeric_limits<double>::quiet_NaN();
    while (true) {
      auto box = ParseBoxHeader(track.sample_input, 0);
      if (!box) {
        break;
      }
      if (box->size > track.sample_input.size()) {
        break;
      }
      if (!track.reported_vtt_header && format_description) {
        track.reported_vtt_header = ProcessVttFileHeader(format_description, out);
      }
      if (box->type == FourCC("vttc")) {
        HlsCue cue;
        cue.type = HlsCue::Type::kWebVtt;
        cue.start = time;
        cue.end = time + duration;
        ParseWebVttCue(track.sample_input, cue);
        out.push_back(std::move(cue));
      }
      track.sample_input.erase(track.sample_input.begin(),
                               track.sample_input.begin() + static_cast<std::ptrdiff_t>(box->size));
    }
  }

  bool ReadVttSampleBuffer(TextTrack& track, CMSampleBufferRef sample, CMFormatDescriptionRef* format_description) {
    CMBlockBufferRef block = CMSampleBufferGetDataBuffer(sample);
    size_t length = block ? CMBlockBufferGetDataLength(block) : 0;
    // ISOBox::minimumBoxSize.
    if (length < 8) {
      return false;
    }
    size_t old_size = track.sample_input.size();
    track.sample_input.resize(old_size + length);
    if (CMBlockBufferCopyDataBytes(block, 0, length, track.sample_input.data() + old_size) != kCMBlockBufferNoErr) {
      track.sample_input.resize(old_size);
      return false;
    }
    *format_description = CMSampleBufferGetFormatDescription(sample);
    return true;
  }

  // InbandTextTrackPrivateAVF::processVTTFileHeader.
  bool ProcessVttFileHeader(CMFormatDescriptionRef format_description, std::vector<HlsCue>& out) {
    CFDictionaryRef extensions = CMFormatDescriptionGetExtensions(format_description);
    if (!extensions) {
      return false;
    }
    CFTypeRef atoms = CFDictionaryGetValue(extensions, kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms);
    if (!atoms || CFGetTypeID(atoms) != CFDictionaryGetTypeID()) {
      return false;
    }
    CFTypeRef header = CFDictionaryGetValue(static_cast<CFDictionaryRef>(atoms), CFSTR("vttC"));
    if (!header || CFGetTypeID(header) != CFDataGetTypeID()) {
      return false;
    }
    CFDataRef data = static_cast<CFDataRef>(header);
    if (!CFDataGetLength(data)) {
      return false;
    }
    HlsCue cue;
    cue.type = HlsCue::Type::kWebVttHeader;
    // A header ends with one or more line terminators.
    cue.text = Latin1ToUtf8(CFDataGetBytePtr(data), static_cast<size_t>(CFDataGetLength(data))) + "\n\n";
    out.push_back(std::move(cue));
    return true;
  }

  void SendCues(const TextTrack& track, std::vector<HlsCue> cues) {
    if (cues.empty()) {
      return;
    }
    std::weak_ptr<Impl> weak = weak_from_this();
    HlsMediaSelectionClient* client = client_;
    std::string key = track.info.key;
    (*poster_)([weak, client, key = std::move(key), cues = std::move(cues)] {
      if (weak.lock()) {
        client->OnTextCues(key, cues);
      }
    });
  }

  // The DOM lists: audio by index (AudioTrackList::append inserts after
  // equal indexes), text in in-band order.
  void ReportTracks() {
    std::vector<HlsTrack> tracks;
    std::vector<const AudioTrack*> audio;
    for (auto& track : audio_tracks_) {
      audio.push_back(track.get());
    }
    std::stable_sort(audio.begin(), audio.end(), [](const AudioTrack* a, const AudioTrack* b) {
      return static_cast<uint64_t>(static_cast<size_t>(a->info.index)) <
             static_cast<uint64_t>(static_cast<size_t>(b->info.index));
    });
    for (const AudioTrack* track : audio) {
      HlsTrack info = track->info;
      info.enabled = track->enabled;
      tracks.push_back(std::move(info));
    }
    for (auto& track : text_tracks_) {
      tracks.push_back(track->info);
    }
    MarkAutomaticTextTrack(tracks);
    if (tracks == reported_) {
      return;
    }
    reported_ = tracks;
    std::weak_ptr<Impl> weak = weak_from_this();
    HlsMediaSelectionClient* client = client_;
    (*poster_)([weak, client, tracks = std::move(tracks)] {
      if (weak.lock()) {
        client->OnTracksChanged(tracks);
      }
    });
  }

  // HTMLMediaElement::configureTextTrackGroup for the in-band captions and
  // subtitles group, as on the element's first configuration (no track
  // showing yet): the track it would show, marked |automatic|. The element
  // shows that one (ParcInbandTextTrack::IsDefault) and leaves the others.
  static void MarkAutomaticTextTrack(std::vector<HlsTrack>& tracks) {
    std::string audio_language;
    bool any_text = false;
    for (const HlsTrack& track : tracks) {
      if (track.type == HlsTrackType::kAudio && track.enabled && audio_language.empty()) {
        audio_language = track.language;
      }
      any_text |= track.type == HlsTrackType::kText;
    }
    if (!any_text) {
      return;
    }
    const CaptionPreferences preferences = ReadCaptionPreferences();
    const bool forced_only_mode =
        preferences.display_mode == CaptionPreferences::DisplayMode::kForcedOnly;
    HlsTrack* to_enable = nullptr;
    HlsTrack* default_track = nullptr;
    HlsTrack* fallback = nullptr;
    HlsTrack* forced = nullptr;
    int highest = 0;
    int highest_forced = 0;
    for (HlsTrack& track : tracks) {
      if (track.type != HlsTrackType::kText) {
        continue;
      }
      track.automatic = false;
      const int score = TextTrackSelectionScore(track, preferences, audio_language);
      if (score) {
        if (score > highest) {
          highest = score;
          to_enable = &track;
        }
        if (!default_track && track.is_default) {
          default_track = &track;
        }
        if (!default_track && !fallback) {
          fallback = &track;
        }
        if (track.contains_only_forced_subtitles && score > highest_forced) {
          forced = &track;
          highest_forced = score;
        }
      } else if (!default_track && track.is_default && !forced_only_mode) {
        default_track = &track;
      }
    }
    if (!to_enable) {
      to_enable = default_track;
    }
    if (!to_enable) {
      to_enable = forced;
    }
    if (!to_enable) {
      to_enable = fallback;
    }
    if (to_enable) {
      to_enable->automatic = true;
    }
  }

  AudioTrack* FindAudioTrack(const std::string& key) {
    for (auto& track : audio_tracks_) {
      if (track->info.key == key) {
        return track.get();
      }
    }
    return nullptr;
  }

  TextTrack* FindTextTrack(const std::string& key) {
    for (auto& track : text_tracks_) {
      if (track->info.key == key) {
        return track.get();
      }
    }
    return nullptr;
  }

  HlsMediaSelectionClient* const client_;
  const std::shared_ptr<const PostTask> poster_;
  AVPlayer* player_ = nil;
  AVPlayerItem* item_ = nil;
  AVAsset* asset_ = nil;
  AVPlayerItemLegibleOutput* legible_output_ = nil;
  PCHlsSelectionObserver* observer_ = nil;
  NSArray<AVPlayerItemTrack*>* cached_tracks_ = nil;
  std::unique_ptr<SelectionGroup> audible_group_;
  std::vector<std::unique_ptr<AudioTrack>> audio_tracks_;
  std::vector<std::unique_ptr<TextTrack>> text_tracks_;
  TextTrack* current_text_track_ = nullptr;
  uint64_t next_text_track_number_ = 0;
  uint64_t next_audio_key_ = 0;
  uint64_t last_cue_id_ = 0;
  std::vector<HlsTrack> reported_;
};

HlsMediaSelection::HlsMediaSelection(HlsMediaSelectionClient* client, PostTask post_task)
    : impl_(std::make_shared<Impl>(client, std::move(post_task))) {}

HlsMediaSelection::~HlsMediaSelection() {
  impl_->Detach();
}

void HlsMediaSelection::SetAudioTrackEnabled(const std::string& key, bool enabled) {
  impl_->SetAudioTrackEnabled(key, enabled);
}

void HlsMediaSelection::SetTextTrackMode(const std::string& key, HlsTextTrackMode mode) {
  impl_->SetTextTrackMode(key, mode);
}

void HlsMediaSelection::BeginSeeking() {
  impl_->BeginSeeking();
}

void HlsMediaSelection::EndSeeking() {
  impl_->EndSeeking();
}

std::vector<HlsTrack> HlsMediaSelection::Tracks() const {
  return impl_->Tracks();
}

void HlsMediaSelectionAttach(HlsMediaSelection::Impl* selection, AVPlayer* player, AVPlayerItem* item) {
  selection->Attach(player, item);
}

}  // namespace parc::fairplay

namespace {
void* const kTracksContext = const_cast<void**>(&kTracksContext);
void* const kTrackEnabledContext = const_cast<void**>(&kTrackEnabledContext);
}  // namespace

@implementation PCHlsSelectionObserver {
  std::weak_ptr<parc::fairplay::HlsMediaSelection::Impl> _impl;
  std::shared_ptr<const parc::fairplay::PostTask> _poster;
  AVPlayerItem* _item;
  NSArray<AVPlayerItemTrack*>* _tracks;
  BOOL _stopped;
  std::atomic<bool> _stopping;
}

- (instancetype)initWithImpl:(std::weak_ptr<parc::fairplay::HlsMediaSelection::Impl>)impl
                      poster:(std::shared_ptr<const parc::fairplay::PostTask>)poster {
  if ((self = [super init])) {
    _impl = std::move(impl);
    _poster = std::move(poster);
  }
  return self;
}

- (void)observeItem:(AVPlayerItem*)item {
  @synchronized(self) {
    if (_stopped || _item) {
      return;
    }
    _item = item;
    [item addObserver:self forKeyPath:@"tracks" options:0 context:kTracksContext];
  }
}

- (void)observeTracks:(NSArray<AVPlayerItemTrack*>*)tracks {
  @synchronized(self) {
    if (_stopped) {
      return;
    }
    for (AVPlayerItemTrack* track in _tracks) {
      [track removeObserver:self forKeyPath:@"enabled" context:kTrackEnabledContext];
    }
    _tracks = [tracks copy];
    for (AVPlayerItemTrack* track in _tracks) {
      [track addObserver:self forKeyPath:@"enabled" options:0 context:kTrackEnabledContext];
    }
  }
}

- (void)stop {
  _stopping.store(true);
  @synchronized(self) {
    if (_stopped) {
      return;
    }
    _stopped = YES;
    for (AVPlayerItemTrack* track in _tracks) {
      [track removeObserver:self forKeyPath:@"enabled" context:kTrackEnabledContext];
    }
    _tracks = nil;
    [_item removeObserver:self forKeyPath:@"tracks" context:kTracksContext];
    _item = nil;
  }
}

- (void)observeValueForKeyPath:(NSString*)keyPath
                      ofObject:(id)object
                        change:(NSDictionary*)change
                       context:(void*)context {
  // Read without the lock: observeTracks: and stop hold it while adding and
  // removing observers.
  if ((context == kTracksContext || context == kTrackEnabledContext) && _stopping.load()) {
    return;
  }
  if (context == kTracksContext) {
    std::weak_ptr<parc::fairplay::HlsMediaSelection::Impl> weak = _impl;
    (*_poster)([weak] {
      if (auto impl = weak.lock()) {
        impl->TracksDidChange();
      }
    });
  } else if (context == kTrackEnabledContext) {
    std::weak_ptr<parc::fairplay::HlsMediaSelection::Impl> weak = _impl;
    (*_poster)([weak] {
      if (auto impl = weak.lock()) {
        impl->TracksChanged();
      }
    });
  } else {
    [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
  }
}

- (void)legibleOutput:(AVPlayerItemLegibleOutput*)output
    didOutputAttributedStrings:(NSArray<NSAttributedString*>*)strings
           nativeSampleBuffers:(NSArray*)nativeSamples
                   forItemTime:(CMTime)itemTime {
  double time = CMTIME_IS_NUMERIC(itemTime) ? std::max(CMTimeGetSeconds(itemTime), 0.0) : 0.0;
  std::weak_ptr<parc::fairplay::HlsMediaSelection::Impl> weak = _impl;
  NSArray* retained_strings = strings;
  NSArray* retained_samples = nativeSamples;
  (*_poster)([weak, retained_strings, retained_samples, time] {
    if (auto impl = weak.lock()) {
      impl->ProcessCue(retained_strings, retained_samples, time);
    }
  });
}

- (void)outputSequenceWasFlushed:(AVPlayerItemOutput*)output {
  std::weak_ptr<parc::fairplay::HlsMediaSelection::Impl> weak = _impl;
  (*_poster)([weak] {
    if (auto impl = weak.lock()) {
      impl->FlushCues();
    }
  });
}

@end
