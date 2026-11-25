#include <CommonCrypto/CommonCryptor.h>
#include <CommonCrypto/CommonDigest.h>
#include <CommonCrypto/CommonKeyDerivation.h>
#include <array>
#include <cstdio>
#include <cstdlib>
#include "base/files/file_util.h"
#include "base/files/scoped_temp_dir.h"
#include "base/strings/strcat.h"
#include "base/strings/string_number_conversions.h"
#include "base/time/time.h"
#include "parc/importer/import_reader.h"
#include "sql/initialization.h"
#include "third_party/sqlite/sqlite3.h"
namespace {
int checks = 0;
void Require(bool yes, const char* message) {
  ++checks;
  if (!yes) {
    fprintf(stderr, "FAILED: %s\n", message);
    exit(1);
  }
}
void SQL(sqlite3* db, const char* text) {
  char* error = nullptr;
  int code = sqlite3_exec(db, text, nullptr, nullptr, &error);
  if (code != SQLITE_OK) {
    fprintf(stderr, "SQL: %s\n", error);
    sqlite3_free(error);
    exit(1);
  }
}
sqlite3* Database(const base::FilePath& path) {
  sql::EnsureSqliteInitialized(false);
  sqlite3* db = nullptr;
  Require(sqlite3_open(path.value().c_str(), &db) == SQLITE_OK,
          "private database");
  return db;
}
std::string Bytes(const base::FilePath& path) {
  std::string data;
  Require(base::ReadFileToString(path, &data), "fixture bytes");
  return data;
}
std::string Encrypt(std::string_view value, std::string_view key) {
  std::array<char, 16> iv;
  iv.fill(' ');
  std::string encrypted(value.size() + 32, '\0');
  size_t count = 0;
  Require(CCCrypt(kCCEncrypt, kCCAlgorithmAES, kCCOptionPKCS7Padding,
                  key.data(), key.size(), iv.data(), value.data(), value.size(),
                  encrypted.data(), encrypted.size(), &count) == kCCSuccess,
          "genuine fixture encryption");
  encrypted.resize(count);
  return "v10" + encrypted;
}
void Blob(sqlite3* db, const char* statement, std::string_view bytes) {
  sqlite3_stmt* s = nullptr;
  Require(sqlite3_prepare_v2(db, statement, -1, &s, nullptr) == SQLITE_OK,
          "fixture prepared insert");
  Require(sqlite3_bind_blob(s, 1, bytes.data(), bytes.size(),
                            SQLITE_TRANSIENT) == SQLITE_OK,
          "fixture bound ciphertext");
  Require(sqlite3_step(s) == SQLITE_DONE, "fixture committed row");
  sqlite3_finalize(s);
}
base::FilePath Directory(const base::FilePath& root, const char* name) {
  const auto path = root.AppendASCII(name);
  Require(base::CreateDirectory(path), "fixture profile");
  return path;
}
void Write(const base::FilePath& path, std::string_view data) {
  Require(base::WriteFile(path, data), "fixture file");
}
void Age(const base::FilePath& path, base::TimeDelta age) {
  const auto time = base::Time::Now() - age;
  Require(base::TouchFile(path, time, time), "fixture file age");
}
std::string Url(std::string_view name, std::string_view url) {
  return base::StrCat(
      {R"({"type":"url","name":")", name, R"(","url":")", url, R"("})"});
}
std::string Folder(std::string_view name, std::string_view children) {
  return base::StrCat({R"({"type":"folder","name":")", name,
                       R"(","children":[)", children, "]}"});
}
std::string Roots(std::string_view bar, std::string_view other = "") {
  return base::StrCat({R"({"roots":{"bookmark_bar":)", Folder("Bar", bar),
                       R"(,"other":)", Folder("Other", other), "}}"});
}
int Count(const parc::importer::Batch& batch, std::string_view url) {
  int count = 0;
  for (const auto& bookmark : batch.bookmarks)
    count += bookmark.url == url;
  return count;
}
void BookmarkStores(const base::FilePath& root,
                    const parc::importer::Cancellation& stop) {
  using namespace parc::importer;
  ReadOptions options;
  options.family = Family::kChromium;
  options.source_key = "0123456789abcdef";
  auto without_key = [&] {
    auto copy = options;
    copy.source_key.clear();
    return ReadChromiumCategory(copy, kBookmarks, stop);
  };
  options.profile_path = Directory(root, "encrypted-only");
  const auto encrypted =
      options.profile_path.AppendASCII("EncryptedBookmarks2");
  Write(encrypted,
        Encrypt(Roots(Url("Encrypted", "https://encrypted.test/")),
                options.source_key));
  Require(ChromiumBookmarksNeedKey(options.profile_path),
          "encrypted-only bookmarks ask for the key");
  auto original = Bytes(encrypted);
  auto b = ReadChromiumCategory(options, kBookmarks, stop);
  Require(b.success && b.bookmarks.size() == 3 &&
              b.bookmarks[1].url == "https://encrypted.test/" &&
              b.bookmarks[1].parent == "bookmark_bar",
          "encrypted-only bookmarks decrypt with the test key");
  Require(Bytes(encrypted) == original, "encrypted bookmarks untouched");
  b = without_key();
  Require(!b.success && b.bookmarks.empty() && !b.error.empty(),
          "encrypted-only bookmarks without the key refuse");
  options.profile_path = Directory(root, "copies");
  const auto plain = options.profile_path.AppendASCII("Bookmarks");
  Write(plain, Roots(Url("Plain", "https://plain.test/")));
  Write(options.profile_path.AppendASCII("EncryptedBookmarks2"),
        Encrypt(Roots(Url("Encrypted", "https://encrypted.test/")),
                options.source_key));
  Require(!ChromiumBookmarksNeedKey(options.profile_path),
          "copies saved together need no key");
  b = ReadChromiumCategory(options, kBookmarks, stop);
  Require(b.success && b.bookmarks.size() == 3 &&
              Count(b, "https://plain.test/") == 1 &&
              Count(b, "https://encrypted.test/") == 0 && b.warnings.empty(),
          "copies saved together import one copy");
  Age(plain, base::Minutes(10));
  Require(ChromiumBookmarksNeedKey(options.profile_path),
          "an older plain copy asks for the key");
  b = ReadChromiumCategory(options, kBookmarks, stop);
  Require(b.success && Count(b, "https://encrypted.test/") == 1 &&
              Count(b, "https://plain.test/") == 0,
          "a newer encrypted copy wins");
  b = without_key();
  Require(b.success && Count(b, "https://plain.test/") == 1 &&
              !b.warnings.empty(),
          "a declined key falls back to the plain copy");
  auto wrong = options;
  wrong.source_key = "fedcba9876543210";
  b = ReadChromiumCategory(wrong, kBookmarks, stop);
  Require(b.success && Count(b, "https://plain.test/") == 1 &&
              !b.warnings.empty(),
          "an undecryptable copy falls back to the plain copy");
  Age(options.profile_path.AppendASCII("EncryptedBookmarks2"),
      base::Minutes(20));
  Require(!ChromiumBookmarksNeedKey(options.profile_path),
          "a stale encrypted copy needs no key");
  b = ReadChromiumCategory(options, kBookmarks, stop);
  Require(b.success && Count(b, "https://plain.test/") == 1 &&
              Count(b, "https://encrypted.test/") == 0,
          "a stale encrypted copy is ignored");
  options.profile_path = Directory(root, "account-only");
  Write(options.profile_path.AppendASCII("AccountBookmarks"),
        Roots(Url("Account", "https://account.test/")));
  Require(!ChromiumBookmarksNeedKey(options.profile_path),
          "plain account bookmarks need no key");
  b = ReadChromiumCategory(options, kBookmarks, stop);
  Require(b.success && b.bookmarks.size() == 3 &&
              Count(b, "https://account.test/") == 1,
          "account bookmarks alone are imported");
  options.profile_path = Directory(root, "merged");
  Write(options.profile_path.AppendASCII("AccountBookmarks"),
        Roots(base::StrCat({Url("Shared", "https://shared.test/"), ",",
                            Folder("Work", Url("Docs", "https://docs.test/")),
                            ",", Url("Account", "https://account.test/")})));
  Write(options.profile_path.AppendASCII("Bookmarks"),
        Roots(base::StrCat({Url("Shared", "https://shared.test/"), ",",
                            Url("Shared", "https://shared.test/"), ",",
                            Folder("Work",
                                   base::StrCat({Url("Docs", "https://docs.test/"),
                                                 ",",
                                                 Url("Wiki", "https://wiki.test/")})),
                            ",", Url("Local", "https://local.test/")}),
              Url("Elsewhere", "https://elsewhere.test/")));
  b = ReadChromiumCategory(options, kBookmarks, stop);
  Require(b.success && b.bookmarks.size() == 10,
          "account and local bookmarks merge");
  Require(b.bookmarks[1].url == "https://shared.test/" &&
              b.bookmarks[2].folder && b.bookmarks[2].title == u"Work" &&
              b.bookmarks[3].parent == b.bookmarks[2].id &&
              b.bookmarks[4].url == "https://wiki.test/" &&
              b.bookmarks[4].parent == b.bookmarks[2].id &&
              b.bookmarks[5].url == "https://account.test/" &&
              b.bookmarks[6].url == "https://shared.test/" &&
              b.bookmarks[7].url == "https://local.test/" &&
              b.bookmarks[8].parent.empty() &&
              b.bookmarks[9].url == "https://elsewhere.test/",
          "account bookmarks lead and same-named folders combine");
  Require(Count(b, "https://docs.test/") == 1 &&
              Count(b, "https://shared.test/") == 2,
          "a bookmark in both stores appears once");
  options.profile_path = Directory(root, "encrypted-account");
  Write(options.profile_path.AppendASCII("EncryptedAccountBookmarks2"),
        Encrypt(Roots(Url("Account", "https://account.test/")),
                options.source_key));
  Write(options.profile_path.AppendASCII("Bookmarks"),
        Roots(Url("Local", "https://local.test/")));
  Require(ChromiumBookmarksNeedKey(options.profile_path),
          "encrypted account bookmarks ask for the key");
  b = ReadChromiumCategory(options, kBookmarks, stop);
  Require(b.success && Count(b, "https://account.test/") == 1 &&
              Count(b, "https://local.test/") == 1,
          "encrypted account and plain local bookmarks merge");
  b = without_key();
  Require(b.success && Count(b, "https://local.test/") == 1 &&
              Count(b, "https://account.test/") == 0 && !b.warnings.empty(),
          "a declined key keeps local bookmarks");
  options.profile_path = Directory(root, "no-bookmarks");
  Require(!ReadChromiumCategory(options, kBookmarks, stop).success,
          "missing bookmark files refuse");
}
void BookmarkRootPresentation(const base::FilePath& root,
                              const parc::importer::Cancellation& stop) {
  using namespace parc::importer;
  ReadOptions options;
  options.family = Family::kChromium;
  options.profile_path = Directory(root, "vivaldi-roots");
  Write(options.profile_path.AppendASCII("Bookmarks"),
        R"({"roots":{"bookmark_bar":{"type":"folder","name":"Bookmarks","children":[)"
        R"({"type":"url","name":"Keep","url":"https://keep.test/"},)"
        R"({"type":"url","name":"---","url":"","meta_info":{"Description":"separator"}},)"
        R"({"type":"url","name":"Dashes","url":"https://dashes.test/","meta_info":{"Description":"note"}},)"
        R"({"type":"folder","name":"Speed Dial","meta_info":{"Speeddial":"true"},"children":[)"
        R"({"type":"url","name":"Mine","url":"https://mine.test/"},)"
        R"({"type":"url","name":"Sponsor","url":"https://sponsor.test/","meta_info":{"Partner":"5d2b4a"}}]},)"
        R"({"type":"folder","name":"Shopping","meta_info":{"Partner":"7e1c9f"},"children":[)"
        R"({"type":"url","name":"Store","url":"https://store.test/","meta_info":{"Partner":"8a3f2d"}}]},)"
        R"({"type":"folder","name":"Trash","guid":"9f32a0fb-bfd9-5032-be46-07afe4a25400","children":[)"
        R"({"type":"url","name":"Old","url":"https://trashed.test/"}]}]},)"
        R"("other":{"type":"folder","name":"Other bookmarks","children":[]},)"
        R"("trash":{"type":"folder","name":"Trash","guid":"9f32a0fb-bfd9-5032-be46-07afe4a25400","children":[)"
        R"({"type":"url","name":"Gone","url":"https://gone.test/"}]}}})");
  auto b = ReadChromiumCategory(options, kBookmarks, stop);
  Require(b.success && b.bookmarks.size() == 6,
          "Vivaldi trash, separators and partner entries are left out");
  Require(b.bookmarks[0].title == u"Bookmarks" &&
              b.bookmarks[1].url == "https://keep.test/" &&
              b.bookmarks[2].url == "https://dashes.test/" &&
              b.bookmarks[3].folder && b.bookmarks[3].title == u"Speed Dial" &&
              b.bookmarks[4].url == "https://mine.test/" &&
              b.bookmarks[4].parent == b.bookmarks[3].id &&
              b.bookmarks[5].title == u"Other bookmarks",
          "Vivaldi user bookmarks and Speed Dial keep their order");
  Require(Count(b, "https://trashed.test/") == 0 &&
              Count(b, "https://gone.test/") == 0 &&
              Count(b, "https://sponsor.test/") == 0 &&
              Count(b, "https://store.test/") == 0,
          "Vivaldi trashed and partner addresses never appear");
  options.profile_path = Directory(root, "opera-roots");
  Write(options.profile_path.AppendASCII("Bookmarks"),
        R"({"roots":{"bookmark_bar":{"type":"folder","name":"Bookmarks bar","children":[]},)"
        R"("other":{"type":"folder","name":"Other bookmarks","children":[]},)"
        R"("synced":{"type":"folder","name":"Mobile bookmarks","children":[]},)"
        R"("custom_root":{)"
        R"("speedDial":{"type":"folder","name":"Speed Dial","children":[)"
        R"({"type":"url","name":"Tile","url":"https://tile.test/","meta_info":{"imageID":"i1"}}]},)"
        R"("trash":{"type":"folder","name":"Trash","children":[)"
        R"({"type":"url","name":"Binned","url":"https://binned.test/"}]},)"
        R"("unsorted":{"type":"folder","name":"Unsorted bookmarks","children":[)"
        R"({"type":"url","name":"Loose","url":"https://loose.test/"}]},)"
        R"("extra":{"type":"folder","name":"Unknown","children":[]}}}})");
  b = ReadChromiumCategory(options, kBookmarks, stop);
  Require(b.success && b.bookmarks.size() == 7,
          "Opera Speed Dial and Unsorted import while its Trash does not");
  Require(b.bookmarks[3].title == u"Speed Dial" &&
              b.bookmarks[3].id == "speedDial" &&
              b.bookmarks[4].url == "https://tile.test/" &&
              b.bookmarks[4].parent == "speedDial" &&
              b.bookmarks[5].title == u"Unsorted bookmarks" &&
              b.bookmarks[6].url == "https://loose.test/" &&
              b.bookmarks[6].parent == "unsorted",
          "Opera custom roots follow the standard roots as ordinary folders");
  Require(Count(b, "https://binned.test/") == 0,
          "Opera trashed bookmarks never appear");
}
void LoginTable(const base::FilePath& path) {
  sqlite3* db = Database(path);
  SQL(db,
      "CREATE TABLE logins(signon_realm TEXT,origin_url TEXT,action_url "
      "TEXT,username_element TEXT,username_value TEXT,password_element "
      "TEXT,password_value BLOB,scheme INTEGER,blacklisted_by_user "
      "INTEGER,date_password_modified INTEGER);");
  sqlite3_close(db);
}
void Login(const base::FilePath& path,
           std::string_view site,
           std::string_view secret,
           int changed) {
  sqlite3* db = Database(path);
  const auto statement = base::StrCat(
      {"INSERT INTO logins VALUES('", site, "','", site,
       "','','user','alice','pass',?,0,0,", base::NumberToString(changed),
       ")"});
  Blob(db, statement.c_str(), secret);
  sqlite3_close(db);
}
const parc::importer::Password* Find(const parc::importer::Batch& batch,
                                     std::string_view site) {
  for (const auto& password : batch.passwords)
    if (password.realm == site)
      return &password;
  return nullptr;
}
void AccountPasswords(const base::FilePath& root,
                      const parc::importer::Cancellation& stop) {
  using namespace parc::importer;
  ReadOptions options;
  options.family = Family::kChromium;
  options.source_key = "0123456789abcdef";
  const auto& key = options.source_key;
  options.profile_path = Directory(root, "account-passwords");
  const auto account = options.profile_path.AppendASCII("Login Data For Account");
  LoginTable(account);
  Login(account, "https://account.test/", Encrypt("account only", key), 200);
  auto original = Bytes(account);
  auto p = ReadChromiumCategory(options, kPasswords, stop);
  Require(p.success && p.passwords.size() == 1 &&
              p.passwords[0].password == u"account only",
          "account passwords alone are imported");
  Require(Bytes(account) == original, "account password database untouched");
  const auto local = options.profile_path.AppendASCII("Login Data");
  LoginTable(local);
  Login(local, "https://shared.test/", Encrypt("local older", key), 100);
  Login(local, "https://local.test/", Encrypt("local only", key), 100);
  Login(local, "https://kept.test/", Encrypt("local newer", key), 300);
  Login(account, "https://shared.test/", Encrypt("account newer", key), 200);
  Login(account, "https://kept.test/", Encrypt("account older", key), 200);
  p = ReadChromiumCategory(options, kPasswords, stop);
  Require(p.success && p.passwords.size() == 4,
          "a login saved in both files is imported once");
  Require(Find(p, "https://shared.test/") && Find(p, "https://kept.test/") &&
              Find(p, "https://shared.test/")->password == u"account newer" &&
              Find(p, "https://kept.test/")->password == u"local newer" &&
              Find(p, "https://local.test/") && Find(p, "https://account.test/"),
          "the most recently changed copy of a login wins");
  Login(account, "https://broken.test/", "v20unsupported", 400);
  p = ReadChromiumCategory(options, kPasswords, stop);
  Require(p.success && p.passwords.size() == 3 &&
              !Find(p, "https://account.test/") &&
              Find(p, "https://shared.test/") &&
              Find(p, "https://shared.test/")->password == u"local older" &&
              !p.warnings.empty(),
          "an unreadable account file only warns");
  Require(base::DeleteFile(local), "remove local logins");
  p = ReadChromiumCategory(options, kPasswords, stop);
  Require(!p.success && p.passwords.empty() && !p.error.empty(),
          "an unreadable account file alone refuses");
}
std::string EmptyPasswordKey() {
  std::array<uint8_t, kCCKeySizeAES128> key;
  const char salt[] = "saltysalt";
  Require(CCKeyDerivationPBKDF(kCCPBKDF2, "", 0,
                               reinterpret_cast<const uint8_t*>(salt),
                               sizeof(salt) - 1, kCCPRFHmacAlgSHA1, 1,
                               key.data(), key.size()) == kCCSuccess,
          "empty-password key derivation");
  return std::string(reinterpret_cast<const char*>(key.data()), key.size());
}
void FallbackKey(const base::FilePath& root,
                 const parc::importer::Cancellation& stop) {
  using namespace parc::importer;
  ReadOptions options;
  options.family = Family::kChromium;
  options.source_key = "0123456789abcdef";
  auto without_key = options;
  without_key.source_key.clear();
  const auto fallback = EmptyPasswordKey();
  options.profile_path = Directory(root, "fallback-key");
  without_key.profile_path = options.profile_path;
  Write(options.profile_path.AppendASCII("EncryptedBookmarks2"),
        Encrypt(Roots(Url("Rescued", "https://rescued.test/")), fallback));
  auto b = ReadChromiumCategory(options, kBookmarks, stop);
  Require(b.success && Count(b, "https://rescued.test/") == 1 &&
              b.warnings.empty(),
          "bookmarks saved with the fallback key decrypt");
  Require(!ReadChromiumCategory(without_key, kBookmarks, stop).success,
          "fallback-key bookmarks still need the browser's key");
  const auto logins = options.profile_path.AppendASCII("Login Data");
  LoginTable(logins);
  Login(logins, "https://rescued.test/", Encrypt("rescued", fallback), 100);
  auto p = ReadChromiumCategory(options, kPasswords, stop);
  Require(p.success && p.passwords.size() == 1 &&
              p.passwords[0].password == u"rescued",
          "a password saved with the fallback key decrypts");
  Require(!ReadChromiumCategory(without_key, kPasswords, stop).success,
          "the fallback key is tried only after the browser's key");
  Login(logins, "https://normal.test/", Encrypt("normal", options.source_key),
        200);
  p = ReadChromiumCategory(options, kPasswords, stop);
  Require(p.success && p.passwords.size() == 2 &&
              Find(p, "https://rescued.test/") &&
              Find(p, "https://rescued.test/")->password == u"rescued" &&
              Find(p, "https://normal.test/") &&
              Find(p, "https://normal.test/")->password == u"normal",
          "fallback-key and ordinary passwords import together");
  Login(logins, "https://neither.test/",
        Encrypt("matches neither", "fedcba9876543210"), 300);
  Require(!ReadChromiumCategory(options, kPasswords, stop).success,
          "a password matching neither key still refuses");
  sqlite3* db = Database(options.profile_path.AppendASCII("Cookies"));
  SQL(db,
      "CREATE TABLE meta(key TEXT,value INTEGER);INSERT INTO meta "
      "VALUES('version',24);CREATE TABLE cookies(host_key TEXT,name TEXT,value "
      "TEXT,path TEXT,creation_utc INTEGER,expires_utc INTEGER,last_access_utc "
      "INTEGER,is_secure INTEGER,is_httponly INTEGER,encrypted_value BLOB);");
  std::array<unsigned char, CC_SHA256_DIGEST_LENGTH> digest;
  const std::string host = ".rescued.test";
  CC_SHA256(host.data(), host.size(), digest.data());
  std::string payload(reinterpret_cast<char*>(digest.data()), digest.size());
  payload += "rescued cookie";
  Blob(db,
       "INSERT INTO cookies "
       "VALUES('.rescued.test','token','','/',1,2,3,1,1,?)",
       Encrypt(payload, fallback));
  sqlite3_close(db);
  auto c = ReadChromiumCategory(options, kCookies, stop);
  Require(c.success && c.cookies.size() == 1 &&
              c.cookies[0].value == "rescued cookie",
          "a cookie saved with the fallback key decrypts");
  db = Database(options.profile_path.AppendASCII("Web Data"));
  SQL(db,
      "CREATE TABLE credit_cards(name_on_card TEXT,expiration_month "
      "INTEGER,expiration_year INTEGER,card_number_encrypted BLOB);");
  Blob(db, "INSERT INTO credit_cards VALUES('Rescued',1,2031,?)",
       Encrypt("5555555555554444", fallback));
  sqlite3_close(db);
  auto a = ReadChromiumCategory(options, kAutofill, stop);
  Require(a.success && a.autofill.size() == 1 &&
              a.autofill[0].fields["number"] == u"5555555555554444",
          "a card saved with the fallback key decrypts");
}
}
int main() {
  using namespace parc::importer;
  base::ScopedTempDir temp;
  Require(temp.CreateUniqueTempDir(), "isolated root");
  ReadOptions options;
  options.family = Family::kChromium;
  options.profile_path = temp.GetPath();
  options.source_key = "0123456789abcdef";
  auto stop = std::make_shared<std::atomic_bool>(false);
  const auto bookmarks = temp.GetPath().AppendASCII("Bookmarks");
  Require(
      base::WriteFile(
          bookmarks,
          R"({"roots":{"bookmark_bar":{"type":"folder","name":"Bar","children":[{"type":"url","name":"Café","url":"https://example.test/"},{"type":"folder","name":"Empty","children":[]}]},"other":{"type":"folder","name":"Other","children":[]}}})"),
      "bookmarks fixture");
  auto b = ReadChromiumCategory(options, kBookmarks, stop);
  Require(b.success && b.bookmarks.size() == 4,
          "ordered roots and empty folders");
  Require(b.bookmarks[1].parent == b.bookmarks[0].id &&
              b.bookmarks[1].title == u"Café",
          "original tree Unicode");
  Require(b.bookmarks[3].parent.empty(), "separate source root");
  auto original = Bytes(bookmarks);
  Require(ReadChromiumCategory(options, kBookmarks, stop).success &&
              Bytes(bookmarks) == original,
          "original JSON untouched");
  const auto history = temp.GetPath().AppendASCII("History");
  sqlite3* db = Database(history);
  SQL(db,
      "PRAGMA journal_mode=WAL;PRAGMA wal_autocheckpoint=0;CREATE TABLE "
      "urls(id INTEGER,url TEXT,title TEXT,visit_count INTEGER,typed_count "
      "INTEGER,last_visit_time INTEGER,hidden INTEGER);INSERT INTO urls "
      "VALUES(1,'https://example.test/','History',3,2,13300000000000000,1);");
  auto h = ReadChromiumCategory(options, kHistory, stop);
  Require(h.success && h.history.size() == 1 && h.history[0].hidden &&
              h.history[0].typed == 2,
          "actual uncheckpointed WAL history");
  Require(h.history[0].last_visit == 13300000000000000LL,
          "Chromium epoch preserved");
  sqlite3_close(db);
  const auto login = temp.GetPath().AppendASCII("Login Data");
  db = Database(login);
  SQL(db,
      "CREATE TABLE logins(signon_realm TEXT,origin_url TEXT,action_url "
      "TEXT,username_element TEXT,username_value TEXT,password_element "
      "TEXT,password_value BLOB,scheme INTEGER,blacklisted_by_user INTEGER);");
  Blob(db,
       "INSERT INTO logins "
       "VALUES('https://example.test/','https://example.test/login','https://"
       "example.test/post','user','alice','pass',?,0,0)",
       Encrypt("fixture secret", options.source_key));
  sqlite3_close(db);
  original = Bytes(login);
  auto p = ReadChromiumCategory(options, kPasswords, stop);
  Require(p.success && p.passwords.size() == 1 &&
              p.passwords[0].password == u"fixture secret",
          "actual CBC password decrypt");
  Require(p.passwords[0].action == "https://example.test/post" &&
              p.passwords[0].username == u"alice",
          "password metadata intact");
  Require(Bytes(login) == original, "source encrypted database unchanged");
  auto wrong = options;
  wrong.source_key.clear();
  auto failed = ReadChromiumCategory(wrong, kPasswords, stop);
  Require(!failed.success && failed.passwords.empty(),
          "unavailable key refuses entire password category");
  db = Database(login);
  Blob(db,
       "INSERT INTO logins "
       "VALUES('https://other.test/','https://other.test/','','','','',?,0,0)",
       "v20unsupported");
  sqlite3_close(db);
  failed = ReadChromiumCategory(options, kPasswords, stop);
  Require(!failed.success && failed.passwords.empty(),
          "later unsupported encryption publishes no partial passwords");
  BookmarkStores(temp.GetPath(), stop);
  BookmarkRootPresentation(temp.GetPath(), stop);
  AccountPasswords(temp.GetPath(), stop);
  FallbackKey(temp.GetPath(), stop);
  const auto cookies = temp.GetPath().AppendASCII("Cookies");
  db = Database(cookies);
  SQL(db,
      "CREATE TABLE meta(key TEXT,value INTEGER);INSERT INTO meta "
      "VALUES('version',24);CREATE TABLE cookies(host_key TEXT,name TEXT,value "
      "TEXT,path TEXT,creation_utc INTEGER,expires_utc INTEGER,last_access_utc "
      "INTEGER,is_secure INTEGER,is_httponly INTEGER,encrypted_value "
      "BLOB,samesite INTEGER,priority INTEGER,source_scheme "
      "INTEGER,source_port INTEGER,top_frame_site_key "
      "TEXT,has_cross_site_ancestor INTEGER);");
  std::array<unsigned char, CC_SHA256_DIGEST_LENGTH> digest;
  std::string host = ".example.test";
  CC_SHA256(host.data(), host.size(), digest.data());
  std::string payload(reinterpret_cast<char*>(digest.data()), digest.size());
  payload += "cookie value";
  Blob(db,
       "INSERT INTO cookies "
       "VALUES('.example.test','token','','/',1,2,3,1,1,?,2,1,2,443,'https://"
       "partition.test',0)",
       Encrypt(payload, options.source_key));
  sqlite3_close(db);
  auto c = ReadChromiumCategory(options, kCookies, stop);
  Require(c.success && c.cookies.size() == 1 &&
              c.cookies[0].value == "cookie value",
          "v24 cookie host integrity and decryption");
  Require(c.cookies[0].top_frame_site == "https://partition.test" &&
              !c.cookies[0].ancestor_cross_site &&
              c.cookies[0].source_port == 443,
          "cookie partition and source metadata");
  db = Database(cookies);
  SQL(db, "UPDATE cookies SET host_key='.changed.test'");
  sqlite3_close(db);
  failed = ReadChromiumCategory(options, kCookies, stop);
  Require(!failed.success && failed.cookies.empty(),
          "cross-host encrypted cookie rejected");
  const auto web = temp.GetPath().AppendASCII("Web Data");
  db = Database(web);
  SQL(db,
      "CREATE TABLE autofill(name TEXT,value TEXT,date_created "
      "INTEGER,date_last_used INTEGER,count INTEGER);INSERT INTO autofill "
      "VALUES('city','Edmonton',100,200,4);CREATE TABLE "
      "address_type_tokens(guid TEXT,type INTEGER,value TEXT);INSERT INTO "
      "address_type_tokens "
      "VALUES('original',3,'Josh'),('original',34,'Edmonton');CREATE TABLE "
      "credit_cards(name_on_card TEXT,expiration_month INTEGER,expiration_year "
      "INTEGER,card_number_encrypted BLOB,nickname TEXT);");
  Blob(db, "INSERT INTO credit_cards VALUES('Test',12,2030,?,'Fixture')",
       Encrypt("4111111111111111", options.source_key));
  sqlite3_close(db);
  auto a = ReadChromiumCategory(options, kAutofill, stop);
  Require(a.success && a.autofill.size() == 3,
          "forms addresses local card actual records");
  Require(a.autofill[0].created == 11644473700000000LL &&
              a.autofill[0].fields["value"] == u"Edmonton",
          "form time and value");
  Require(a.autofill[1].fields.size() == 2 &&
              a.autofill[2].fields["number"] == u"4111111111111111",
          "address tokens and card bytes");
  db = Database(web);
  SQL(db,
      "DROP TABLE address_type_tokens; CREATE TABLE autofill_profiles(guid "
      "TEXT,company_name TEXT,street_address TEXT,city TEXT,state TEXT,zipcode "
      "TEXT,country_code TEXT); INSERT INTO autofill_profiles "
      "VALUES('legacy','Example','123 Test','Edmonton','AB','T1X1X1','CA'); "
      "CREATE TABLE autofill_profile_names(guid TEXT,first_name TEXT,full_name "
      "TEXT); INSERT INTO autofill_profile_names VALUES('legacy','Josh','Josh "
      "Example'); CREATE TABLE autofill_profile_emails(guid TEXT,email TEXT); "
      "INSERT INTO autofill_profile_emails "
      "VALUES('legacy','example@example.test');");
  sqlite3_close(db);
  a = ReadChromiumCategory(options, kAutofill, stop);
  Require(a.success && a.autofill.size() == 3,
          "genuine legacy address schema supported");
  Require(a.autofill[1].fields["7"] == u"Josh Example" &&
              a.autofill[1].fields["9"] == u"example@example.test" &&
              a.autofill[1].fields["77"] == u"123 Test",
          "legacy name email and address fields retained");
  const std::string id(32, 'a');
  Require(base::WriteFile(temp.GetPath().AppendASCII("Secure Preferences"),
                          "{\"extensions\":{\"settings\":{\"" + id +
                              "\":{\"from_webstore\":true,\"manifest\":{"
                              "\"name\":\"Fixture\"}}}}}"),
          "source extension preferences");
  auto e = ReadChromiumCategory(options, kExtensions, stop);
  Require(e.success && e.extensions.empty(),
          "empty consent selection installs none");
  options.extension_ids = {id};
  e = ReadChromiumCategory(options, kExtensions, stop);
  Require(e.success && e.extensions.size() == 1 && e.extensions[0].id == id,
          "only exact allowed WebStore ID");
  options.extension_ids = {std::string(32, 'b')};
  e = ReadChromiumCategory(options, kExtensions, stop);
  Require(e.success && e.extensions.empty() && !e.warnings.empty(),
          "changed extension excluded with warning");
  stop->store(true);
  failed = ReadChromiumCategory(options, kHistory, stop);
  Require(!failed.success && failed.history.empty(), "cancel before snapshot");
  stop->store(false);
  wrong = options;
  wrong.profile_path = base::FilePath("relative");
  Require(!ReadChromiumCategory(wrong, kHistory, stop).success,
          "relative source refused");
  wrong = options;
  wrong.family = Family::kSafari;
  Require(!ReadChromiumCategory(wrong, kHistory, stop).success,
          "foreign source family refused");
  printf("PASS: %d Chromium import reader checks\n", checks);
  return 0;
}
