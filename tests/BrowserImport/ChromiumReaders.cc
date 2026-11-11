#include <CommonCrypto/CommonCryptor.h>
#include <CommonCrypto/CommonDigest.h>
#include <array>
#include <cstdio>
#include <cstdlib>
#include "base/files/file_util.h"
#include "base/files/scoped_temp_dir.h"
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
