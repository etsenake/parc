// Byte-level helpers for building FairPlay sample buffers. Pure C++, no
// platform types, so they can be unit-tested in isolation.
#pragma once

#include <cstddef>
#include <cstdint>
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

// Wraps |payload| in an ISO box header.
std::vector<uint8_t> MakeBox(uint32_t type, const std::vector<uint8_t>& payload);

}  // namespace parc::fairplay
