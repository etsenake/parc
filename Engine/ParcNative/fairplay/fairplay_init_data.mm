#include "fairplay_init_data.h"

#import <Foundation/Foundation.h>

#include <algorithm>

#if !__has_feature(objc_arc)
#error "This file requires ARC."
#endif

namespace parc::fairplay {

const uint8_t kFairPlaySystemId[16] = {0x94, 0xce, 0x86, 0xfb, 0x07, 0xff, 0x4f, 0x43,
                                       0xad, 0xb8, 0x93, 0xd2, 0xfa, 0x96, 0x8c, 0xa2};
const uint8_t kWidevineSystemId[16] = {0xed, 0xef, 0x8b, 0xa9, 0x79, 0xd6, 0x4a, 0xce,
                                       0xa3, 0xc8, 0x27, 0xdc, 0xd5, 0x1d, 0x21, 0xed};

namespace {

uint32_t ReadBE32(const uint8_t* p) {
  return (static_cast<uint32_t>(p[0]) << 24) | (static_cast<uint32_t>(p[1]) << 16) |
         (static_cast<uint32_t>(p[2]) << 8) | static_cast<uint32_t>(p[3]);
}

constexpr uint32_t Type(const char (&name)[5]) {
  return (static_cast<uint32_t>(static_cast<uint8_t>(name[0])) << 24) |
         (static_cast<uint32_t>(static_cast<uint8_t>(name[1])) << 16) |
         (static_cast<uint32_t>(static_cast<uint8_t>(name[2])) << 8) |
         static_cast<uint32_t>(static_cast<uint8_t>(name[3]));
}

struct Box {
  uint32_t type;
  const uint8_t* payload;
  size_t payload_size;
};

// Iterates the boxes in [data, data + size). Returns false on a malformed box.
template <typename Visitor>
bool ForEachBox(const uint8_t* data, size_t size, Visitor visit) {
  size_t offset = 0;
  while (offset < size) {
    if (size - offset < 8) {
      return false;
    }
    uint64_t box_size = ReadBE32(data + offset);
    size_t header = 8;
    if (box_size == 1) {
      if (size - offset < 16) {
        return false;
      }
      box_size = (static_cast<uint64_t>(ReadBE32(data + offset + 8)) << 32) |
                 ReadBE32(data + offset + 12);
      header = 16;
    } else if (box_size == 0) {
      box_size = size - offset;
    }
    if (box_size < header || box_size > size - offset) {
      return false;
    }
    visit(Box{ReadBE32(data + offset + 4), data + offset + header,
              static_cast<size_t>(box_size) - header},
          data + offset, static_cast<size_t>(box_size));
    offset += static_cast<size_t>(box_size);
  }
  return true;
}

NSData* ToNSData(const std::vector<uint8_t>& bytes) {
  return [NSData dataWithBytes:bytes.data() length:bytes.size()];
}

std::vector<uint8_t> ToVector(NSData* data) {
  const uint8_t* bytes = static_cast<const uint8_t*>(data.bytes);
  return std::vector<uint8_t>(bytes, bytes + data.length);
}

id ParseJSON(const std::vector<uint8_t>& init_data) {
  if (init_data.empty()) {
    return nil;
  }
  return [NSJSONSerialization JSONObjectWithData:ToNSData(init_data) options:0 error:nil];
}

NSData* DecodeBase64(NSString* string, bool url_safe) {
  if (![string isKindOfClass:[NSString class]]) {
    return nil;
  }
  NSMutableString* normalized = [string mutableCopy];
  if (url_safe) {
    [normalized replaceOccurrencesOfString:@"-" withString:@"+" options:0
                                     range:NSMakeRange(0, normalized.length)];
    [normalized replaceOccurrencesOfString:@"_" withString:@"/" options:0
                                     range:NSMakeRange(0, normalized.length)];
    while (normalized.length % 4) {
      [normalized appendString:@"="];
    }
  }
  return [[NSData alloc] initWithBase64EncodedString:normalized
                                             options:NSDataBase64DecodingIgnoreUnknownCharacters];
}

void AddUnique(std::vector<std::vector<uint8_t>>* list, const std::vector<uint8_t>& key_id) {
  if (std::find(list->begin(), list->end(), key_id) == list->end()) {
    list->push_back(key_id);
  }
}

InitDataPlan Fail(std::string message) {
  InitDataPlan plan;
  plan.error = std::move(message);
  return plan;
}

std::vector<uint8_t> PsshJson(const std::vector<uint8_t>& pssh) {
  NSString* base64 = [ToNSData(pssh) base64EncodedStringWithOptions:0];
  return ToVector([NSJSONSerialization dataWithJSONObject:@{@"pssh" : base64} options:0 error:nil]);
}

void AppendBE32(std::vector<uint8_t>* out, uint32_t value) {
  for (int shift = 24; shift >= 0; shift -= 8) {
    out->push_back(static_cast<uint8_t>(value >> shift));
  }
}

std::vector<uint8_t> MakeBox(uint32_t type, const std::vector<uint8_t>& payload, bool full) {
  std::vector<uint8_t> out;
  AppendBE32(&out, static_cast<uint32_t>(8 + (full ? 4 : 0) + payload.size()));
  AppendBE32(&out, type);
  if (full) {
    AppendBE32(&out, 0);
  }
  out.insert(out.end(), payload.begin(), payload.end());
  return out;
}

InitDataPlan PlanForKeyIds(const std::vector<std::vector<uint8_t>>& key_ids) {
  InitDataPlan plan;
  plan.json_messages = true;
  for (const std::vector<uint8_t>& key_id : key_ids) {
    ContentKeyRequestPlan call;
    call.initialization_data = PsshJson(FairPlayPsshForKeyId(key_id));
    call.content_identifier = key_id;
    call.key_ids.push_back(key_id);
    plan.calls.push_back(std::move(call));
  }
  return plan;
}

bool IsValidScheme(uint32_t scheme) {
  return scheme == Type("cbcs") || scheme == Type("cbc2") || scheme == Type("cbc1") ||
         scheme == Type("cenc");
}

}  // namespace

std::optional<InitDataType> InitDataTypeFromName(const std::string& name) {
  if (name == "skd") return InitDataType::kSkd;
  if (name == "sinf") return InitDataType::kSinf;
  if (name == "cenc") return InitDataType::kCenc;
  if (name == "keyids") return InitDataType::kKeyIds;
  return std::nullopt;
}

const char* InitDataTypeName(InitDataType type) {
  switch (type) {
    case InitDataType::kSkd:
      return "skd";
    case InitDataType::kSinf:
      return "sinf";
    case InitDataType::kCenc:
      return "cenc";
    case InitDataType::kKeyIds:
      return "keyids";
  }
  return "";
}

std::optional<std::vector<uint8_t>> KeyIdFromSkdUri(const std::string& uri) {
  static constexpr char kScheme[] = "skd://";
  constexpr size_t kSchemeSize = sizeof(kScheme) - 1;
  if (uri.compare(0, kSchemeSize, kScheme) != 0) {
    return std::nullopt;
  }
  std::string host = uri.substr(kSchemeSize);
  host = host.substr(0, host.find_first_of(":/?#"));
  host.erase(std::remove(host.begin(), host.end(), '-'), host.end());
  if (host.size() != 32) {
    return std::nullopt;
  }
  std::vector<uint8_t> key_id;
  for (size_t i = 0; i < 32; i += 2) {
    auto nibble = [](char c) -> int {
      if (c >= '0' && c <= '9') return c - '0';
      if (c >= 'a' && c <= 'f') return c - 'a' + 10;
      if (c >= 'A' && c <= 'F') return c - 'A' + 10;
      return -1;
    };
    int high = nibble(host[i]);
    int low = nibble(host[i + 1]);
    if (high < 0 || low < 0) {
      return std::nullopt;
    }
    key_id.push_back(static_cast<uint8_t>(high << 4 | low));
  }
  return key_id;
}

std::vector<std::vector<uint8_t>> KeyIdsFromSinfPayload(const std::vector<uint8_t>& sinf) {
  std::optional<uint32_t> scheme;
  std::optional<std::vector<uint8_t>> key_id;
  ForEachBox(sinf.data(), sinf.size(), [&](const Box& box, const uint8_t*, size_t) {
    if (box.type == Type("schm") && box.payload_size >= 8) {
      scheme = ReadBE32(box.payload + 4);
    } else if (box.type == Type("schi")) {
      ForEachBox(box.payload, box.payload_size, [&](const Box& inner, const uint8_t*, size_t) {
        if (inner.type == Type("tenc") && inner.payload_size >= 24) {
          key_id = std::vector<uint8_t>(inner.payload + 8, inner.payload + 24);
        }
      });
    }
  });
  if (!scheme || !key_id || !IsValidScheme(*scheme)) {
    return {};
  }
  return {*key_id};
}

std::optional<std::vector<PsshBox>> ParsePsshBoxes(const std::vector<uint8_t>& data) {
  std::vector<PsshBox> boxes;
  bool valid = true;
  bool parsed = ForEachBox(data.data(), data.size(), [&](const Box& box, const uint8_t* start,
                                                         size_t size) {
    if (box.type != Type("pssh")) {
      return;
    }
    const uint8_t* p = box.payload;
    size_t remaining = box.payload_size;
    if (remaining < 4 + 16 + 4) {
      valid = false;
      return;
    }
    PsshBox pssh;
    pssh.version = p[0];
    pssh.system_id.assign(p + 4, p + 20);
    p += 20;
    remaining -= 20;
    if (pssh.version >= 1) {
      uint32_t count = ReadBE32(p);
      p += 4;
      remaining -= 4;
      if (count > remaining / 16) {
        valid = false;
        return;
      }
      for (uint32_t i = 0; i < count; ++i) {
        pssh.key_ids.emplace_back(p, p + 16);
        p += 16;
        remaining -= 16;
      }
    }
    if (remaining < 4) {
      valid = false;
      return;
    }
    uint32_t data_size = ReadBE32(p);
    p += 4;
    remaining -= 4;
    if (data_size > remaining) {
      valid = false;
      return;
    }
    pssh.data.assign(p, p + data_size);
    pssh.box.assign(start, start + size);
    boxes.push_back(std::move(pssh));
  });
  if (!parsed || !valid) {
    return std::nullopt;
  }
  return boxes;
}

std::vector<uint8_t> FairPlayPsshForKeyId(const std::vector<uint8_t>& key_id) {
  std::vector<uint8_t> scheme;
  AppendBE32(&scheme, Type("cbcs"));
  std::vector<uint8_t> fpsd_payload = MakeBox(Type("fpsi"), scheme, true);
  std::vector<uint8_t> fpsk = MakeBox(Type("fpsk"), MakeBox(Type("fkri"), key_id, true), false);
  fpsd_payload.insert(fpsd_payload.end(), fpsk.begin(), fpsk.end());
  std::vector<uint8_t> fpsd = MakeBox(Type("fpsd"), fpsd_payload, false);
  std::vector<uint8_t> pssh(kFairPlaySystemId, kFairPlaySystemId + 16);
  AppendBE32(&pssh, static_cast<uint32_t>(fpsd.size()));
  pssh.insert(pssh.end(), fpsd.begin(), fpsd.end());
  return MakeBox(Type("pssh"), pssh, true);
}

std::vector<std::vector<uint8_t>> KeyIdsFromPssh(const PsshBox& box) {
  std::vector<std::vector<uint8_t>> key_ids;
  for (const auto& key_id : box.key_ids) {
    AddUnique(&key_ids, key_id);
  }
  if (box.version != 0 ||
      !std::equal(box.system_id.begin(), box.system_id.end(), kWidevineSystemId)) {
    return key_ids;
  }
  // WidevinePsshData: repeated bytes key_id = 2.
  const std::vector<uint8_t>& d = box.data;
  size_t i = 0;
  auto varint = [&](uint64_t* value) {
    *value = 0;
    for (int shift = 0; shift < 64 && i < d.size(); shift += 7) {
      uint8_t byte = d[i++];
      *value |= static_cast<uint64_t>(byte & 0x7f) << shift;
      if (!(byte & 0x80)) {
        return true;
      }
    }
    return false;
  };
  while (i < d.size()) {
    uint64_t key = 0;
    if (!varint(&key)) {
      break;
    }
    uint64_t field = key >> 3;
    uint64_t wire = key & 7;
    uint64_t value = 0;
    if (wire == 0) {
      if (!varint(&value)) break;
    } else if (wire == 1) {
      i += 8;
    } else if (wire == 5) {
      i += 4;
    } else if (wire == 2) {
      if (!varint(&value) || value > d.size() - i) break;
      if (field == 2 && value == 16) {
        AddUnique(&key_ids, std::vector<uint8_t>(d.begin() + i, d.begin() + i + 16));
      }
      i += value;
    } else {
      break;
    }
  }
  return key_ids;
}

namespace {

// Parc extension for WebKit's legacy com.apple.fps.2_N sessions
// (Engine/ParcRenderer/parc_webkit_media_keys.h), whose SPC content
// identifier is the page's bytes while the request comes from the media's own
// init data (CDMSessionAVContentKeySession: processContentKeyRequestWithIdentifier
// with the source buffer's init data, then contentIdentifier = the identifier):
//   {"initDataType": "cenc" | "sinf", "initData": "<base64>",
//    "contentId": "<base64>"}
// plans the inner init data as that type and names every request's SPC by
// contentId. Sessions exchange messages in the inner type's format. Key IDs
// take {"kids": [...], "contentId": "<base64>"} instead (below).
InitDataPlan PlanWithContentIdentifier(NSDictionary* root) {
  NSData* content_id = DecodeBase64(root[@"contentId"], false);
  if (!content_id.length) {
    return Fail("keyids contentId is not non-empty base64");
  }
  NSString* inner_name = root[@"initDataType"];
  std::optional<InitDataType> inner;
  if ([inner_name isKindOfClass:[NSString class]]) {
    inner = InitDataTypeFromName(inner_name.UTF8String);
  }
  if (inner != InitDataType::kCenc && inner != InitDataType::kSinf) {
    return Fail("keyids with a contentId names no cenc or sinf init data");
  }
  NSData* inner_data = DecodeBase64(root[@"initData"], false);
  if (!inner_data.length) {
    return Fail("keyids initData is not non-empty base64");
  }
  InitDataPlan plan = PlanContentKeyRequests(*inner, ToVector(inner_data));
  if (plan.error.empty()) {
    for (ContentKeyRequestPlan& call : plan.calls) {
      call.content_identifier = ToVector(content_id);
    }
  }
  return plan;
}

}  // namespace

InitDataPlan PlanContentKeyRequests(InitDataType type, const std::vector<uint8_t>& init_data) {
  switch (type) {
    case InitDataType::kSkd: {
      NSString* identifier = [[NSString alloc] initWithData:ToNSData(init_data)
                                                   encoding:NSUTF8StringEncoding];
      if (!identifier.length) {
        return Fail("skd init data is not a UTF-8 string");
      }
      InitDataPlan plan;
      ContentKeyRequestPlan call;
      call.content_identifier = init_data;
      if (auto key_id = KeyIdFromSkdUri(identifier.UTF8String)) {
        call.initialization_data = PsshJson(FairPlayPsshForKeyId(*key_id));
        call.key_ids.push_back(*key_id);
      } else {
        call.identifier = identifier.UTF8String;
      }
      plan.calls.push_back(std::move(call));
      return plan;
    }
    case InitDataType::kSinf: {
      NSDictionary* root = ParseJSON(init_data);
      NSArray* sinfs = [root isKindOfClass:[NSDictionary class]] ? root[@"sinf"] : nil;
      if (![sinfs isKindOfClass:[NSArray class]] || !sinfs.count) {
        return Fail("sinf init data is not {\"sinf\": [base64]}");
      }
      ContentKeyRequestPlan call;
      for (NSString* entry in sinfs) {
        NSData* sinf = DecodeBase64(entry, false);
        if (!sinf) {
          return Fail("sinf init data has an invalid base64 entry");
        }
        for (const auto& key_id : KeyIdsFromSinfPayload(ToVector(sinf))) {
          AddUnique(&call.key_ids, key_id);
        }
      }
      if (call.key_ids.empty()) {
        return Fail("sinf init data names no FairPlay-compatible scheme and key ID");
      }
      call.initialization_data = init_data;
      InitDataPlan plan;
      plan.calls.push_back(std::move(call));
      return plan;
    }
    case InitDataType::kCenc: {
      std::optional<std::vector<PsshBox>> boxes = ParsePsshBoxes(init_data);
      if (!boxes || boxes->empty()) {
        return Fail("cenc init data is not a list of pssh boxes");
      }
      std::vector<std::vector<uint8_t>> key_ids;
      for (const PsshBox& box : *boxes) {
        if (std::equal(box.system_id.begin(), box.system_id.end(), kFairPlaySystemId)) {
          // AVFoundation reads only the first PSSH atom and rejects the blob if
          // it isn't FairPlay's, so forward that box alone (WebKit, rdar://179255226).
          InitDataPlan plan;
          plan.json_messages = true;
          ContentKeyRequestPlan call;
          call.initialization_data = PsshJson(box.box);
          call.key_ids = box.key_ids;
          plan.calls.push_back(std::move(call));
          return plan;
        }
        for (const auto& key_id : KeyIdsFromPssh(box)) {
          AddUnique(&key_ids, key_id);
        }
      }
      if (key_ids.empty()) {
        return Fail("cenc init data has no FairPlay pssh and names no key ID");
      }
      return PlanForKeyIds(key_ids);
    }
    case InitDataType::kKeyIds: {
      NSDictionary* root = ParseJSON(init_data);
      if ([root isKindOfClass:[NSDictionary class]] && root[@"initDataType"]) {
        return PlanWithContentIdentifier(root);
      }
      NSArray* kids = [root isKindOfClass:[NSDictionary class]] ? root[@"kids"] : nil;
      if (![kids isKindOfClass:[NSArray class]] || !kids.count) {
        return Fail("keyids init data is not {\"kids\": [base64url]}");
      }
      std::vector<std::vector<uint8_t>> key_ids;
      for (NSString* entry in kids) {
        NSData* key_id = DecodeBase64(entry, true);
        if (key_id.length != 16) {
          return Fail("keyids init data has a key ID that isn't 16 bytes");
        }
        AddUnique(&key_ids, ToVector(key_id));
      }
      InitDataPlan plan = PlanForKeyIds(key_ids);
      // The same extension for legacy key IDs: a non-empty base64 contentId
      // names every SPC (anything else there is ignored, as before).
      NSData* content_id = DecodeBase64(root[@"contentId"], false);
      if (content_id.length) {
        for (ContentKeyRequestPlan& call : plan.calls) {
          call.content_identifier = ToVector(content_id);
        }
      }
      return plan;
    }
  }
  return Fail("unknown init data type");
}

}  // namespace parc::fairplay
