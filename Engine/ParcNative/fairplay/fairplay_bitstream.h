// Byte-level helpers for building FairPlay sample buffers. Pure C++, no
// platform types, so they can be unit-tested in isolation.
#pragma once

#include <cstddef>
#include <cstdint>
#include <optional>
#include <vector>

#include "fairplay_types.h"

namespace parc::fairplay {

constexpr uint32_t FourCC(char a, char b, char c, char d) {
  return (static_cast<uint32_t>(static_cast<uint8_t>(a)) << 24) |
         (static_cast<uint32_t>(static_cast<uint8_t>(b)) << 16) |
         (static_cast<uint32_t>(static_cast<uint8_t>(c)) << 8) |
         static_cast<uint32_t>(static_cast<uint8_t>(d));
}

// Rewrites an Annex B access unit (3- or 4-byte start codes) as 4-byte
// big-endian length-prefixed NAL units, the framing AVSampleBufferDisplayLayer
// requires with an avcC/hvcC format description. In-band parameter sets are
// kept. Start codes are searched only inside clear ranges, as Chromium's
// H264Parser::SetEncryptedStream does, and each subsample's clear_bytes grows
// by the bytes its start codes gained. Returns false if the data has no start
// code, a start code isn't in clear data, or the subsamples don't cover the
// sample exactly.
bool ConvertAnnexBToLengthPrefixed(const uint8_t* data,
                                   size_t size,
                                   std::vector<SubsampleEntry>* subsamples,
                                   std::vector<uint8_t>* output);

// Returns the size of the ADTS header at |data| (7, or 9 with CRC), or 0 if
// |data| doesn't start with a valid ADTS header.
size_t AdtsHeaderSize(const uint8_t* data, size_t size);

// Removes |header_size| leading clear bytes from |subsamples|. A single
// remaining {0, payload} entry is dropped, since an empty list means "whole
// sample protected", which is what AVStreamDataParser emits for CMAF audio.
// Returns false if the header isn't covered by clear bytes.
bool RemoveLeadingClearBytes(size_t header_size,
                             size_t payload_size,
                             std::vector<SubsampleEntry>* subsamples);

// The native-endian uint32 BytesOfClearData/BytesOfProtectedData pairs that
// kCMSampleAttachmentKey_CryptorSubsampleAuxiliaryData carries.
std::vector<uint8_t> SubsampleAuxiliaryData(
    const std::vector<SubsampleEntry>& subsamples);

// 'tenc' FullBox payload (version/flags included, box header excluded): what
// AVStreamDataParser puts in the CommonEncryptionTrackEncryptionBox format
// description extension. Version 1 carries the cbcs pattern.
std::vector<uint8_t> TrackEncryptionBoxPayload(const TrackEncryption& tenc);

// 'sinf' payload (frma + schm + schi/tenc, box header excluded), the 'sinf'
// entry of kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms.
std::vector<uint8_t> ProtectionSchemeInfoPayload(uint32_t original_format,
                                                 const TrackEncryption& tenc);

// 'esds' FullBox payload (version/flags + ES_Descriptor) for an AAC
// AudioSpecificConfig of any object type (LC, HE-AAC, HE-AACv2, xHE-AAC).
std::vector<uint8_t> AacEsdsPayload(const std::vector<uint8_t>& audio_specific_config);

// ISO/IEC 14496-12 VisualSampleEntry (box header included) of |type| with
// |children| (decoder configuration and other boxes) appended.
std::vector<uint8_t> VisualSampleEntry(uint32_t type,
                                       uint16_t width,
                                       uint16_t height,
                                       const std::vector<std::vector<uint8_t>>& children);

// AudioSampleEntry (version 0, box header included) with |children|.
std::vector<uint8_t> AudioSampleEntry(uint32_t type,
                                      uint16_t channels,
                                      uint32_t sample_rate,
                                      const std::vector<std::vector<uint8_t>>& children);

// The protected form of a clear sample entry (ISO/IEC 23001-7): renamed to
// 'encv'/'enca' with a 'sinf' (frma = original type, schm, schi/tenc) appended.
std::vector<uint8_t> ProtectSampleEntry(const std::vector<uint8_t>& entry,
                                        bool video,
                                        const TrackEncryption& tenc);

// Chromium hands a renderer empty decoder records (MP4StreamParser builds every
// video VideoDecoderConfig with EmptyExtraData() and gives AC-3/E-AC-3 no
// dac3/dec3), so these rebuild them from the bitstream.

// The sequence header OBU of a low-overhead-format AV1 temporal unit, with its
// size field (as av1C configOBUs carry it). nullopt if there is none.
std::optional<std::vector<uint8_t>> Av1SequenceHeaderObu(const uint8_t* data, size_t size);

// AV1CodecConfigurationRecord ('av1C' payload) for a sequence header OBU from
// Av1SequenceHeaderObu: seq_profile, level, tier, bit depth, monochrome and
// chroma fields parsed from it, then the OBU as configOBUs.
std::optional<std::vector<uint8_t>> Av1CodecConfigurationRecord(const std::vector<uint8_t>& sequence_header_obu);

// DOVIDecoderConfigurationRecord ('dvcC'/'dvvC' payload, 24 bytes) for a
// single-layer stream: RPU and base layer present, no enhancement layer.
// Profile 5 has compatibility ID 0.
std::vector<uint8_t> DolbyVisionConfigurationRecord(int profile, int level, int compatibility_id);

// 'dac3' payload from the AC-3 syncframe at the start of |data|.
// |subsamples| is null for a clear sample; for an encrypted one it is the
// sample's layout (empty: all protected), and only a syncframe header lying in
// clear bytes is read, since a syncword found in ciphertext would be noise.
std::optional<std::vector<uint8_t>> Ac3SpecificBoxPayload(const uint8_t* data, size_t size,
                                                          const std::vector<SubsampleEntry>* subsamples = nullptr);

// 'dec3' payload from the E-AC-3 syncframes of one access unit, reading only
// headers in clear bytes as above. Syncframes are grouped by stream type and
// substream ID: one entry per independent substream with its dependent
// substreams' count and chan_loc (chanmap locations 5-12 and 14, LSB first,
// as Dolby's muxer writes them); data_rate sums each substream's rate. bsmod and asvc are written
// as 0, and no Atmos extension is written.
std::optional<std::vector<uint8_t>> Eac3SpecificBoxPayload(const uint8_t* data, size_t size,
                                                           const std::vector<SubsampleEntry>* subsamples = nullptr);

// The same boxes from the decoder config alone, for streams whose syncframes
// are encrypted (whole-sample cbcs/cenc audio): sample rate gives fscod,
// channel count gives acmod and lfeon (6, 7 and 8 = 3/2 + LFE, the 5.1 core
// of 6.1/7.1). The bit rate is unknown and written as 0. nullopt for an
// unsupported rate or layout.
std::optional<std::vector<uint8_t>> Ac3SpecificBoxFromConfig(int sample_rate, int channels);
std::optional<std::vector<uint8_t>> Eac3SpecificBoxFromConfig(int sample_rate, int channels);

// The Dolby Vision base-layer compatibility ID for a profile when the stream
// doesn't say (Chromium carries only profile and level): 0 for profiles 4, 5
// and 7 (no compatible base layer), 2 (SDR) for 9, the only one it allows;
// for 8 the ID can't be known from the profile, and 1 (HDR10) is assumed.
int DefaultDolbyVisionCompatibilityId(int profile);

// The ID a parameter set NAL unit declares: H.264 SPS/PPS (types 7/8) or HEVC
// VPS/SPS/PPS (32/33/34), read after removing emulation-prevention bytes.
// nullopt for other NAL types or a truncated unit.
std::optional<uint32_t> ParameterSetId(bool hevc, const uint8_t* nal, size_t size);

// Wraps |payload| in an ISO box header.
std::vector<uint8_t> MakeBox(uint32_t type, const std::vector<uint8_t>& payload);

}  // namespace parc::fairplay
