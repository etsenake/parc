#include "sample_encryptor.h"

#include <CommonCrypto/CommonCryptor.h>

#include <algorithm>
#include <cstring>

namespace parc::fairplay::test {

namespace {

class Aes {
 public:
  Aes(bool encrypt, const std::vector<uint8_t>& key) {
    if (key.size() != 16 || CCCryptorCreate(encrypt ? kCCEncrypt : kCCDecrypt, kCCAlgorithmAES, kCCOptionECBMode,
                                            key.data(), key.size(), nullptr, &cryptor_) != kCCSuccess) {
      cryptor_ = nullptr;
    }
  }
  ~Aes() {
    if (cryptor_) CCCryptorRelease(cryptor_);
  }
  Aes(const Aes&) = delete;
  Aes& operator=(const Aes&) = delete;

  bool ok() const { return cryptor_ != nullptr; }
  bool Block(const uint8_t in[16], uint8_t out[16]) {
    size_t moved = 0;
    return CCCryptorUpdate(cryptor_, in, 16, out, 16, &moved) == kCCSuccess && moved == 16;
  }

 private:
  CCCryptorRef cryptor_ = nullptr;
};

void Increment(uint8_t counter[16]) {
  for (int i = 15; i >= 0 && ++counter[i] == 0; --i) {
  }
}

}

bool CencCrypt(bool encrypt, EncryptionScheme scheme, const std::vector<uint8_t>& key, const std::vector<uint8_t>& iv,
               EncryptionPattern pattern, const std::vector<SubsampleEntry>& subsamples, std::vector<uint8_t>* data,
               std::string* error) {
  std::vector<std::pair<size_t, size_t>> ranges;
  if (subsamples.empty()) {
    ranges.push_back({0, data->size()});
  } else {
    size_t offset = 0;
    for (const SubsampleEntry& e : subsamples) {
      offset += e.clear_bytes;
      if (offset + e.cypher_bytes > data->size()) {
        *error = "subsamples exceed the sample";
        return false;
      }
      ranges.push_back({offset, e.cypher_bytes});
      offset += e.cypher_bytes;
    }
    if (offset != data->size()) {
      *error = "subsamples don't cover the sample";
      return false;
    }
  }
  if (scheme == EncryptionScheme::kCenc) {
    if (iv.size() != 8 && iv.size() != 16) {
      *error = "cenc needs an 8- or 16-byte IV";
      return false;
    }
    Aes aes(true, key);
    if (!aes.ok()) {
      *error = "bad key";
      return false;
    }
    uint8_t counter[16] = {};
    std::memcpy(counter, iv.data(), iv.size());
    uint8_t stream[16];
    size_t used = 16;
    for (auto [offset, size] : ranges) {
      for (size_t i = 0; i < size; ++i) {
        if (used == 16) {
          if (!aes.Block(counter, stream)) return false;
          Increment(counter);
          used = 0;
        }
        (*data)[offset + i] ^= stream[used++];
      }
    }
    return true;
  }
  if (scheme != EncryptionScheme::kCbcs || iv.size() != 16) {
    *error = "cbcs needs a 16-byte IV";
    return false;
  }
  Aes aes(encrypt, key);
  if (!aes.ok()) {
    *error = "bad key";
    return false;
  }
  const size_t crypt = pattern.crypt_byte_block ? pattern.crypt_byte_block : 1;
  const size_t skip = pattern.crypt_byte_block ? pattern.skip_byte_block : 0;
  for (auto [offset, size] : ranges) {
    uint8_t chain[16];
    std::memcpy(chain, iv.data(), 16);
    const size_t blocks = size / 16;
    for (size_t b = 0; b < blocks; ++b) {
      if (b % (crypt + skip) >= crypt) continue;
      uint8_t* block = data->data() + offset + b * 16;
      uint8_t out[16];
      if (encrypt) {
        for (int k = 0; k < 16; ++k) block[k] ^= chain[k];
        if (!aes.Block(block, out)) return false;
        std::memcpy(block, out, 16);
        std::memcpy(chain, out, 16);
      } else {
        uint8_t cipher[16];
        std::memcpy(cipher, block, 16);
        if (!aes.Block(block, out)) return false;
        for (int k = 0; k < 16; ++k) block[k] = out[k] ^ chain[k];
        std::memcpy(chain, cipher, 16);
      }
    }
  }
  return true;
}

namespace {

class RbspReader {
 public:
  RbspReader(const uint8_t* nal, size_t size) {
    int zeros = 0;
    for (size_t i = 0; i < size; ++i) {
      if (zeros >= 2 && nal[i] == 3) {
        zeros = 0;
        continue;
      }
      zeros = nal[i] == 0 ? zeros + 1 : 0;
      rbsp_.push_back(nal[i]);
      raw_.push_back(i);
    }
  }

  bool Bits(int n, uint32_t* out) {
    uint32_t v = 0;
    for (int i = 0; i < n; ++i) {
      if (pos_ >= rbsp_.size() * 8) return false;
      v = (v << 1) | ((rbsp_[pos_ / 8] >> (7 - pos_ % 8)) & 1);
      ++pos_;
    }
    *out = v;
    return true;
  }
  bool Flag(bool* out) {
    uint32_t v = 0;
    if (!Bits(1, &v)) return false;
    *out = v != 0;
    return true;
  }
  bool Skip(size_t n) {
    if (pos_ + n > rbsp_.size() * 8) return false;
    pos_ += n;
    return true;
  }
  bool Ue(uint32_t* out) {
    int zeros = 0;
    uint32_t bit = 0;
    while (true) {
      if (!Bits(1, &bit)) return false;
      if (bit) break;
      if (++zeros > 31) return false;
    }
    uint32_t rest = 0;
    if (!Bits(zeros, &rest)) return false;
    *out = uint32_t((uint64_t(1) << zeros) - 1 + rest);
    return true;
  }
  bool Se(int32_t* out) {
    uint32_t v = 0;
    if (!Ue(&v)) return false;
    *out = (v & 1) ? int32_t((v + 1) / 2) : -int32_t(v / 2);
    return true;
  }
  bool Aligned() const { return pos_ % 8 == 0; }
  size_t RawBytesConsumed() const {
    if (pos_ == 0) return 0;
    return raw_[(pos_ - 1) / 8] + 1;
  }

 private:
  std::vector<uint8_t> rbsp_;
  std::vector<size_t> raw_;
  size_t pos_ = 0;
};

#define READ(expr)              \
  do {                          \
    if (!(expr)) return false;  \
  } while (0)

uint32_t CeilLog2(uint32_t x) {
  uint32_t n = 0;
  while ((uint64_t(1) << n) < x) ++n;
  return n;
}

bool H264ScalingList(RbspReader& r, int size) {
  int last = 8, next = 8;
  for (int j = 0; j < size; ++j) {
    if (next != 0) {
      int32_t delta = 0;
      READ(r.Se(&delta));
      next = (last + delta + 256) % 256;
    }
    last = next == 0 ? last : next;
  }
  return true;
}

bool HevcScalingListData(RbspReader& r) {
  for (int size_id = 0; size_id < 4; ++size_id) {
    for (int matrix_id = 0; matrix_id < 6; matrix_id += size_id == 3 ? 3 : 1) {
      bool pred_mode = false;
      READ(r.Flag(&pred_mode));
      uint32_t u = 0;
      int32_t s = 0;
      if (!pred_mode) {
        READ(r.Ue(&u));
      } else {
        int coef_num = std::min(64, 1 << (4 + (size_id << 1)));
        if (size_id > 1) READ(r.Se(&s));
        for (int i = 0; i < coef_num; ++i) READ(r.Se(&s));
      }
    }
  }
  return true;
}

bool HevcProfileTierLevel(RbspReader& r, uint32_t max_sub_layers_minus1) {
  READ(r.Skip(96));
  std::vector<bool> profile_present(max_sub_layers_minus1), level_present(max_sub_layers_minus1);
  for (uint32_t i = 0; i < max_sub_layers_minus1; ++i) {
    bool p = false, l = false;
    READ(r.Flag(&p));
    READ(r.Flag(&l));
    profile_present[i] = p;
    level_present[i] = l;
  }
  if (max_sub_layers_minus1 > 0) READ(r.Skip(2 * (8 - max_sub_layers_minus1)));
  for (uint32_t i = 0; i < max_sub_layers_minus1; ++i) {
    if (profile_present[i]) READ(r.Skip(88));
    if (level_present[i]) READ(r.Skip(8));
  }
  return true;
}

bool HevcStRefPicSet(RbspReader& r, uint32_t idx, const std::vector<NalLayout::HevcRps>& sets, uint32_t num_sets,
                     NalLayout::HevcRps* out) {
  bool inter = false;
  if (idx != 0) READ(r.Flag(&inter));
  *out = {};
  uint32_t u = 0;
  if (inter) {
    uint32_t delta_idx_minus1 = 0;
    if (idx == num_sets) READ(r.Ue(&delta_idx_minus1));
    if (delta_idx_minus1 + 1 > idx) return false;
    READ(r.Skip(1));
    READ(r.Ue(&u));
    const NalLayout::HevcRps& ref = sets[idx - (delta_idx_minus1 + 1)];
    for (uint32_t j = 0; j <= ref.num_delta_pocs; ++j) {
      bool used = false, use_delta = true;
      READ(r.Flag(&used));
      if (!used) READ(r.Flag(&use_delta));
      if (used || use_delta) ++out->num_delta_pocs;
      if (used) ++out->num_used;
    }
    return true;
  }
  uint32_t negative = 0, positive = 0;
  READ(r.Ue(&negative));
  READ(r.Ue(&positive));
  if (negative > 16 || positive > 16) return false;
  for (uint32_t i = 0; i < negative + positive; ++i) {
    bool used = false;
    READ(r.Ue(&u));
    READ(r.Flag(&used));
    if (used) ++out->num_used;
  }
  out->num_delta_pocs = negative + positive;
  return true;
}

bool ParseH264Sps(RbspReader& r, uint32_t* id, NalLayout::H264Sps* sps) {
  uint32_t profile_idc = 0, u = 0;
  int32_t s = 0;
  READ(r.Bits(8, &profile_idc));
  READ(r.Skip(16));
  READ(r.Ue(id));
  static const uint32_t kHigh[] = {100, 110, 122, 244, 44, 83, 86, 118, 128, 138, 139, 134, 135};
  if (std::find(std::begin(kHigh), std::end(kHigh), profile_idc) != std::end(kHigh)) {
    READ(r.Ue(&sps->chroma_format_idc));
    if (sps->chroma_format_idc == 3) READ(r.Flag(&sps->separate_colour_plane));
    READ(r.Ue(&u));
    READ(r.Ue(&u));
    READ(r.Skip(1));
    bool matrix = false;
    READ(r.Flag(&matrix));
    if (matrix) {
      for (int i = 0; i < (sps->chroma_format_idc != 3 ? 8 : 12); ++i) {
        bool present = false;
        READ(r.Flag(&present));
        if (present) READ(H264ScalingList(r, i < 6 ? 16 : 64));
      }
    }
  }
  READ(r.Ue(&u));
  sps->log2_max_frame_num = u + 4;
  READ(r.Ue(&sps->pic_order_cnt_type));
  if (sps->pic_order_cnt_type == 0) {
    READ(r.Ue(&u));
    sps->log2_max_poc_lsb = u + 4;
  } else if (sps->pic_order_cnt_type == 1) {
    READ(r.Flag(&sps->delta_pic_order_always_zero));
    READ(r.Se(&s));
    READ(r.Se(&s));
    uint32_t cycle = 0;
    READ(r.Ue(&cycle));
    for (uint32_t i = 0; i < cycle; ++i) READ(r.Se(&s));
  }
  READ(r.Ue(&u));
  READ(r.Skip(1));
  READ(r.Ue(&u));
  READ(r.Ue(&u));
  READ(r.Flag(&sps->frame_mbs_only));
  return true;
}

bool ParseH264Pps(RbspReader& r, uint32_t* id, NalLayout::H264Pps* pps) {
  int32_t s = 0;
  READ(r.Ue(id));
  READ(r.Ue(&pps->sps_id));
  READ(r.Flag(&pps->entropy_coding_mode));
  READ(r.Flag(&pps->bottom_field_pic_order_in_frame_present));
  READ(r.Ue(&pps->num_slice_groups_minus1));
  if (pps->num_slice_groups_minus1 > 0) return false;
  READ(r.Ue(&pps->num_ref_idx_l0_default_minus1));
  READ(r.Ue(&pps->num_ref_idx_l1_default_minus1));
  READ(r.Flag(&pps->weighted_pred));
  READ(r.Bits(2, &pps->weighted_bipred_idc));
  READ(r.Se(&s));
  READ(r.Se(&s));
  READ(r.Se(&s));
  READ(r.Flag(&pps->deblocking_filter_control_present));
  READ(r.Skip(1));
  READ(r.Flag(&pps->redundant_pic_cnt_present));
  return true;
}

bool ParseHevcSps(RbspReader& r, uint32_t* id, NalLayout::HevcSps* sps) {
  uint32_t u = 0, max_sub_layers_minus1 = 0;
  READ(r.Skip(4));
  READ(r.Bits(3, &max_sub_layers_minus1));
  READ(r.Skip(1));
  READ(HevcProfileTierLevel(r, max_sub_layers_minus1));
  READ(r.Ue(id));
  READ(r.Ue(&sps->chroma_format_idc));
  if (sps->chroma_format_idc == 3) READ(r.Flag(&sps->separate_colour_plane));
  uint32_t width = 0, height = 0;
  READ(r.Ue(&width));
  READ(r.Ue(&height));
  bool conformance = false;
  READ(r.Flag(&conformance));
  if (conformance) {
    for (int i = 0; i < 4; ++i) READ(r.Ue(&u));
  }
  READ(r.Ue(&u));
  READ(r.Ue(&u));
  READ(r.Ue(&u));
  sps->log2_max_poc_lsb = u + 4;
  bool ordering = false;
  READ(r.Flag(&ordering));
  for (uint32_t i = ordering ? 0 : max_sub_layers_minus1; i <= max_sub_layers_minus1; ++i) {
    READ(r.Ue(&u));
    READ(r.Ue(&u));
    READ(r.Ue(&u));
  }
  uint32_t log2_min_cb_minus3 = 0, log2_diff_cb = 0;
  READ(r.Ue(&log2_min_cb_minus3));
  READ(r.Ue(&log2_diff_cb));
  READ(r.Ue(&u));
  READ(r.Ue(&u));
  READ(r.Ue(&u));
  READ(r.Ue(&u));
  const uint32_t ctb_log2 = log2_min_cb_minus3 + 3 + log2_diff_cb;
  if (ctb_log2 > 7) return false;
  const uint32_t ctb = 1u << ctb_log2;
  sps->pic_size_in_ctbs = ((width + ctb - 1) / ctb) * ((height + ctb - 1) / ctb);
  bool flag = false;
  READ(r.Flag(&flag));
  if (flag) {
    READ(r.Flag(&flag));
    if (flag) READ(HevcScalingListData(r));
  }
  READ(r.Skip(1));
  READ(r.Flag(&sps->sample_adaptive_offset));
  READ(r.Flag(&flag));
  if (flag) {
    READ(r.Skip(8));
    READ(r.Ue(&u));
    READ(r.Ue(&u));
    READ(r.Skip(1));
  }
  uint32_t num_sets = 0;
  READ(r.Ue(&num_sets));
  if (num_sets > 64) return false;
  sps->rps.resize(num_sets);
  for (uint32_t i = 0; i < num_sets; ++i) READ(HevcStRefPicSet(r, i, sps->rps, num_sets, &sps->rps[i]));
  READ(r.Flag(&sps->long_term_ref_pics_present));
  if (sps->long_term_ref_pics_present) {
    uint32_t count = 0;
    READ(r.Ue(&count));
    if (count > 32) return false;
    for (uint32_t i = 0; i < count; ++i) {
      bool used = false;
      READ(r.Skip(sps->log2_max_poc_lsb));
      READ(r.Flag(&used));
      sps->lt_used_by_curr_pic.push_back(used);
    }
  }
  READ(r.Flag(&sps->temporal_mvp));
  return true;
}

bool ParseHevcPps(RbspReader& r, uint32_t* id, NalLayout::HevcPps* pps) {
  uint32_t u = 0;
  int32_t s = 0;
  bool flag = false, transform_skip = false;
  READ(r.Ue(id));
  READ(r.Ue(&pps->sps_id));
  READ(r.Flag(&pps->dependent_slice_segments_enabled));
  READ(r.Flag(&pps->output_flag_present));
  READ(r.Bits(3, &pps->num_extra_slice_header_bits));
  READ(r.Skip(1));
  READ(r.Flag(&pps->cabac_init_present));
  READ(r.Ue(&pps->num_ref_idx_l0_default_minus1));
  READ(r.Ue(&pps->num_ref_idx_l1_default_minus1));
  READ(r.Se(&s));
  READ(r.Skip(1));
  READ(r.Flag(&transform_skip));
  READ(r.Flag(&flag));
  if (flag) READ(r.Ue(&u));
  READ(r.Se(&s));
  READ(r.Se(&s));
  READ(r.Flag(&pps->slice_chroma_qp_offsets_present));
  READ(r.Flag(&pps->weighted_pred));
  READ(r.Flag(&pps->weighted_bipred));
  READ(r.Skip(1));
  READ(r.Flag(&pps->tiles_enabled));
  READ(r.Flag(&pps->entropy_coding_sync_enabled));
  if (pps->tiles_enabled) {
    uint32_t columns = 0, rows = 0;
    READ(r.Ue(&columns));
    READ(r.Ue(&rows));
    READ(r.Flag(&flag));
    if (!flag) {
      for (uint32_t i = 0; i < columns + rows; ++i) READ(r.Ue(&u));
    }
    READ(r.Skip(1));
  }
  READ(r.Flag(&pps->loop_filter_across_slices_enabled));
  READ(r.Flag(&flag));
  if (flag) {
    READ(r.Flag(&pps->deblocking_filter_override_enabled));
    READ(r.Flag(&pps->deblocking_filter_disabled));
    if (!pps->deblocking_filter_disabled) {
      READ(r.Se(&s));
      READ(r.Se(&s));
    }
  }
  READ(r.Flag(&flag));
  if (flag) READ(HevcScalingListData(r));
  READ(r.Flag(&pps->lists_modification_present));
  READ(r.Ue(&u));
  READ(r.Flag(&pps->slice_segment_header_extension_present));
  READ(r.Flag(&flag));
  if (flag) {
    bool range = false;
    uint32_t others = 0;
    READ(r.Flag(&range));
    READ(r.Bits(7, &others));
    if (others) return false;
    if (range) {
      if (transform_skip) READ(r.Ue(&u));
      READ(r.Skip(1));
      READ(r.Flag(&pps->chroma_qp_offset_list_enabled));
    }
  }
  return true;
}

bool H264SliceHeader(RbspReader& r, uint8_t nal_ref_idc, uint8_t nal_type,
                     const std::map<uint32_t, NalLayout::H264Sps>& all_sps,
                     const std::map<uint32_t, NalLayout::H264Pps>& all_pps, std::string* error) {
  uint32_t u = 0, slice_type = 0, pps_id = 0;
  int32_t s = 0;
  READ(r.Ue(&u));
  READ(r.Ue(&slice_type));
  READ(r.Ue(&pps_id));
  auto pps_it = all_pps.find(pps_id);
  auto sps_it = pps_it == all_pps.end() ? all_sps.end() : all_sps.find(pps_it->second.sps_id);
  if (sps_it == all_sps.end()) {
    *error = "slice refers to an unknown parameter set";
    return false;
  }
  const NalLayout::H264Pps& pps = pps_it->second;
  const NalLayout::H264Sps& sps = sps_it->second;
  const uint32_t type = slice_type % 5;
  if (sps.separate_colour_plane) READ(r.Skip(2));
  READ(r.Skip(sps.log2_max_frame_num));
  bool field_pic = false;
  if (!sps.frame_mbs_only) {
    READ(r.Flag(&field_pic));
    if (field_pic) READ(r.Skip(1));
  }
  if (nal_type == 5) READ(r.Ue(&u));
  if (sps.pic_order_cnt_type == 0) {
    READ(r.Skip(sps.log2_max_poc_lsb));
    if (pps.bottom_field_pic_order_in_frame_present && !field_pic) READ(r.Se(&s));
  }
  if (sps.pic_order_cnt_type == 1 && !sps.delta_pic_order_always_zero) {
    READ(r.Se(&s));
    if (pps.bottom_field_pic_order_in_frame_present && !field_pic) READ(r.Se(&s));
  }
  if (pps.redundant_pic_cnt_present) READ(r.Ue(&u));
  if (type == 1) READ(r.Skip(1));
  uint32_t l0 = pps.num_ref_idx_l0_default_minus1, l1 = pps.num_ref_idx_l1_default_minus1;
  if (type == 0 || type == 3 || type == 1) {
    bool override_flag = false;
    READ(r.Flag(&override_flag));
    if (override_flag) {
      READ(r.Ue(&l0));
      if (type == 1) READ(r.Ue(&l1));
    }
  }
  for (int list = 0; list < (type == 1 ? 2 : (type == 2 || type == 4) ? 0 : 1); ++list) {
    bool modification = false;
    READ(r.Flag(&modification));
    if (!modification) continue;
    uint32_t idc = 0;
    do {
      READ(r.Ue(&idc));
      if (idc <= 2) READ(r.Ue(&u));
      else if (idc != 3) return false;
    } while (idc != 3);
  }
  const uint32_t chroma_array_type = sps.separate_colour_plane ? 0 : sps.chroma_format_idc;
  if ((pps.weighted_pred && (type == 0 || type == 3)) || (pps.weighted_bipred_idc == 1 && type == 1)) {
    READ(r.Ue(&u));
    if (chroma_array_type != 0) READ(r.Ue(&u));
    for (int list = 0; list < (type == 1 ? 2 : 1); ++list) {
      for (uint32_t i = 0; i <= (list ? l1 : l0); ++i) {
        bool flag = false;
        READ(r.Flag(&flag));
        if (flag) {
          READ(r.Se(&s));
          READ(r.Se(&s));
        }
        if (chroma_array_type != 0) {
          READ(r.Flag(&flag));
          if (flag) {
            for (int j = 0; j < 4; ++j) READ(r.Se(&s));
          }
        }
      }
    }
  }
  if (nal_ref_idc != 0) {
    if (nal_type == 5) {
      READ(r.Skip(2));
    } else {
      bool adaptive = false;
      READ(r.Flag(&adaptive));
      if (adaptive) {
        uint32_t op = 0;
        do {
          READ(r.Ue(&op));
          if (op == 1 || op == 3) READ(r.Ue(&u));
          if (op == 2) READ(r.Ue(&u));
          if (op == 3 || op == 6) READ(r.Ue(&u));
          if (op == 4) READ(r.Ue(&u));
          if (op > 6) return false;
        } while (op != 0);
      }
    }
  }
  if (pps.entropy_coding_mode && type != 2 && type != 4) READ(r.Ue(&u));
  READ(r.Se(&s));
  if (type == 3 || type == 4) {
    if (type == 3) READ(r.Skip(1));
    READ(r.Se(&s));
  }
  if (pps.deblocking_filter_control_present) {
    READ(r.Ue(&u));
    if (u != 1) {
      READ(r.Se(&s));
      READ(r.Se(&s));
    }
  }
  if (pps.entropy_coding_mode) {
    while (!r.Aligned()) READ(r.Skip(1));
  }
  return true;
}

bool HevcSliceHeader(RbspReader& r, uint8_t nal_type, const std::map<uint32_t, NalLayout::HevcSps>& all_sps,
                     const std::map<uint32_t, NalLayout::HevcPps>& all_pps, std::string* error) {
  uint32_t u = 0, pps_id = 0;
  int32_t s = 0;
  bool first = false, dependent = false;
  READ(r.Flag(&first));
  if (nal_type >= 16 && nal_type <= 23) READ(r.Skip(1));
  READ(r.Ue(&pps_id));
  auto pps_it = all_pps.find(pps_id);
  auto sps_it = pps_it == all_pps.end() ? all_sps.end() : all_sps.find(pps_it->second.sps_id);
  if (sps_it == all_sps.end()) {
    *error = "slice refers to an unknown parameter set";
    return false;
  }
  const NalLayout::HevcPps& pps = pps_it->second;
  const NalLayout::HevcSps& sps = sps_it->second;
  if (!first) {
    if (pps.dependent_slice_segments_enabled) READ(r.Flag(&dependent));
    READ(r.Skip(CeilLog2(sps.pic_size_in_ctbs)));
  }
  if (!dependent) {
    READ(r.Skip(pps.num_extra_slice_header_bits));
    uint32_t slice_type = 0;
    READ(r.Ue(&slice_type));
    if (pps.output_flag_present) READ(r.Skip(1));
    if (sps.separate_colour_plane) READ(r.Skip(2));
    bool temporal_mvp = false;
    uint32_t total_curr = 0;
    if (nal_type != 19 && nal_type != 20) {
      READ(r.Skip(sps.log2_max_poc_lsb));
      bool sps_set = false;
      READ(r.Flag(&sps_set));
      const uint32_t num_sets = uint32_t(sps.rps.size());
      if (!sps_set) {
        NalLayout::HevcRps rps;
        READ(HevcStRefPicSet(r, num_sets, sps.rps, num_sets, &rps));
        total_curr += rps.num_used;
      } else {
        uint32_t idx = 0;
        if (num_sets > 1) READ(r.Bits(int(CeilLog2(num_sets)), &idx));
        if (idx >= num_sets) return false;
        total_curr += sps.rps[idx].num_used;
      }
      if (sps.long_term_ref_pics_present) {
        uint32_t lt_sps = 0, lt_pics = 0;
        const uint32_t sps_count = uint32_t(sps.lt_used_by_curr_pic.size());
        if (sps_count > 0) READ(r.Ue(&lt_sps));
        READ(r.Ue(&lt_pics));
        for (uint32_t i = 0; i < lt_sps + lt_pics; ++i) {
          if (i < lt_sps) {
            uint32_t idx = 0;
            if (sps_count > 1) READ(r.Bits(int(CeilLog2(sps_count)), &idx));
            if (idx >= sps_count) return false;
            total_curr += sps.lt_used_by_curr_pic[idx];
          } else {
            bool used = false;
            READ(r.Skip(sps.log2_max_poc_lsb));
            READ(r.Flag(&used));
            total_curr += used;
          }
          bool msb = false;
          READ(r.Flag(&msb));
          if (msb) READ(r.Ue(&u));
        }
      }
      if (sps.temporal_mvp) READ(r.Flag(&temporal_mvp));
    }
    bool sao_luma = false, sao_chroma = false;
    const uint32_t chroma_array_type = sps.separate_colour_plane ? 0 : sps.chroma_format_idc;
    if (sps.sample_adaptive_offset) {
      READ(r.Flag(&sao_luma));
      if (chroma_array_type != 0) READ(r.Flag(&sao_chroma));
    }
    if (slice_type == 0 || slice_type == 1) {
      uint32_t l0 = pps.num_ref_idx_l0_default_minus1, l1 = pps.num_ref_idx_l1_default_minus1;
      bool override_flag = false;
      READ(r.Flag(&override_flag));
      if (override_flag) {
        READ(r.Ue(&l0));
        if (slice_type == 0) READ(r.Ue(&l1));
      }
      if (pps.lists_modification_present && total_curr > 1) {
        for (int list = 0; list < (slice_type == 0 ? 2 : 1); ++list) {
          bool modification = false;
          READ(r.Flag(&modification));
          if (modification) READ(r.Skip(size_t((list ? l1 : l0) + 1) * CeilLog2(total_curr)));
        }
      }
      if (slice_type == 0) READ(r.Skip(1));
      if (pps.cabac_init_present) READ(r.Skip(1));
      if (temporal_mvp) {
        bool from_l0 = true;
        if (slice_type == 0) READ(r.Flag(&from_l0));
        if ((from_l0 && l0 > 0) || (!from_l0 && l1 > 0)) READ(r.Ue(&u));
      }
      if ((pps.weighted_pred && slice_type == 1) || (pps.weighted_bipred && slice_type == 0)) {
        READ(r.Ue(&u));
        if (chroma_array_type != 0) READ(r.Se(&s));
        for (int list = 0; list < (slice_type == 0 ? 2 : 1); ++list) {
          const uint32_t count = (list ? l1 : l0) + 1;
          std::vector<bool> luma(count), chroma(count);
          for (uint32_t i = 0; i < count; ++i) {
            bool f = false;
            READ(r.Flag(&f));
            luma[i] = f;
          }
          if (chroma_array_type != 0) {
            for (uint32_t i = 0; i < count; ++i) {
              bool f = false;
              READ(r.Flag(&f));
              chroma[i] = f;
            }
          }
          for (uint32_t i = 0; i < count; ++i) {
            if (luma[i]) {
              READ(r.Se(&s));
              READ(r.Se(&s));
            }
            if (chroma[i]) {
              for (int j = 0; j < 4; ++j) READ(r.Se(&s));
            }
          }
        }
      }
      READ(r.Ue(&u));
    }
    READ(r.Se(&s));
    if (pps.slice_chroma_qp_offsets_present) {
      READ(r.Se(&s));
      READ(r.Se(&s));
    }
    if (pps.chroma_qp_offset_list_enabled) READ(r.Skip(1));
    bool deblocking_override = false;
    if (pps.deblocking_filter_override_enabled) READ(r.Flag(&deblocking_override));
    bool deblocking_disabled = pps.deblocking_filter_disabled;
    if (deblocking_override) {
      READ(r.Flag(&deblocking_disabled));
      if (!deblocking_disabled) {
        READ(r.Se(&s));
        READ(r.Se(&s));
      }
    }
    if (pps.loop_filter_across_slices_enabled && (sao_luma || sao_chroma || !deblocking_disabled)) READ(r.Skip(1));
  }
  if (pps.tiles_enabled || pps.entropy_coding_sync_enabled) {
    uint32_t entries = 0;
    READ(r.Ue(&entries));
    if (entries > 0) {
      uint32_t len_minus1 = 0;
      READ(r.Ue(&len_minus1));
      if (len_minus1 > 31) return false;
      READ(r.Skip(size_t(entries) * (len_minus1 + 1)));
    }
  }
  if (pps.slice_segment_header_extension_present) {
    READ(r.Ue(&u));
    READ(r.Skip(size_t(u) * 8));
  }
  READ(r.Skip(1));
  while (!r.Aligned()) READ(r.Skip(1));
  return true;
}

#undef READ

}

NalLayout::NalLayout(NalCodec codec, const std::vector<uint8_t>& record) : codec_(codec) {
  auto add_list = [&](size_t* pos, uint32_t count) {
    for (uint32_t k = 0; k < count && error_.empty(); ++k) {
      if (*pos + 2 > record.size()) {
        error_ = "truncated decoder record";
        return;
      }
      size_t len = (record[*pos] << 8) | record[*pos + 1];
      *pos += 2;
      if (*pos + len > record.size()) {
        error_ = "truncated decoder record";
        return;
      }
      AddParameterSet(record.data() + *pos, len, &error_);
      *pos += len;
    }
  };
  if (codec == NalCodec::kH264) {
    if (record.size() < 7) {
      error_ = "short avcC";
      return;
    }
    length_size_ = (record[4] & 3) + 1;
    size_t pos = 6;
    add_list(&pos, record[5] & 0x1f);
    if (pos < record.size()) {
      uint32_t count = record[pos++];
      add_list(&pos, count);
    }
  } else {
    if (record.size() < 23) {
      error_ = "short hvcC";
      return;
    }
    length_size_ = (record[21] & 3) + 1;
    size_t pos = 23;
    for (uint8_t a = 0; a < record[22] && error_.empty(); ++a) {
      if (pos + 3 > record.size()) {
        error_ = "truncated hvcC";
        return;
      }
      uint32_t count = (record[pos + 1] << 8) | record[pos + 2];
      pos += 3;
      add_list(&pos, count);
    }
  }
}

bool NalLayout::AddParameterSet(const uint8_t* nal, size_t size, std::string* error) {
  if (size < 2) return true;
  if (codec_ == NalCodec::kH264) {
    const uint8_t type = nal[0] & 0x1f;
    if (type != 7 && type != 8) return true;
    RbspReader r(nal + 1, size - 1);
    uint32_t id = 0;
    bool ok = false;
    if (type == 7) {
      H264Sps sps;
      ok = ParseH264Sps(r, &id, &sps);
      if (ok) h264_sps_[id] = sps;
    } else {
      H264Pps pps;
      ok = ParseH264Pps(r, &id, &pps);
      if (ok) h264_pps_[id] = pps;
    }
    if (!ok) *error = type == 7 ? "unparsable H.264 SPS" : "unparsable H.264 PPS";
    return ok;
  }
  const uint8_t type = (nal[0] >> 1) & 0x3f;
  if (type != 33 && type != 34) return true;
  RbspReader r(nal + 2, size - 2);
  uint32_t id = 0;
  bool ok = false;
  if (type == 33) {
    HevcSps sps;
    ok = ParseHevcSps(r, &id, &sps);
    if (ok) hevc_sps_[id] = sps;
  } else {
    HevcPps pps;
    ok = ParseHevcPps(r, &id, &pps);
    if (ok) hevc_pps_[id] = pps;
  }
  if (!ok) *error = type == 33 ? "unparsable HEVC SPS" : "unparsable HEVC PPS";
  return ok;
}

bool NalLayout::HeaderSize(const uint8_t* nal, size_t size, size_t* header, std::string* error) {
  *header = 0;
  if (size < 2) return true;
  if (codec_ == NalCodec::kH264) {
    const uint8_t type = nal[0] & 0x1f;
    if (type < 1 || type > 5) return AddParameterSet(nal, size, error);
    RbspReader r(nal, size);
    r.Skip(8);
    if (!H264SliceHeader(r, uint8_t(nal[0] >> 5), type, h264_sps_, h264_pps_, error)) {
      if (error->empty()) *error = "unparsable H.264 slice header";
      return false;
    }
    *header = r.RawBytesConsumed();
    return true;
  }
  const uint8_t type = (nal[0] >> 1) & 0x3f;
  if (type > 31) return AddParameterSet(nal, size, error);
  if (type > 21) {
    *error = "reserved HEVC VCL NAL unit type";
    return false;
  }
  RbspReader r(nal, size);
  r.Skip(16);
  if (!HevcSliceHeader(r, type, hevc_sps_, hevc_pps_, error)) {
    if (error->empty()) *error = "unparsable HEVC slice header";
    return false;
  }
  *header = r.RawBytesConsumed();
  return true;
}

bool NalLayout::Subsamples(const std::vector<uint8_t>& sample, EncryptionScheme scheme,
                           std::vector<SubsampleEntry>* subsamples, std::string* error) {
  subsamples->clear();
  uint32_t pending_clear = 0;
  for (size_t pos = 0; pos < sample.size();) {
    if (pos + length_size_ > sample.size()) {
      *error = "truncated NAL length";
      return false;
    }
    size_t length = 0;
    for (size_t k = 0; k < length_size_; ++k) length = (length << 8) | sample[pos + k];
    if (pos + length_size_ + length > sample.size()) {
      *error = "NAL unit past the sample's end";
      return false;
    }
    size_t header = 0;
    if (!HeaderSize(sample.data() + pos + length_size_, length, &header, error)) return false;
    const uint32_t total = uint32_t(length_size_ + length);
    if (header == 0 || header >= length) {
      pending_clear += total;
    } else {
      uint32_t clear = uint32_t(length_size_ + header);
      uint32_t cypher = total - clear;
      if (scheme == EncryptionScheme::kCenc) {
        clear += cypher % 16;
        cypher -= cypher % 16;
      }
      if (cypher == 0) {
        pending_clear += total;
      } else {
        subsamples->push_back({pending_clear + clear, cypher});
        pending_clear = 0;
      }
    }
    pos += length_size_ + length;
  }
  if (pending_clear) subsamples->push_back({pending_clear, 0});
  return true;
}

}
