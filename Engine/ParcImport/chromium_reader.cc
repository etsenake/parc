// Copyright 2026 Parc contributors.
#include <CommonCrypto/CommonCryptor.h>
#include <CommonCrypto/CommonDigest.h>
#include <array>
#include <limits>
#include <map>
#include <optional>
#include <set>
#include <tuple>
#include "base/files/file.h"
#include "base/files/file_util.h"
#include "base/json/json_reader.h"
#include "base/numerics/checked_math.h"
#include "base/strings/strcat.h"
#include "base/strings/string_number_conversions.h"
#include "base/strings/utf_string_conversions.h"
#include "base/time/time.h"
#include "base/values.h"
#include "parc/importer/import_reader.h"
#include "parc/importer/import_snapshot.h"
#include "url/gurl.h"
namespace parc::importer {
namespace {
constexpr size_t kMaxRows = 1000000;
constexpr size_t kMaxJSON = 64 * 1024 * 1024;
bool Stopped(const Cancellation& stop) {
  return stop && stop->load();
}
constexpr std::array<uint8_t, kCCKeySizeAES128> kEmptyPasswordKey{
    0xd0, 0xd0, 0xec, 0x9c, 0x7d, 0x77, 0xd4, 0x3a,
    0xc5, 0x41, 0x87, 0xfa, 0x48, 0x18, 0xd1, 0x7f};
std::optional<std::string> DecryptCBC(std::string_view ciphertext,
                                      const void* key) {
  if (ciphertext.empty() || ciphertext.size() % kCCBlockSizeAES128)
    return std::nullopt;
  const std::array<uint8_t, kCCBlockSizeAES128> iv{
      ' ', ' ', ' ', ' ', ' ', ' ', ' ', ' ',
      ' ', ' ', ' ', ' ', ' ', ' ', ' ', ' '};
  std::string plain(ciphertext.size(), '\0');
  size_t written = 0;
  const bool decrypted =
      CCCrypt(kCCDecrypt, kCCAlgorithmAES, 0, key, kCCKeySizeAES128,
              iv.data(), ciphertext.data(), ciphertext.size(), plain.data(),
              plain.size(), &written) == kCCSuccess &&
      written == plain.size();
  const size_t padding = decrypted ? static_cast<uint8_t>(plain.back()) : 0;
  if (padding == 0 || padding > kCCBlockSizeAES128 ||
      plain.find_first_not_of(static_cast<char>(padding),
                              plain.size() - padding) != std::string::npos) {
    std::fill(plain.begin(), plain.end(), '\0');
    return std::nullopt;
  }
  plain.resize(plain.size() - padding);
  return plain;
}
std::optional<std::string> Decrypt(std::string_view encrypted,
                                   std::string_view key) {
  if (encrypted.empty())
    return std::string();
  if (!encrypted.starts_with("v10") || key.size() != kCCKeySizeAES128 ||
      encrypted.size() < 19)
    return std::nullopt;
  const auto ciphertext = encrypted.substr(3);
  if (auto plain = DecryptCBC(ciphertext, key.data()))
    return plain;
  return DecryptCBC(ciphertext, kEmptyPasswordKey.data());
}
std::optional<base::DictValue> ReadJSON(const base::FilePath& file) {
  std::string json;
  if (!base::ReadFileToStringWithMaxSize(file, &json, kMaxJSON))
    return std::nullopt;
  return base::JSONReader::ReadDict(json, base::JSON_PARSE_CHROMIUM_EXTENSIONS);
}
std::optional<base::DictValue> ReadEncryptedJSON(const base::FilePath& file,
                                                 std::string_view key) {
  std::string encrypted;
  if (!base::ReadFileToStringWithMaxSize(file, &encrypted,
                                         kMaxJSON + 3 + kCCBlockSizeAES128))
    return std::nullopt;
  auto json = Decrypt(encrypted, key);
  if (!json || json->empty())
    return std::nullopt;
  auto dict =
      base::JSONReader::ReadDict(*json, base::JSON_PARSE_CHROMIUM_EXTENSIONS);
  std::fill(json->begin(), json->end(), '\0');
  return dict;
}
std::string Column(sqlite3* db,
                   std::string_view table,
                   std::string_view name,
                   std::string_view fallback) {
  return HasColumn(db, table, name) ? std::string(name) : std::string(fallback);
}
bool FinishQuery(Statement& query,
                 std::string& error,
                 const Cancellation& stop) {
  if (Stopped(stop)) {
    error = "Import was cancelled.";
    return false;
  }
  if (!query.done()) {
    error = "The source database could not be read completely.";
    return false;
  }
  return true;
}
constexpr base::TimeDelta kSameSave = base::Minutes(1);
struct BookmarkRootKey {
  const char* container;
  const char* key;
};
constexpr BookmarkRootKey kBookmarkRoots[] = {{nullptr, "bookmark_bar"},
                                              {nullptr, "other"},
                                              {nullptr, "synced"},
                                              {"custom_root", "speedDial"},
                                              {"custom_root", "unsorted"}};
constexpr char kVivaldiTrash[] = "9f32a0fb-bfd9-5032-be46-07afe4a25400";
struct BookmarkTree {
  std::u16string title;
  std::string url;
  bool folder = false;
  std::vector<BookmarkTree> children;
};
using BookmarkRoots =
    std::array<std::optional<BookmarkTree>, std::size(kBookmarkRoots)>;
std::optional<base::Time> Modified(const base::FilePath& path) {
  base::File::Info info;
  if (!base::GetFileInfo(path, &info) || info.is_directory)
    return std::nullopt;
  return info.last_modified;
}
bool UsesEncryptedCopy(const base::FilePath& profile,
                       const ChromiumBookmarkFiles& files) {
  const auto plain = Modified(profile.AppendASCII(files.plain));
  const auto encrypted = Modified(profile.AppendASCII(files.encrypted));
  return encrypted && (!plain || *encrypted - *plain > kSameSave);
}
std::string_view Meta(const base::DictValue& node, std::string_view key) {
  const auto* meta = node.FindDict("meta_info");
  const auto* value = meta ? meta->FindString(key) : nullptr;
  return value ? std::string_view(*value) : std::string_view();
}
bool HiddenBookmark(const base::DictValue& node) {
  const auto* type = node.FindString("type");
  const auto* guid = node.FindString("guid");
  if (guid && *guid == kVivaldiTrash)
    return true;
  if (!type || *type != "url")
    return false;
  const auto* name = node.FindString("name");
  return (name && *name == "---" && Meta(node, "Description") == "separator") ||
         !Meta(node, "Partner").empty();
}
bool ParseBookmark(const base::DictValue& node,
                   BookmarkTree& tree,
                   size_t& count,
                   const Cancellation& stop,
                   int depth) {
  if (Stopped(stop) || depth > 128 || ++count > kMaxRows)
    return false;
  const auto* type = node.FindString("type");
  const auto* name = node.FindString("name");
  if (!type || !name)
    return false;
  tree.folder = *type == "folder";
  if (!tree.folder && *type != "url")
    return false;
  tree.title = base::UTF8ToUTF16(*name);
  if (!tree.folder) {
    const auto* url = node.FindString("url");
    if (!url || !GURL(*url).is_valid())
      return false;
    tree.url = *url;
    return true;
  }
  const auto* children = node.FindList("children");
  if (!children)
    return false;
  for (const auto& child : *children) {
    if (!child.is_dict())
      return false;
    if (HiddenBookmark(child.GetDict()))
      continue;
    if (!ParseBookmark(child.GetDict(), tree.children.emplace_back(), count,
                       stop, depth + 1))
      return false;
    const auto& parsed = tree.children.back();
    if (parsed.folder && parsed.children.empty() &&
        !Meta(child.GetDict(), "Partner").empty())
      tree.children.pop_back();
  }
  return true;
}
bool ParseBookmarkRoots(const base::DictValue& json,
                        BookmarkRoots& roots,
                        const Cancellation& stop) {
  const auto* dict = json.FindDict("roots");
  if (!dict)
    return false;
  size_t count = 0;
  for (size_t i = 0; i < std::size(kBookmarkRoots); ++i) {
    const auto& key = kBookmarkRoots[i];
    const auto* container =
        key.container ? dict->FindDict(key.container) : dict;
    const auto* root = container ? container->FindDict(key.key) : nullptr;
    if (!root || HiddenBookmark(*root))
      continue;
    if (!ParseBookmark(*root, roots[i].emplace(), count, stop, 0))
      return false;
  }
  return true;
}
struct BookmarkStore {
  bool present = false;
  bool read = false;
  BookmarkRoots roots;
  std::string problem;
};
BookmarkStore ReadBookmarkStore(const ReadOptions& options,
                                const ChromiumBookmarkFiles& files,
                                std::string_view label,
                                const Cancellation& stop) {
  BookmarkStore store;
  const auto plain = options.profile_path.AppendASCII(files.plain);
  const bool has_plain = Modified(plain).has_value();
  if (UsesEncryptedCopy(options.profile_path, files)) {
    store.present = true;
    auto json = options.source_key.empty()
                    ? std::nullopt
                    : ReadEncryptedJSON(
                          options.profile_path.AppendASCII(files.encrypted),
                          options.source_key);
    if (json && ParseBookmarkRoots(*json, store.roots, stop)) {
      store.read = true;
      return store;
    }
    store.problem =
        options.source_key.empty()
            ? base::StrCat({label,
                            " are encrypted, and the browser's encryption key "
                            "was unavailable."})
            : base::StrCat({label, " could not be decrypted."});
    if (!has_plain || Stopped(stop))
      return store;
    store.roots = {};
  }
  if (!has_plain)
    return store;
  store.present = true;
  auto json = ReadJSON(plain);
  if (json && ParseBookmarkRoots(*json, store.roots, stop)) {
    store.read = true;
    if (!store.problem.empty())
      store.problem += " An older unencrypted copy was imported instead.";
    return store;
  }
  if (!store.problem.empty())
    store.problem += " Their older unencrypted copy could not be read either.";
  else
    store.problem =
        json && json->FindDict("roots")
            ? base::StrCat({label, " contain unsupported or incomplete data."})
            : base::StrCat({label, " could not be read."});
  return store;
}
void MergeBookmarks(std::vector<BookmarkTree>& into,
                    std::vector<BookmarkTree> from) {
  std::map<std::tuple<bool, std::u16string, std::string>, std::vector<size_t>>
      unmatched;
  for (size_t i = into.size(); i-- > 0;)
    unmatched[{into[i].folder, into[i].title, into[i].url}].push_back(i);
  for (auto& node : from) {
    auto match = unmatched.find({node.folder, node.title, node.url});
    if (match == unmatched.end() || match->second.empty()) {
      into.push_back(std::move(node));
      continue;
    }
    const size_t index = match->second.back();
    match->second.pop_back();
    if (node.folder)
      MergeBookmarks(into[index].children, std::move(node.children));
  }
}
bool EmitBookmark(BookmarkTree& node,
                  const std::string& parent,
                  const std::string& id,
                  Batch& batch,
                  const Cancellation& stop) {
  if (Stopped(stop) || batch.bookmarks.size() >= kMaxRows)
    return false;
  batch.bookmarks.push_back(
      {id, parent, std::move(node.title), std::move(node.url), node.folder});
  for (size_t i = 0; i < node.children.size(); ++i) {
    if (!EmitBookmark(node.children[i], id,
                      id + "/" + base::NumberToString(i), batch, stop))
      return false;
  }
  return true;
}
bool ReadBookmarks(const ReadOptions& options,
                   Batch& batch,
                   const Cancellation& stop) {
  BookmarkStore account = ReadBookmarkStore(
      options, kChromiumAccountBookmarks, "The source account bookmarks", stop);
  BookmarkStore local = ReadBookmarkStore(options, kChromiumLocalBookmarks,
                                          "The source bookmarks", stop);
  if (Stopped(stop))
    return false;
  if (!account.read && !local.read) {
    batch.error = local.present     ? local.problem
                  : account.present ? account.problem
                                    : "The source bookmarks could not be read.";
    return false;
  }
  BookmarkRoots merged;
  for (auto* store : {&account, &local}) {
    if (!store->problem.empty())
      batch.warnings.push_back(store->problem);
    if (!store->read)
      continue;
    for (size_t i = 0; i < merged.size(); ++i) {
      auto& root = store->roots[i];
      if (!root)
        continue;
      if (merged[i])
        MergeBookmarks(merged[i]->children, std::move(root->children));
      else
        merged[i] = std::move(root);
    }
  }
  for (size_t i = 0; i < merged.size(); ++i) {
    if (merged[i] &&
        !EmitBookmark(*merged[i], "", kBookmarkRoots[i].key, batch, stop)) {
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
  return FinishQuery(query, batch.error, stop);
}
void Wipe(std::u16string& value) {
  std::fill(value.begin(), value.end(), u'\0');
}
struct Logins {
  Logins() = default;
  Logins(const Logins&) = delete;
  Logins& operator=(const Logins&) = delete;
  ~Logins() { Drop(); }
  void Drop() {
    for (auto& row : rows)
      Wipe(row.password);
    rows.clear();
    changed.clear();
    warnings.clear();
  }
  std::vector<Password> rows;
  std::vector<int64_t> changed;
  std::vector<std::string> warnings;
  std::string error;
};
bool ReadLogins(const base::FilePath& path,
                const ReadOptions& options,
                bool account,
                Logins& logins,
                const Cancellation& stop) {
  SnapshotDatabase db;
  if (!db.Open(path)) {
    logins.error = db.error();
    return false;
  }
  const std::string changed =
      Column(db.get(), "logins", "date_password_modified",
             HasColumn(db.get(), "logins", "date_created") ? "date_created"
                                                           : "0");
  Statement query(
      db.get(),
      "SELECT "
      "signon_realm,origin_url,action_url,username_element,username_value,"
      "password_element,password_value,scheme,blacklisted_by_user," +
          changed + " FROM logins");
  while (query.Step()) {
    if (Stopped(stop)) {
      logins.error = "Import was cancelled.";
      return false;
    }
    if (logins.rows.size() >= kMaxRows) {
      logins.error =
          "The source data exceeded supported limits or could not be read.";
      return false;
    }
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
      logins.error =
          account ? "Some passwords saved to the source browser's account "
                    "could not be decrypted, so none of them were imported."
                  : "Some source passwords could not be decrypted. No "
                    "passwords were imported.";
      return false;
    }
    if (value) {
      p.password = base::UTF8ToUTF16(*value);
      std::fill(value->begin(), value->end(), '\0');
    }
    if (p.realm.empty() || !GURL(p.url).is_valid() || p.scheme < 0 ||
        p.scheme > 2) {
      Wipe(p.password);
      logins.warnings.push_back("An unsupported password record was skipped.");
      continue;
    }
    logins.changed.push_back(query.Int(9));
    logins.rows.push_back(std::move(p));
  }
  return FinishQuery(query, logins.error, stop);
}
void MergeLogins(Logins& local, Logins& account, Batch& batch) {
  using Key = std::tuple<std::string, std::string, std::u16string,
                         std::u16string, std::u16string>;
  auto key = [](const Password& p) {
    return Key(p.realm, p.url, p.username_element, p.username,
               p.password_element);
  };
  batch.passwords = std::move(local.rows);
  std::vector<int64_t> changed = std::move(local.changed);
  std::map<Key, size_t> index;
  for (size_t i = 0; i < batch.passwords.size(); ++i)
    index.emplace(key(batch.passwords[i]), i);
  for (size_t i = 0; i < account.rows.size(); ++i) {
    auto& row = account.rows[i];
    auto [existing, added] = index.emplace(key(row), batch.passwords.size());
    if (added) {
      batch.passwords.push_back(std::move(row));
      changed.push_back(account.changed[i]);
    } else if (account.changed[i] >= changed[existing->second]) {
      Wipe(batch.passwords[existing->second].password);
      batch.passwords[existing->second] = std::move(row);
      changed[existing->second] = account.changed[i];
    } else {
      Wipe(row.password);
    }
  }
}
bool ReadPasswords(const ReadOptions& options,
                   Batch& batch,
                   const Cancellation& stop) {
  const auto local_path = options.profile_path.AppendASCII(kChromiumLogins);
  const auto account_path =
      options.profile_path.AppendASCII(kChromiumAccountLogins);
  const bool has_local = base::PathExists(local_path);
  const bool has_account = base::PathExists(account_path);
  Logins local, account;
  if ((has_local || !has_account) &&
      !ReadLogins(local_path, options, false, local, stop)) {
    batch.error = std::move(local.error);
    return false;
  }
  if (has_account) {
    bool read = ReadLogins(account_path, options, true, account, stop);
    if (read && local.rows.size() + account.rows.size() > kMaxRows) {
      account.error =
          "The source data exceeded supported limits or could not be read.";
      read = false;
    }
    if (!read) {
      if (Stopped(stop) || !has_local) {
        batch.error = std::move(account.error);
        return false;
      }
      account.Drop();
      batch.warnings.push_back(
          base::StrCat({"Passwords saved to the source browser's account were "
                        "not imported. ",
                        account.error}));
    }
  }
  for (auto* logins : {&local, &account})
    for (auto& warning : logins->warnings)
      batch.warnings.push_back(std::move(warning));
  MergeLogins(local, account, batch);
  return !Stopped(stop);
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
  return FinishQuery(query, batch.error, stop);
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
    if (!FinishQuery(query, batch.error, stop))
      return false;
  }
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
    if (!FinishQuery(query, batch.error, stop))
      return false;
    for (auto& [id, address] : addresses)
      batch.autofill.push_back(std::move(address));
  } else if (HasTable(db, "autofill_profiles")) {
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
    if (!FinishQuery(query, batch.error, stop))
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
      if (!FinishQuery(q, batch.error, stop))
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
    if (!FinishQuery(query, batch.error, stop))
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
}
std::optional<std::string> DecryptChromiumValue(std::string_view encrypted,
                                                std::string_view key) {
  return Decrypt(encrypted, key);
}
bool ChromiumBookmarksNeedKey(const base::FilePath& profile) {
  return UsesEncryptedCopy(profile, kChromiumAccountBookmarks) ||
         UsesEncryptedCopy(profile, kChromiumLocalBookmarks);
}
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
  else if (category == kPasswords)
    batch.success = ReadPasswords(options, batch, stop);
  else if (category == kExtensions)
    batch.success = ReadExtensions(options, batch, stop);
  else {
    const char* file = category == kHistory    ? "History"
                       : category == kAutofill ? "Web Data"
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
}
