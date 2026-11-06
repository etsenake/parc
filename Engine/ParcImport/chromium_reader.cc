// Copyright 2026 Parc contributors.
#include <CommonCrypto/CommonCryptor.h>
#include <CommonCrypto/CommonDigest.h>
#include <array>
#include <limits>
#include <optional>
#include <set>
#include "base/files/file_util.h"
#include "base/json/json_reader.h"
#include "base/numerics/checked_math.h"
#include "base/strings/string_number_conversions.h"
#include "base/strings/utf_string_conversions.h"
#include "base/values.h"
#include "chrome/utility/importer/parc/import_reader.h"
#include "chrome/utility/importer/parc/import_snapshot.h"
#include "url/gurl.h"
namespace parc::importer {
namespace {
constexpr size_t kMaxRows = 1000000;
constexpr size_t kMaxJSON = 64 * 1024 * 1024;
bool Stopped(const Cancellation& stop) {
  return stop && stop->load();
}
std::optional<std::string> Decrypt(std::string_view encrypted,
                                   std::string_view key) {
  if (encrypted.empty())
    return std::string();
  if (!encrypted.starts_with("v10") || key.size() != kCCKeySizeAES128 ||
      encrypted.size() < 19)
    return std::nullopt;
  const std::array<uint8_t, 16> iv{' ', ' ', ' ', ' ', ' ', ' ', ' ', ' ',
                                   ' ', ' ', ' ', ' ', ' ', ' ', ' ', ' '};
  std::string plain(encrypted.size(), '\0');
  size_t written = 0;
  auto result =
      CCCrypt(kCCDecrypt, kCCAlgorithmAES, kCCOptionPKCS7Padding, key.data(),
              key.size(), iv.data(), encrypted.data() + 3, encrypted.size() - 3,
              plain.data(), plain.size(), &written);
  if (result != kCCSuccess) {
    std::fill(plain.begin(), plain.end(), '\0');
    return std::nullopt;
  }
  plain.resize(written);
  return plain;
}
std::optional<base::DictValue> ReadJSON(const base::FilePath& file) {
  std::string json;
  if (!base::ReadFileToStringWithMaxSize(file, &json, kMaxJSON))
    return std::nullopt;
  return base::JSONReader::ReadDict(json, base::JSON_PARSE_CHROMIUM_EXTENSIONS);
}
std::string Column(sqlite3* db,
                   std::string_view table,
                   std::string_view name,
                   std::string_view fallback) {
  return HasColumn(db, table, name) ? std::string(name) : std::string(fallback);
}
bool FinishQuery(Statement& query, Batch& batch, const Cancellation& stop) {
  if (Stopped(stop)) {
    batch.error = "Import was cancelled.";
    return false;
  }
  if (!query.done()) {
    batch.error = "The source database could not be read completely.";
    return false;
  }
  return true;
}
bool BookmarkNode(const base::DictValue& node,
                  const std::string& parent,
                  const std::string& position,
                  Batch& batch,
                  const Cancellation& stop,
                  int depth) {
  if (Stopped(stop) || depth > 128 || batch.bookmarks.size() >= kMaxRows)
    return false;
  const auto* type = node.FindString("type");
  const auto* name = node.FindString("name");
  if (!type || !name)
    return false;
  const bool folder = *type == "folder";
  if (!folder && *type != "url")
    return false;
  const auto* url = node.FindString("url");
  if (!folder && (!url || !GURL(*url).is_valid()))
    return false;
  Bookmark item;
  item.id = position;
  item.parent = parent;
  item.title = base::UTF8ToUTF16(*name);
  item.folder = folder;
  if (url && !folder)
    item.url = *url;
  batch.bookmarks.push_back(std::move(item));
  if (folder) {
    const auto* children = node.FindList("children");
    if (!children)
      return false;
    size_t index = 0;
    for (const auto& child : *children) {
      if (!child.is_dict() ||
          !BookmarkNode(child.GetDict(), position,
                        position + "/" + base::NumberToString(index++), batch,
                        stop, depth + 1))
        return false;
    }
  }
  return true;
}
bool ReadBookmarks(const ReadOptions& options,
                   Batch& batch,
                   const Cancellation& stop) {
  auto json = ReadJSON(options.profile_path.AppendASCII("Bookmarks"));
  const auto* roots = json ? json->FindDict("roots") : nullptr;
  if (!roots) {
    batch.error = "The source bookmarks could not be read.";
    return false;
  }
  for (const char* key : {"bookmark_bar", "other", "synced"}) {
    const auto* root = roots->FindDict(key);
    if (root && !BookmarkNode(*root, "", key, batch, stop, 0)) {
      batch.error =
          "The source bookmarks contain unsupported or incomplete data.";
      return false;
    }
  }
  return !Stopped(stop);
}
bool ReadHistory(sqlite3* db, Batch& batch, const Cancellation& stop) {
  Statement query(
      db,
      "SELECT url,title,visit_count,typed_count,last_visit_time,hidden FROM "
      "urls ORDER BY id");
  while (query.Step()) {
    if (Stopped(stop) || batch.history.size() >= kMaxRows)
      return false;
    History h;
    h.url = query.Text(0);
    h.title = query.Text16(1);
    if (query.Int(2) < 0 || query.Int(2) > std::numeric_limits<int>::max() ||
        query.Int(3) < 0 || query.Int(3) > std::numeric_limits<int>::max()) {
      batch.warnings.push_back("An invalid history count was skipped.");
      continue;
    }
    h.visits = query.Int(2);
    h.typed = query.Int(3);
    h.last_visit = query.Int(4);
    h.hidden = query.Int(5) != 0;
    if (GURL(h.url).is_valid() && h.visits >= 0 && h.typed >= 0)
      batch.history.push_back(std::move(h));
  }
  return FinishQuery(query, batch, stop);
}
bool ReadPasswords(sqlite3* db,
                   const ReadOptions& options,
                   Batch& batch,
                   const Cancellation& stop) {
  Statement query(
      db,
      "SELECT "
      "signon_realm,origin_url,action_url,username_element,username_value,"
      "password_element,password_value,scheme,blacklisted_by_user FROM logins");
  while (query.Step()) {
    if (Stopped(stop) || batch.passwords.size() >= kMaxRows)
      return false;
    Password p;
    p.realm = query.Text(0);
    p.url = query.Text(1);
    p.action = query.Text(2);
    p.username_element = query.Text16(3);
    p.username = query.Text16(4);
    p.password_element = query.Text16(5);
    p.scheme = query.Int(7);
    p.blocked = query.Int(8) != 0;
    auto value = Decrypt(query.Blob(6), options.source_key);
    if (!value && !p.blocked) {
      batch.error =
          "Some source passwords could not be decrypted. No passwords were "
          "imported.";
      return false;
    }
    if (value) {
      p.password = base::UTF8ToUTF16(*value);
      std::fill(value->begin(), value->end(), '\0');
    }
    if (p.realm.empty() || !GURL(p.url).is_valid() || p.scheme < 0 ||
        p.scheme > 2) {
      batch.warnings.push_back("An unsupported password record was skipped.");
      continue;
    }
    batch.passwords.push_back(std::move(p));
  }
  return FinishQuery(query, batch, stop);
}
bool ReadCookies(sqlite3* db,
                 const ReadOptions& options,
                 Batch& batch,
                 const Cancellation& stop) {
  int version = 0;
  Statement metadata(db, "SELECT value FROM meta WHERE key='version'");
  if (metadata.Step())
    version = metadata.Int(0);
  std::string sql =
      "SELECT "
      "host_key,name,value,path,creation_utc,expires_utc,last_access_utc,is_"
      "secure,is_httponly,encrypted_value,";
  for (const auto& field : std::vector<std::pair<const char*, const char*>>{
           {"samesite", "-1"},
           {"priority", "1"},
           {"source_scheme", "0"},
           {"source_port", "-1"},
           {"top_frame_site_key", "''"},
           {"has_cross_site_ancestor", "1"}}) {
    sql += Column(db, "cookies", field.first, field.second) + ",";
  }
  sql.pop_back();
  sql += " FROM cookies";
  Statement query(db, sql);
  while (query.Step()) {
    if (Stopped(stop) || batch.cookies.size() >= kMaxRows)
      return false;
    Cookie c;
    c.domain = query.Text(0);
    c.name = query.Text(1);
    c.value = query.Text(2);
    c.path = query.Text(3);
    c.creation = query.Int(4);
    c.expiry = query.Int(5);
    c.last_access = query.Int(6);
    c.secure = query.Int(7) != 0;
    c.http_only = query.Int(8) != 0;
    const std::string encrypted = query.Blob(9);
    if (!encrypted.empty()) {
      auto value = Decrypt(encrypted, options.source_key);
      if (!value) {
        batch.error =
            "Some source cookies could not be decrypted. No cookies were "
            "imported.";
        return false;
      }
      if (version >= 24) {
        std::array<unsigned char, CC_SHA256_DIGEST_LENGTH> digest;
        CC_SHA256(c.domain.data(), static_cast<CC_LONG>(c.domain.size()),
                  digest.data());
        if (value->size() < digest.size() ||
            std::string_view(*value).substr(0, digest.size()) !=
                std::string_view(reinterpret_cast<const char*>(digest.data()),
                                 digest.size())) {
          batch.error = "A source cookie failed its host integrity check.";
          return false;
        }
        value->erase(0, digest.size());
      }
      c.value = std::move(*value);
    }
    c.same_site = query.Int(10);
    c.priority = query.Int(11);
    c.source_scheme = query.Int(12);
    c.source_port = query.Int(13);
    c.top_frame_site = query.Text(14);
    c.ancestor_cross_site = query.Int(15) != 0;
    batch.cookies.push_back(std::move(c));
  }
  return FinishQuery(query, batch, stop);
}
bool ReadAutofill(sqlite3* db,
                  const ReadOptions& options,
                  Batch& batch,
                  const Cancellation& stop) {
  if (HasTable(db, "autofill")) {
    Statement query(
        db,
        "SELECT name,value,date_created,date_last_used,count FROM autofill");
    while (query.Step()) {
      if (Stopped(stop) || batch.autofill.size() >= kMaxRows)
        return false;
      Autofill a;
      a.fields["name"] = query.Text16(0);
      a.fields["value"] = query.Text16(1);
      if (!((base::CheckedNumeric<int64_t>(query.Int(2)) + 11644473600LL) *
            1000000)
               .AssignIfValid(&a.created) ||
          !((base::CheckedNumeric<int64_t>(query.Int(3)) + 11644473600LL) *
            1000000)
               .AssignIfValid(&a.last_used)) {
        batch.error = "An autofill timestamp is invalid.";
        return false;
      }
      a.use_count = query.Int(4);
      batch.autofill.push_back(std::move(a));
    }
    if (!FinishQuery(query, batch, stop))
      return false;
  }
  // Current and the immediately preceding Chromium local-address schemas.
  const char* table = HasTable(db, "address_type_tokens")
                          ? "address_type_tokens"
                      : HasTable(db, "local_addresses_type_tokens")
                          ? "local_addresses_type_tokens"
                          : nullptr;
  if (table) {
    Statement query(db, std::string("SELECT guid,type,value FROM ") + table +
                            " ORDER BY guid");
    std::map<std::string, Autofill> addresses;
    while (query.Step()) {
      if (Stopped(stop) || addresses.size() >= kMaxRows)
        return false;
      auto& a = addresses[query.Text(0)];
      a.kind = Autofill::Kind::kAddress;
      a.fields[base::NumberToString(query.Int(1))] = query.Text16(2);
    }
    if (!FinishQuery(query, batch, stop))
      return false;
    for (auto& [id, address] : addresses)
      batch.autofill.push_back(std::move(address));
  } else if (HasTable(db, "autofill_profiles")) {
    // Historical Chromium's migration fields map to its stable FieldType IDs.
    const std::vector<std::pair<const char*, int>> fields = {
        {"company_name", 60}, {"street_address", 77}, {"city", 33},
        {"state", 34},        {"zipcode", 35},        {"country_code", 36}};
    std::string sql = "SELECT guid";
    for (const auto& [name, type] : fields)
      sql += "," + Column(db, "autofill_profiles", name, "''");
    sql += " FROM autofill_profiles ORDER BY guid";
    Statement query(db, sql);
    std::map<std::string, Autofill> profiles;
    while (query.Step()) {
      if (Stopped(stop) || profiles.size() >= kMaxRows)
        return false;
      auto& a = profiles[query.Text(0)];
      a.kind = Autofill::Kind::kAddress;
      for (size_t i = 0; i < fields.size(); ++i)
        a.fields[base::NumberToString(fields[i].second)] = query.Text16(i + 1);
    }
    if (!FinishQuery(query, batch, stop))
      return false;
    const std::vector<std::tuple<const char*, const char*, int>> details = {
        {"autofill_profile_names", "first_name", 3},
        {"autofill_profile_names", "middle_name", 4},
        {"autofill_profile_names", "last_name", 5},
        {"autofill_profile_names", "full_name", 7},
        {"autofill_profile_emails", "email", 9},
        {"autofill_profile_phones", "number", 14}};
    for (const auto& [detail_table, column, type] : details) {
      if (!HasTable(db, detail_table) || !HasColumn(db, detail_table, column))
        continue;
      Statement q(db, "SELECT guid," + std::string(column) + " FROM " +
                          detail_table + " ORDER BY rowid");
      while (q.Step()) {
        if (Stopped(stop))
          return false;
        auto it = profiles.find(q.Text(0));
        if (it != profiles.end() &&
            !it->second.fields.contains(base::NumberToString(type)))
          it->second.fields[base::NumberToString(type)] = q.Text16(1);
      }
      if (!FinishQuery(q, batch, stop))
        return false;
    }
    for (auto& [id, address] : profiles)
      batch.autofill.push_back(std::move(address));
  }
  if (HasTable(db, "credit_cards")) {
    Statement query(
        db,
        "SELECT "
        "name_on_card,expiration_month,expiration_year,card_number_encrypted," +
            Column(db, "credit_cards", "nickname", "''") +
            " FROM credit_cards");
    while (query.Step()) {
      if (Stopped(stop) || batch.autofill.size() >= kMaxRows)
        return false;
      auto number = Decrypt(query.Blob(3), options.source_key);
      if (!number) {
        batch.error =
            "Source payment data could not be decrypted. No autofill data was "
            "imported.";
        return false;
      }
      Autofill a;
      a.kind = Autofill::Kind::kCard;
      a.fields["name"] = query.Text16(0);
      a.fields["month"] = base::NumberToString16(query.Int(1));
      a.fields["year"] = base::NumberToString16(query.Int(2));
      a.fields["number"] = base::UTF8ToUTF16(*number);
      a.fields["nickname"] = query.Text16(4);
      std::fill(number->begin(), number->end(), '\0');
      batch.autofill.push_back(std::move(a));
    }
    if (!FinishQuery(query, batch, stop))
      return false;
  }
  return true;
}
bool ReadExtensions(const ReadOptions& options,
                    Batch& batch,
                    const Cancellation& stop) {
  auto json = ReadJSON(options.profile_path.AppendASCII("Secure Preferences"));
  if (!json)
    json = ReadJSON(options.profile_path.AppendASCII("Preferences"));
  const auto* extensions =
      json ? json->FindDictByDottedPath("extensions.settings") : nullptr;
  if (!extensions) {
    batch.error = "The source extension preferences could not be read.";
    return false;
  }
  for (const auto& id : options.extension_ids) {
    if (Stopped(stop))
      return false;
    if (id.size() != 32 ||
        id.find_first_not_of("abcdefghijklmnop") != std::string::npos)
      return false;
    const auto* entry = extensions->FindDict(id);
    const auto* manifest = entry ? entry->FindDict("manifest") : nullptr;
    if (!manifest || !entry->FindBool("from_webstore").value_or(false) ||
        entry->FindBool("was_installed_by_default").value_or(false)) {
      batch.warnings.push_back(
          "A selected extension is no longer an eligible Web Store extension.");
      continue;
    }
    const auto* name = manifest->FindString("name");
    batch.extensions.push_back({id, base::UTF8ToUTF16(name ? *name : id)});
  }
  return true;
}
}  // namespace
Batch ReadChromiumCategory(const ReadOptions& options,
                           uint32_t category,
                           const Cancellation& stop) {
  Batch batch;
  batch.category = category;
  if (options.family != Family::kChromium ||
      !options.profile_path.IsAbsolute()) {
    batch.error = "The source profile is invalid.";
    return batch;
  }
  if (Stopped(stop)) {
    batch.error = "Import was cancelled.";
    return batch;
  }
  if (category == kBookmarks)
    batch.success = ReadBookmarks(options, batch, stop);
  else if (category == kExtensions)
    batch.success = ReadExtensions(options, batch, stop);
  else {
    const char* file = category == kHistory     ? "History"
                       : category == kPasswords ? "Login Data"
                       : category == kAutofill  ? "Web Data"
                                                : nullptr;
    base::FilePath path;
    if (category == kCookies) {
      path = options.profile_path.AppendASCII("Network/Cookies");
      if (!base::PathExists(path))
        path = options.profile_path.AppendASCII("Cookies");
    } else if (file)
      path = options.profile_path.AppendASCII(file);
    else {
      batch.error = "This import category is unsupported.";
      return batch;
    }
    SnapshotDatabase db;
    if (!db.Open(path)) {
      batch.error = db.error();
      return batch;
    }
    switch (category) {
      case kHistory:
        batch.success = ReadHistory(db.get(), batch, stop);
        break;
      case kPasswords:
        batch.success = ReadPasswords(db.get(), options, batch, stop);
        break;
      case kCookies:
        batch.success = ReadCookies(db.get(), options, batch, stop);
        break;
      case kAutofill:
        batch.success = ReadAutofill(db.get(), options, batch, stop);
        break;
    }
  }
  if (!batch.success && batch.error.empty())
    batch.error =
        Stopped(stop)
            ? "Import was cancelled."
            : "The source data exceeded supported limits or could not be read.";
  if (!batch.success) {
    batch.history.clear();
    batch.bookmarks.clear();
    batch.cookies.clear();
    batch.passwords.clear();
    batch.autofill.clear();
    batch.extensions.clear();
  }
  return batch;
}
}  // namespace parc::importer
