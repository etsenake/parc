// Copyright 2026 Parc contributors.
#pragma once
#include <atomic>
#include <cstdint>
#include <map>
#include <memory>
#include <string>
#include <vector>
#include "base/files/file_path.h"

namespace parc::importer {
enum class Family { kChromium, kSafari, kFirefox };
enum Category : uint32_t {
  kHistory = 1, kBookmarks = 2, kCookies = 4, kPasswords = 8,
  kAutofill = 16, kExtensions = 32,
};
// Plain data stays in the native utility/browser boundary. Never exposed in the
// public ObjC DTOs. All timestamps are microseconds since 1601-01-01 UTC.
struct History { std::string url; std::u16string title; int visits = 0;
  int typed = 0; int64_t last_visit = 0; bool hidden = false; };
struct Bookmark { std::string id, parent; std::u16string title;
  std::string url; bool folder = false; };
struct Cookie { std::string domain, name, value, path;
  int64_t creation = 0, expiry = 0, last_access = 0;
  bool secure = false, http_only = false; int same_site = -1, priority = 1;
  int source_scheme = 0, source_port = -1;
  std::string top_frame_site; bool ancestor_cross_site = true; };
struct Password { std::string realm, url, action;
  std::u16string username_element, username, password_element, password;
  int scheme = 0; bool blocked = false; };
struct Autofill { enum class Kind { kForm, kAddress, kCard };
  Kind kind = Kind::kForm;
  // Form: name/value. Address: numeric ServerFieldType strings. Card:
  // name/number/month/year/nickname. Actual writers validate every field.
  std::map<std::string, std::u16string> fields;
  int64_t created = 0, last_used = 0; int use_count = 0; };
struct Extension { std::string id; std::u16string name; };
struct ReadOptions {
  Family family = Family::kChromium;
  base::FilePath profile_path, app_path;
  // Original user-authorized source key only. Never target Parc's encryption key.
  std::string source_key;
  std::vector<std::string> extension_ids;
};
struct Batch {
  uint32_t category = 0;
  bool success = false;
  std::string error;
  std::vector<std::string> warnings;
  std::vector<History> history;
  std::vector<Bookmark> bookmarks;
  std::vector<Cookie> cookies;
  std::vector<Password> passwords;
  std::vector<Autofill> autofill;
  std::vector<Extension> extensions;
};
using Cancellation = std::shared_ptr<std::atomic_bool>;
// Blocking worker entry points. Only immutable selected-source paths, no
// discovery, target profile, network, Keychain or user-interface work here.
Batch ReadChromiumCategory(const ReadOptions&, uint32_t, const Cancellation&);
Batch ReadSafariCategory(const ReadOptions&, uint32_t, const Cancellation&);
Batch ReadFirefoxCategory(const ReadOptions&, uint32_t, const Cancellation&);
}  // namespace parc::importer
