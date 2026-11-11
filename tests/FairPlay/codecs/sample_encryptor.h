#pragma once

#include <cstddef>
#include <cstdint>
#include <map>
#include <string>
#include <vector>

#include "fairplay_types.h"

namespace parc::fairplay::test {

bool CencCrypt(bool encrypt, EncryptionScheme scheme, const std::vector<uint8_t>& key, const std::vector<uint8_t>& iv,
               EncryptionPattern pattern, const std::vector<SubsampleEntry>& subsamples, std::vector<uint8_t>* data,
               std::string* error);

enum class NalCodec { kH264, kHevc };

class NalLayout {
 public:
  NalLayout(NalCodec codec, const std::vector<uint8_t>& record);

  bool ok() const { return error_.empty(); }
  const std::string& error() const { return error_; }
  size_t length_size() const { return length_size_; }

  bool Subsamples(const std::vector<uint8_t>& sample, EncryptionScheme scheme, std::vector<SubsampleEntry>* subsamples,
                  std::string* error);

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
    uint32_t num_used = 0;
  };
  struct HevcSps {
    uint32_t chroma_format_idc = 1;
    bool separate_colour_plane = false;
    uint32_t log2_max_poc_lsb = 0;
    uint32_t pic_size_in_ctbs = 0;
    bool sample_adaptive_offset = false;
    std::vector<HevcRps> rps;
    bool long_term_ref_pics_present = false;
    std::vector<bool> lt_used_by_curr_pic;
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

}
