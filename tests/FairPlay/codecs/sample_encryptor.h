// Common Encryption (ISO/IEC 23001-7) of single samples in memory, for the
// FairPlay codec proof: the AES-128 'cenc' and 'cbcs' ciphers, and the
// subsample layouts a CMAF packager gives H.264 and HEVC (Dolby Vision)
// samples.
#pragma once

#include <cstddef>
#include <cstdint>
#include <map>
#include <string>
#include <vector>

#include "fairplay_types.h"

namespace parc::fairplay::test {

// Encrypts (or decrypts) |data| in place with a 16-byte |key|.
// 'cenc': AES-CTR over the protected ranges as one keystream; the counter
//   block starts as |iv| (an 8-byte IV is zero-extended to 16) and is
//   incremented as a 128-bit big-endian number per block.
// 'cbcs': AES-CBC over each protected range with |pattern| (crypt blocks
//   encrypted, then skip blocks left clear, repeating; {0, 0} encrypts every
//   block). Every range starts again from the 16-byte |iv| and a trailing
//   partial block stays clear (as media/cdm/cbcs_decryptor.cc reads it).
// Empty |subsamples| means the whole sample is one protected range.
bool CencCrypt(bool encrypt, EncryptionScheme scheme, const std::vector<uint8_t>& key, const std::vector<uint8_t>& iv,
               EncryptionPattern pattern, const std::vector<SubsampleEntry>& subsamples, std::vector<uint8_t>* data,
               std::string* error);

enum class NalCodec { kH264, kHevc };

// Subsample layouts for length-prefixed H.264 or HEVC samples (Dolby Vision
// profiles 5 and 8 are HEVC streams), as CENC 3rd edition section 10 and the
// CMAF packagers do it: each VCL NAL unit keeps its length field, NAL unit
// header and slice header clear and protects the rest; NAL units without
// slice data (parameter sets, SEI, AUD, Dolby Vision RPU) stay clear and are
// folded into the next subsample's clear bytes. 'cenc' rounds each protected
// range down to whole 16-byte blocks, moving the remainder into the clear
// bytes; 'cbcs' protects everything after the slice header.
//
// Slice headers are parsed with the active parameter sets, from the decoder
// record and from parameter sets found in the samples.
class NalLayout {
 public:
  // |record| is the 'avcC' or 'hvcC' payload.
  NalLayout(NalCodec codec, const std::vector<uint8_t>& record);

  bool ok() const { return error_.empty(); }
  const std::string& error() const { return error_; }
  size_t length_size() const { return length_size_; }

  bool Subsamples(const std::vector<uint8_t>& sample, EncryptionScheme scheme, std::vector<SubsampleEntry>* subsamples,
                  std::string* error);

  // Bytes of a VCL NAL unit (from its NAL unit header, length field
  // excluded) up to the end of its slice header, or 0 for a NAL unit without
  // slice data. Parameter sets passed here are stored.
  bool HeaderSize(const uint8_t* nal, size_t size, size_t* header, std::string* error);

  struct H264Sps {
    uint32_t chroma_format_idc = 1;
    bool separate_colour_plane = false;
    uint32_t log2_max_frame_num = 0;
    uint32_t pic_order_cnt_type = 0;
    uint32_t log2_max_poc_lsb = 0;
    bool delta_pic_order_always_zero = false;
    bool frame_mbs_only = true;
  };
  struct H264Pps {
    uint32_t sps_id = 0;
    bool entropy_coding_mode = false;
    bool bottom_field_pic_order_in_frame_present = false;
    uint32_t num_slice_groups_minus1 = 0;
    uint32_t num_ref_idx_l0_default_minus1 = 0;
    uint32_t num_ref_idx_l1_default_minus1 = 0;
    bool weighted_pred = false;
    uint32_t weighted_bipred_idc = 0;
    bool deblocking_filter_control_present = false;
    bool redundant_pic_cnt_present = false;
  };
  struct HevcRps {
    uint32_t num_delta_pocs = 0;
    uint32_t num_used = 0;  // used_by_curr_pic entries.
  };
  struct HevcSps {
    uint32_t chroma_format_idc = 1;
    bool separate_colour_plane = false;
    uint32_t log2_max_poc_lsb = 0;
    uint32_t pic_size_in_ctbs = 0;
    bool sample_adaptive_offset = false;
    std::vector<HevcRps> rps;
    bool long_term_ref_pics_present = false;
    std::vector<bool> lt_used_by_curr_pic;  // Per SPS long-term picture.
    bool temporal_mvp = false;
  };
  struct HevcPps {
    uint32_t sps_id = 0;
    bool dependent_slice_segments_enabled = false;
    bool output_flag_present = false;
    uint32_t num_extra_slice_header_bits = 0;
    bool cabac_init_present = false;
    uint32_t num_ref_idx_l0_default_minus1 = 0;
    uint32_t num_ref_idx_l1_default_minus1 = 0;
    bool slice_chroma_qp_offsets_present = false;
    bool weighted_pred = false;
    bool weighted_bipred = false;
    bool tiles_enabled = false;
    bool entropy_coding_sync_enabled = false;
    bool loop_filter_across_slices_enabled = false;
    bool deblocking_filter_override_enabled = false;
    bool deblocking_filter_disabled = false;
    bool lists_modification_present = false;
    bool slice_segment_header_extension_present = false;
    bool chroma_qp_offset_list_enabled = false;
  };

 private:
  bool AddParameterSet(const uint8_t* nal, size_t size, std::string* error);

  NalCodec codec_;
  size_t length_size_ = 4;
  std::string error_;
  std::map<uint32_t, H264Sps> h264_sps_;
  std::map<uint32_t, H264Pps> h264_pps_;
  std::map<uint32_t, HevcSps> hevc_sps_;
  std::map<uint32_t, HevcPps> hevc_pps_;
};

}  // namespace parc::fairplay::test
