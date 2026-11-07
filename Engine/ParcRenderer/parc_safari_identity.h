// Copyright 2026 Parc contributors.
// Parc presents Safari's identity to the sites that need Apple FairPlay
// (docs/fairplay-identity.md). The browser chooses it per navigation through
// Chromium's user agent override, which also drops the UA client hints, so a
// document, the frames sharing its process and its workers see Safari's user
// agent string. The rest of what Safari lacks or reports differently follows
// from that string here, so every surface of one context stays consistent:
// navigator.vendor, no navigator.userAgentData, no Widevine, Dolby audio
// (AC-3, E-AC-3) and FairPlay's init data types offered only there.
// Installed at third_party/blink/renderer/core/frame/parc_safari_identity.h.
#ifndef THIRD_PARTY_BLINK_RENDERER_CORE_FRAME_PARC_SAFARI_IDENTITY_H_
#define THIRD_PARTY_BLINK_RENDERER_CORE_FRAME_PARC_SAFARI_IDENTITY_H_

#include <cstdint>
#include <limits>
#include <optional>

#include "third_party/blink/renderer/platform/wtf/text/ascii_ctype.h"
#include "third_party/blink/renderer/platform/wtf/text/string_builder.h"
#include "third_party/blink/renderer/platform/wtf/text/string_view.h"
#include "third_party/blink/renderer/platform/wtf/text/wtf_string.h"

namespace blink {

// Safari's user agent ends "Version/27.2 Safari/605.1.15" after WebKit's
// "AppleWebKit/605.1.15". Chromium-based and other browsers that mention
// Safari also name themselves, so a Safari user agent is one with all three
// and none of those names. A DevTools override with Safari's user agent
// matches too, which makes that emulation faithful.
inline bool IsParcSafariIdentityUserAgent(const String& user_agent) {
  return user_agent.contains("AppleWebKit/") &&
         user_agent.contains(" Version/") && user_agent.contains(" Safari/") &&
         !user_agent.contains("Chrome/") && !user_agent.contains("Chromium/") &&
         !user_agent.contains("CriOS/") && !user_agent.contains("FxiOS/") &&
         !user_agent.contains("EdgiOS/");
}

// Key systems Safari never offers. Sites probe Widevine before FairPlay and
// choose it when it answers, so it must be absent under Safari's identity.
inline bool IsParcSafariHiddenKeySystem(const String& key_system) {
  return key_system == "com.widevine.alpha" ||
         key_system.starts_with("com.widevine.alpha.");
}

// AC-3 and E-AC-3 (Dolby Digital and Dolby Digital Plus), and ALAC (Apple
// Lossless). Safari plays them, so Parc answers yes for them only under
// Safari's identity and every other page keeps Chromium's usual answer. `codecs` is a codecs parameter value
// without quotes ("avc1.640028,ec-3"), as ContentType and ParsedContentType
// give it.
inline bool IsParcSafariOnlyAudioCodecs(const String& codecs) {
  if (codecs.empty()) {
    return false;
  }
  for (const String& codec : codecs.Split(',')) {
    const String id = codec.StripWhiteSpace();
    if (EqualIgnoringAsciiCase(id, "ac-3") ||
        EqualIgnoringAsciiCase(id, "ec-3") ||
        EqualIgnoringAsciiCase(id, "mp4a.a5") ||
        EqualIgnoringAsciiCase(id, "mp4a.a6") ||
        EqualIgnoringAsciiCase(id, "alac")) {
      return true;
    }
  }
  return false;
}

// Whether Safari's WebCodecs decodes a Safari-only audio codec: AC-3 and
// E-AC-3 as the platform decoder takes them, ALAC never
// (AudioDecoderCocoa::isCodecSupported lists no Apple Lossless).
inline bool IsParcSafariWebCodecsAudioCodec(const String& codec) {
  return !EqualIgnoringAsciiCase(codec.StripWhiteSpace(), "alac");
}

// FairPlay's EME initialization data types, as WebKit registers them on
// macOS (CDMFairPlayStreaming.cpp): "sinf", which Safari's Media Source fires
// `encrypted` with, "skd", an HLS key URI, and "mpts", MPEG-2 TS content
// described as JSON. fairplay-media.patch adds them to media::EmeInitDataType;
// anywhere but under Safari's identity requestMediaKeySystemAccess and
// generateRequest treat them as the unregistered names they were before.
// Compared case-sensitively, as EME compares init data types.
inline bool IsParcSafariOnlyInitDataType(const String& init_data_type) {
  return init_data_type == "sinf" || init_data_type == "skd" ||
         init_data_type == "mpts";
}

// Values of WebKit's EME IDL enums that Blink declares as DOMString:
// MediaKeyEncryptionScheme ("cenc", "cbcs"; MediaKeyEncryptionScheme.idl) and
// MediaKeySessionType (MediaKeySessionType.idl). Under Safari's identity any
// other value in a requestMediaKeySystemAccess configuration is a TypeError,
// as WebKit's bindings throw while converting the dictionary.
inline bool IsParcSafariEncryptionScheme(const String& encryption_scheme) {
  return encryption_scheme == "cenc" || encryption_scheme == "cbcs";
}

inline bool IsParcSafariSessionType(const String& session_type) {
  return session_type == "temporary" ||
         session_type == "persistent-usage-record" ||
         session_type == "persistent-license";
}

// FairPlay Streaming's key system names, matched as WebKit matches them
// (CDMFactoryFairPlayStreaming::supportsKeySystem): case-sensitive,
// "com.apple.fps" or any name under "com.apple.fps.".
inline bool IsParcFairPlayKeySystem(const String& key_system) {
  return key_system == "com.apple.fps" ||
         key_system.starts_with("com.apple.fps.");
}

// Safari's "persistent-usage-record" MediaKeySessionType, which
// fairplay-media.patch adds to MediaKeys.idl and Chromium's session types.
// Anywhere but under Safari's identity, requestMediaKeySystemAccess treats it
// as the unknown session type it was before and createSession() throws the
// enum's TypeError for it. Under Safari's identity the key system selector
// applies WebKit's FairPlay session type and persistent state rules to
// IsParcFairPlayKeySystem names.
inline bool IsParcSafariOnlySessionType(const String& session_type) {
  return session_type == "persistent-usage-record";
}

// WebKit's SpatialAudioPlaybackHelper::supportsSpatialAudioPlaybackForConfiguration
// on macOS, which MediaCapabilities.decodingInfo asks for an audio
// configuration with spatialRendering: the default output device's spatial
// audio sources (AudioGetDeviceSpatialPreferencesForContentType, read by the
// browser) against the configuration's channel count. Multichannel sources
// spatialize more than two channels; mono or stereo sources spatialize at
// least one.
inline bool IsParcSafariSpatialAudioSupported(const auto& sources,
                                              double channels) {
  constexpr uint32_t kSpatialAudioSourceMultichannel = 0x6d6c7469;  // 'mlti'
  constexpr uint32_t kSpatialAudioSourceMonoOrStereo = 0x6d6f7374;  // 'most'
  for (const uint32_t source : sources) {
    if (source == kSpatialAudioSourceMultichannel && channels > 2) {
      return true;
    }
    if (source == kSpatialAudioSourceMonoOrStereo && channels >= 1) {
      return true;
    }
  }
  return false;
}

// The MPEG-2 TS container names Safari's Media Source takes: those
// AVStreamDataParser lists in audiovisualMIMETypes on macOS 27.2
// (AVStreamDataParserMIMETypeCache::initializeCache), compared exactly as
// MIMETypeCache::supportsContainerType does. AVStreamDataParser reads 188-byte
// TS packets under every one of them, as Chromium's video/mp2t parser does.
inline bool IsParcSafariMediaSourceMp2tType(const String& mime_type) {
  return mime_type == "video/mp2t" || mime_type == "video/x-mp2t" ||
         mime_type == "video/m2ts" || mime_type == "video/x-m2ts";
}

// strtoul() over `text` from `pos`, as AVStreamDataParser reads a codec's
// numbers: an optional sign, in base 16 an optional "0x", then digits.
// Advances `pos` past them; nullopt without a digit.
inline std::optional<uint64_t> ParcSafariCodecNumber(const String& text,
                                                     wtf_size_t& pos,
                                                     unsigned base) {
  wtf_size_t at = pos;
  bool negative = false;
  if (at < text.length() && (text[at] == '+' || text[at] == '-')) {
    negative = text[at] == '-';
    ++at;
  }
  if (base == 16 && at + 2 < text.length() && text[at] == '0' &&
      (text[at + 1] == 'x' || text[at + 1] == 'X') &&
      IsAsciiHexDigit(text[at + 2])) {
    at += 2;
  }
  const wtf_size_t digits = at;
  uint64_t value = 0;
  bool overflow = false;
  for (; at < text.length(); ++at) {
    const UChar c = text[at];
    if (base == 16 ? !IsAsciiHexDigit(c) : !IsAsciiDigit(c)) {
      break;
    }
    const unsigned digit = base == 16 ? ToAsciiHexValue(c) : c - '0';
    if (value > (std::numeric_limits<uint64_t>::max() - digit) / base) {
      overflow = true;
    }
    value = value * base + digit;
  }
  if (at == digits) {
    return std::nullopt;
  }
  pos = at;
  if (overflow) {
    return std::numeric_limits<uint64_t>::max();
  }
  return negative ? 0 - value : value;
}

// The codec ids of MPEG-2 TS media that both Safari's Media Source and Parc
// play: +[AVStreamDataParser canParseExtendedMIMEType:] on macOS 27.2 for
// H.264, AAC, MPEG-1 Layer I and II, AC-3 and E-AC-3, which Chromium's TS
// parser reads (AC-3 and E-AC-3 under Safari's identity only, through
// media::mp2t::ParcEsParserAc3) and its MP3 decoder plays Layers I and II
// through. AVFoundation refuses every MP3 id and HEVC there; it also takes
// "mp2v" and "mp1v", which Chromium can't decode. Matched as AVFoundation
// matches them:
// - H.264: "avc1" or "avc3", alone or followed by "." and anything, except
//   that six characters reading wholly as one hex number must give a
//   profile_idc of 66, 77, 88, 100, 110, 122 or 244 and a level_idc below 100.
// - AAC and MPEG-1 audio: "mp4a." with object type 0x40 then "." and audio
//   object type 2, 5, 29, 42, 32 (Layer I) or 33 (Layer II) and nothing more,
//   or object type 0x67 (MPEG-2 AAC LC) not followed by ".".
// - AC-3 and E-AC-3: "ac-3" or "ec-3", alone or followed by "." and anything.
inline bool IsParcSafariMp2tCodec(const String& codec) {
  if (codec.starts_with("ac-3") || codec.starts_with("ec-3")) {
    return codec.length() == 4 || codec[4] == '.';
  }
  if (codec.starts_with("avc1") || codec.starts_with("avc3")) {
    if (codec.length() == 4) {
      return true;
    }
    if (codec[4] != '.') {
      return false;
    }
    const String constraints = codec.substr(5);
    wtf_size_t end = 0;
    const std::optional<uint64_t> value =
        ParcSafariCodecNumber(constraints, end, 16);
    if (constraints.length() != 6 || !value || end != constraints.length()) {
      return true;
    }
    const uint64_t profile = *value >> 16;
    return (profile == 66 || profile == 77 || profile == 88 ||
            profile == 100 || profile == 110 || profile == 122 ||
            profile == 244) &&
           (*value & 0xff) < 100;
  }
  if (!codec.starts_with("mp4a.")) {
    return false;
  }
  wtf_size_t pos = 5;
  const std::optional<uint64_t> object_type =
      ParcSafariCodecNumber(codec, pos, 16);
  const bool dot = pos < codec.length() && codec[pos] == '.';
  if (object_type == 0x67) {
    return !dot;
  }
  if (object_type != 0x40 || !dot) {
    return false;
  }
  ++pos;
  const std::optional<uint64_t> audio_object_type =
      ParcSafariCodecNumber(codec, pos, 10);
  return pos == codec.length() &&
         (audio_object_type == 2 || audio_object_type == 5 ||
          audio_object_type == 29 || audio_object_type == 42 ||
          audio_object_type == 32 || audio_object_type == 33);
}

// For an MPEG-2 TS type (IsParcSafariMediaSourceMp2tType) with codecs
// parameter `codecs` under Safari's identity: nullopt where Safari's Media
// Source or Parc refuses it, else the codecs Chromium's video/mp2t parser is
// created with for it. As WebKit's MediaSource::isTypeSupported, a value
// listing no codec (MIMETypeCache::canDecodeType's MayBeSupported) is taken
// only when empty; otherwise AVFoundation splits it at commas and ASCII
// whitespace and every codec must pass IsParcSafariMp2tCodec. The parser keeps
// every stream regardless (Mp2tStreamParser::ParcIgnoreDeclaredCodecs()), so
// the ids returned only name the H.264, AAC and MPEG audio its factory
// accepts, keeping HE-AAC's SBR signal; without one (as for AC-3 and E-AC-3
// alone), empty codecs leave the parser to
// media::StreamParserFactory::ParcCreateWithoutCodecs().
inline std::optional<String> ParcSafariMp2tParserCodecs(const String& codecs) {
  const Vector<String> ids = codecs.SplitSkippingEmpty(
      [](const StringView& text,
         wtf_size_t at) -> std::optional<wtf_size_t> {
        if (text[at] == ',' || IsAsciiSpace(text[at])) {
          return 1;
        }
        return std::nullopt;
      });
  if (ids.empty()) {
    if (!codecs.StripWhiteSpace(IsAsciiSpace<UChar>).empty()) {
      return std::nullopt;
    }
    return g_empty_string;
  }
  StringBuilder parser_codecs;
  for (const String& id : ids) {
    if (!IsParcSafariMp2tCodec(id)) {
      return std::nullopt;
    }
    if (id.starts_with("ac-3") || id.starts_with("ec-3")) {
      continue;
    }
    String parser_codec;
    wtf_size_t pos = 5;
    if (id.starts_with("avc")) {
      parser_codec = "avc1.42E01E";
    } else if (ParcSafariCodecNumber(id, pos, 16) == 0x67) {
      parser_codec = "mp4a.67";
    } else {
      ++pos;
      const uint64_t audio_object_type = *ParcSafariCodecNumber(id, pos, 10);
      if (audio_object_type == 32 || audio_object_type == 33) {
        // MPEG-1 Layers I and II as the MPEG audio id the factory takes.
        parser_codec = "mp4a.69";
      } else {
        parser_codec = "mp4a.40." + String::Number(audio_object_type);
      }
    }
    if (!parser_codecs.empty()) {
      parser_codecs.Append(',');
    }
    parser_codecs.Append(parser_codec);
  }
  return parser_codecs.ToString();
}

// Under Safari's identity, rewrites a TS SourceBuffer's type and codecs, as
// addSourceBuffer and changeType pass them to the demuxer, into those its
// parser is created with (ParcSafariMp2tParserCodecs). Leaves others as given.
inline void ParcUseSafariMp2tParser(const String& user_agent,
                                    String& mime_type,
                                    String& codecs) {
  if (!IsParcSafariMediaSourceMp2tType(mime_type) ||
      !IsParcSafariIdentityUserAgent(user_agent)) {
    return;
  }
  if (std::optional<String> parser_codecs = ParcSafariMp2tParserCodecs(codecs)) {
    mime_type = "video/mp2t";
    codecs = *parser_codecs;
  }
}

}  // namespace blink

#endif  // THIRD_PARTY_BLINK_RENDERER_CORE_FRAME_PARC_SAFARI_IDENTITY_H_
