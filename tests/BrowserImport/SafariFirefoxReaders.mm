#import <Foundation/Foundation.h>
#include <cstdio>
#include <cstdlib>
#include <string>
#include "base/files/file_util.h"
#include "base/files/scoped_temp_dir.h"
#include "parc/importer/import_reader.h"
#include "third_party/sqlite/sqlite3.h"
#include "sql/initialization.h"

namespace {
int checks = 0;
void Require(bool condition, const char* message) {
  ++checks;
  if (!condition) { std::fprintf(stderr, "FAILED: %s\n", message); std::exit(1); }
}
void SQL(sqlite3* db, const char* sql) {
  char* error = nullptr;
  int result = sqlite3_exec(db, sql, nullptr, nullptr, &error);
  if (result != SQLITE_OK) {
    std::fprintf(stderr, "Fixture SQL: %s\n", error ? error : "unknown");
    sqlite3_free(error); std::exit(1);
  }
}
sqlite3* Database(const base::FilePath& path) {
  sql::EnsureSqliteInitialized(false);
  sqlite3* db = nullptr;
  Require(sqlite3_open(path.value().c_str(), &db) == SQLITE_OK, "create disposable database");
  return db;
}
std::string Bytes(const base::FilePath& path) {
  std::string bytes;
  Require(base::ReadFileToString(path, &bytes), "read fixture bytes");
  return bytes;
}
void Plist(const base::FilePath& path, id object, NSPropertyListFormat format) {
  NSData* bytes = [NSPropertyListSerialization dataWithPropertyList:object
      format:format options:0 error:nil];
  Require(bytes != nil, "encode fixture plist");
  Require(base::WriteFile(path, std::string_view(static_cast<const char*>(bytes.bytes), bytes.length)),
          "write fixture plist");
}
void Safari(const base::FilePath& path) {
  using namespace parc::importer;
  ReadOptions options; options.family = Family::kSafari; options.profile_path = path;
  auto cancel = std::make_shared<std::atomic_bool>(false);
  const auto bookmarks = path.AppendASCII("Bookmarks.plist");
  NSDictionary* leaf = @{@"WebBookmarkType":@"WebBookmarkTypeLeaf", @"URLString":@"https://example.test/a",
                         @"URIDictionary":@{@"title":@"Café 🦊"}};
  NSDictionary* root = @{@"WebBookmarkFileVersion":@1, @"Children":@[
      @{@"WebBookmarkType":@"WebBookmarkTypeList", @"Title":@"BookmarksMenu", @"Children":@[leaf]},
      @{@"WebBookmarkType":@"WebBookmarkTypeList", @"Title":@"BookmarksBar", @"Children":@[
          @{@"WebBookmarkType":@"WebBookmarkTypeList", @"Title":@"Empty", @"Children":@[]}, leaf]},
      @{@"WebBookmarkType":@"Unsupported"}]};
  for (NSNumber* format in @[@(NSPropertyListXMLFormat_v1_0), @(NSPropertyListBinaryFormat_v1_0)]) {
    Plist(bookmarks, root, static_cast<NSPropertyListFormat>(format.unsignedIntegerValue));
    const auto original = Bytes(bookmarks);
    auto result = ReadSafariCategory(options, kBookmarks, cancel);
    Require(result.success && result.bookmarks.size() == 4, "Safari XML/binary nested bookmarks");
    Require(result.bookmarks[0].parent.empty() && result.bookmarks[0].title == u"Café 🦊", "Safari menu flatten and Unicode");
    Require(result.bookmarks[1].folder && result.bookmarks[2].folder, "Safari toolbar and empty folder survive");
    Require(result.bookmarks[3].parent == result.bookmarks[1].id, "Safari exact parent identity");
    Require(result.warnings.size() == 1, "Safari skipped item reported");
    Require(Bytes(bookmarks) == original, "Safari original plist unchanged");
  }
  cancel->store(true);
  Require(!ReadSafariCategory(options, kBookmarks, cancel).success, "Safari cancellation");
  cancel->store(false);
  Plist(bookmarks, @{@"Children":@[leaf, @{@"WebBookmarkType":@"WebBookmarkTypeLeaf"}]}, NSPropertyListBinaryFormat_v1_0);
  auto bad = ReadSafariCategory(options, kBookmarks, cancel);
  Require(!bad.success && bad.bookmarks.empty(), "Safari malformed leaf publishes no partial category");
  NSMutableDictionary* chain = [@{@"WebBookmarkType":@"WebBookmarkTypeList", @"Title":@"deep"} mutableCopy];
  NSDictionary* deep = chain;
  for (int i = 0; i < 130; ++i) {
    NSMutableDictionary* next = [@{@"WebBookmarkType":@"WebBookmarkTypeList", @"Title":@"deep"} mutableCopy];
    chain[@"Children"] = @[next]; chain = next;
  }
  Plist(bookmarks, @{@"Children":@[deep]}, NSPropertyListBinaryFormat_v1_0);
  Require(!ReadSafariCategory(options, kBookmarks, cancel).success, "Safari depth limit");
  Require(base::WriteFile(bookmarks, "not a plist"), "write invalid plist");
  Require(!ReadSafariCategory(options, kBookmarks, cancel).success, "Safari invalid plist rejected");
  const auto history = path.AppendASCII("History.db");
  sqlite3* db = Database(history);
  SQL(db, "CREATE TABLE history_items(id INTEGER,url TEXT,visit_count INTEGER);"
          "CREATE TABLE history_visits(history_item INTEGER,title TEXT,visit_time REAL);"
          "INSERT INTO history_items VALUES(1,'https://example.test/',3),(2,'https://invalid.test/',-1);"
          "INSERT INTO history_visits VALUES(1,'One',0.25),(1,'Two',1.5),(2,'Invalid',0);");
  sqlite3_close(db);
  const auto original = Bytes(history);
  auto result = ReadSafariCategory(options, kHistory, cancel);
  Require(result.success && result.history.size() == 2, "Safari original per-visit rows");
  Require(result.history[0].last_visit == 12622780800250000LL, "Safari fractional Cocoa epoch");
  Require(result.history[1].last_visit == 12622780801500000LL, "Safari visit time precision");
  Require(result.history[0].visits == 3 && result.history[0].typed == 0, "Safari visit count");
  Require(!result.warnings.empty(), "Safari invalid history warning");
  Require(Bytes(history) == original, "Safari original database unchanged");
  Require(!base::PathExists(base::FilePath(history.value()+"-shm")), "Safari no original SHM");
  Require(!ReadSafariCategory(options, kCookies, cancel).success, "Safari cookie capability refused");
  Require(!ReadSafariCategory(options, kPasswords, cancel).success, "Safari direct passwords refused");
  options.profile_path = base::FilePath("relative");
  Require(!ReadSafariCategory(options, kHistory, cancel).success, "Safari relative path rejected");
  options.profile_path = path;
  options.family = Family::kFirefox;
  Require(!ReadSafariCategory(options, kHistory, cancel).success, "Safari exact family binding");
}
void Firefox(const base::FilePath& path) {
  using namespace parc::importer;
  ReadOptions options; options.family = Family::kFirefox; options.profile_path = path;
  auto cancel = std::make_shared<std::atomic_bool>(false);
  const auto places = path.AppendASCII("places.sqlite");
  sqlite3* db = Database(places);
  SQL(db, "CREATE TABLE moz_places(id INTEGER PRIMARY KEY,url TEXT,title TEXT,visit_count INTEGER,hidden INTEGER,typed INTEGER);"
          "CREATE TABLE moz_historyvisits(place_id INTEGER,visit_type INTEGER,visit_date INTEGER);"
          "CREATE TABLE moz_bookmarks(id INTEGER PRIMARY KEY,parent INTEGER,position INTEGER,type INTEGER,guid TEXT,title TEXT,fk INTEGER);"
          "CREATE TABLE moz_items_annos(item_id INTEGER,anno_attribute_id INTEGER);"
          "CREATE TABLE moz_anno_attributes(id INTEGER,name TEXT);"
          "INSERT INTO moz_places VALUES(1,'https://example.test/','Café',4,1,2),(2,'place:folder=1','Query',1,0,0);"
          "INSERT INTO moz_historyvisits VALUES(1,1,1234567),(1,2,2345678),(1,4,3456789),(2,1,0);"
          "INSERT INTO moz_bookmarks VALUES"
          "(1,0,0,2,'root________','Root',NULL),"
          "(2,1,0,2,'toolbar_____','Toolbar',NULL),(3,1,1,2,'menu________','Menu',NULL),"
          "(4,1,2,2,'unfiled_____','Other',NULL),"
          "(10,2,0,2,'folder______','Nested',NULL),(11,10,0,1,'bookmark____','One',1),"
          "(12,3,0,1,'menubookmark','Menu Link',1),(13,4,0,2,'empty_______','Empty',NULL),"
          "(14,3,1,1,'post________','POST',1),(15,3,2,2,'live________','Live',NULL),"
          "(16,15,0,1,'livechild___','Live Child',1),(17,3,3,1,'query_______','Query',2),"
          "(18,3,4,3,'separator___','',NULL);"
          "INSERT INTO moz_anno_attributes VALUES(1,'bookmarkProperties/POSTData'),(2,'livemark/feedURI');"
          "INSERT INTO moz_items_annos VALUES(14,1),(15,2);");
  sqlite3_close(db);
  const auto original = Bytes(places);
  auto history = ReadFirefoxCategory(options, kHistory, cancel);
  Require(history.success && history.history.size() == 2, "Firefox real history transition and URL filtering");
  Require(history.history[0].last_visit == 11644473601234567LL, "Firefox Unix microsecond precision");
  Require(history.history[0].hidden && history.history[0].typed == 2 && history.history[0].visits == 4, "Firefox hidden/typed/count provenance");
  auto bookmarks = ReadFirefoxCategory(options, kBookmarks, cancel);
  Require(bookmarks.success && bookmarks.bookmarks.size() == 6, "Firefox roots, nesting, empty folders and annotation exclusions");
  Require(bookmarks.bookmarks[2].parent == "firefox:10", "Firefox original child parent");
  Require(bookmarks.bookmarks[3].id == "firefox:12" && bookmarks.bookmarks[3].parent.empty(), "Firefox menu flatten");
  Require(bookmarks.bookmarks.back().folder && bookmarks.bookmarks.back().title == u"Empty", "Firefox empty folder retained");
  Require(bookmarks.warnings.size() == 3, "Firefox excluded annotation/URL/separator warnings");
  Require(Bytes(places) == original, "Firefox original database unchanged");
  Require(!base::PathExists(base::FilePath(places.value()+"-shm")), "Firefox no original SHM");
  db = Database(places);
  SQL(db, "UPDATE moz_bookmarks SET parent=10 WHERE id=2;"); sqlite3_close(db);
  auto cycle = ReadFirefoxCategory(options, kBookmarks, cancel);
  Require(!cycle.success && cycle.bookmarks.empty(), "Firefox reachable cycle publishes no partial category");
  db = Database(places);
  SQL(db, "UPDATE moz_bookmarks SET parent=1 WHERE id=2; DROP TABLE moz_anno_attributes;"); sqlite3_close(db);
  Require(!ReadFirefoxCategory(options, kBookmarks, cancel).success, "Firefox incomplete POST annotation protection refuses");
  db = Database(places); SQL(db, "DROP TABLE moz_items_annos;"); sqlite3_close(db);
  Require(ReadFirefoxCategory(options, kBookmarks, cancel).success, "Firefox modern no-annotation schema accepted");
  const auto forms = path.AppendASCII("formhistory.sqlite");
  db = Database(forms);
  SQL(db, "CREATE TABLE moz_formhistory(fieldname TEXT,value TEXT,timesUsed INTEGER,firstUsed INTEGER,lastUsed INTEGER);"
          "INSERT INTO moz_formhistory VALUES('email','fixture@example.test',3,1234567,2345678),"
          "('searchbar-history','not imported',2,1,2),('bad','bad',-1,1,2);");
  sqlite3_close(db);
  auto form = ReadFirefoxCategory(options, kAutofill, cancel);
  Require(form.success && form.autofill.size() == 1, "Firefox form data excludes searchbar and malformed counts");
  Require(form.autofill[0].fields.at("name") == u"email" && form.autofill[0].kind == Autofill::Kind::kForm, "Firefox real form field carrier");
  Require(form.autofill[0].created == 11644473601234567LL && form.autofill[0].use_count == 3, "Firefox form time and count");
  cancel->store(true);
  Require(!ReadFirefoxCategory(options, kHistory, cancel).success, "Firefox cancellation");
  cancel->store(false);
  Require(!ReadFirefoxCategory(options, kPasswords, cancel).success, "Firefox macOS NSS/password restriction");
  Require(!ReadFirefoxCategory(options, kCookies, cancel).success, "Firefox cookies not invented");
  db = Database(places); SQL(db, "DROP TABLE moz_historyvisits;"); sqlite3_close(db);
  auto malformed = ReadFirefoxCategory(options, kHistory, cancel);
  Require(!malformed.success && malformed.history.empty(), "Firefox schema failure does not publish history");
  Require(malformed.error == "Firefox history has an unsupported database schema.",
          "An unnamed Firefox-family source is described as Firefox");
  options.source_name = "Zen";
  auto zen = ReadFirefoxCategory(options, kHistory, cancel);
  Require(!zen.success && zen.error == "Zen history has an unsupported database schema.",
          "A damaged Zen profile is described as Zen, not Firefox");
  options.source_name.clear();
  options.profile_path = base::FilePath("relative");
  Require(!ReadFirefoxCategory(options, kHistory, cancel).success, "Firefox relative path rejected");
  options.profile_path = path.AppendASCII("missing");
  Require(!ReadFirefoxCategory(options, kHistory, cancel).success, "Missing source does not become empty success");
}
void SafariExport(const base::FilePath& path) {
  using namespace parc::importer;
  ReadOptions options; options.family = Family::kSafari; options.profile_path = path;
  auto cancel = std::make_shared<std::atomic_bool>(false);
  const auto file = path.AppendASCII("History.json");
  const std::string json = R"({
    "metadata" : {"browser_name" : "Safari", "browser_version" : "18.4", "data_type" : "history",
                  "export_time_usec" : 1751296375693668, "schema_version" : 1},
    "history" : [
      {"url" : "http://redirect.example.test/", "time_usec" : 1751296375691025, "visit_count" : 2,
       "destination_url" : "https://redirect.example.test/", "destination_time_usec" : 1751296375691668},
      {"url" : "https://redirect.example.test/", "time_usec" : 1751296375691668, "visit_count" : 4,
       "title" : "Caf\u00e9 fixture", "source_url" : "http://redirect.example.test/",
       "source_time_usec" : 1751296375691025},
      {"url" : "https://documented.example.test/", "time_usec" : 1722367302951310, "visits_count" : 7},
      {"url" : "not a url", "time_usec" : 1722367302951310, "visit_count" : 1},
      {"url" : "https://untimed.example.test/", "visit_count" : 1}
    ]
  })";
  Require(base::WriteFile(file, json), "write exported Safari history");
  auto result = ReadSafariCategory(options, kHistory, cancel);
  Require(result.success && result.history.size() == 3, "Exported Safari history keeps its valid entries");
  Require(result.history[0].hidden && !result.history[1].hidden, "Redirect sources are hidden and their targets are not");
  Require(result.history[0].visits == 2 && result.history[1].visits == 4 && result.history[2].visits == 7,
          "Visit counts come from either the visit_count or the documented visits_count key");
  Require(result.history[1].title == u"Caf\u00e9 fixture" && result.history[0].title.empty(), "Titles are optional and decoded");
  Require(result.history[0].last_visit == 1751296375691025LL + 11644473600000000LL &&
          result.history[1].last_visit == 1751296375691668LL + 11644473600000000LL,
          "Unix microseconds become Chromium's 1601-based microseconds exactly, odd values included");
  Require(result.warnings.size() == 1, "Invalid exported entries are skipped with one warning");
  Require(Bytes(file) == json, "The exported history file is left unchanged");
  cancel->store(true);
  Require(!ReadSafariCategory(options, kHistory, cancel).success, "Exported history honours cancellation");
  cancel->store(false);
  Require(base::WriteFile(file, R"({"metadata":{"data_type":"payment_cards"},"payment_cards":[]})"),
          "write a non-history export file");
  Require(!ReadSafariCategory(options, kHistory, cancel).success, "Only a history export is read as history");
  Require(base::WriteFile(file, "{ not json"), "write malformed export");
  Require(!ReadSafariCategory(options, kHistory, cancel).success, "Malformed exported history is refused");
  Require(base::WriteFile(file, json), "restore a valid exported history");
  Require(ReadSafariCategory(options, kHistory, cancel).success, "The restored export reads again");
  Require(base::WriteFile(path.AppendASCII("History.db"), "not sqlite"), "add a Safari database beside it");
  Require(!ReadSafariCategory(options, kHistory, cancel).success,
          "A real Safari History.db always wins over an exported History.json");
}
void WAL(const base::FilePath& path) {
  using namespace parc::importer;
  const auto file = path.AppendASCII("History.db");
  sqlite3* db = Database(file);
  SQL(db, "PRAGMA journal_mode=WAL; PRAGMA wal_autocheckpoint=0;"
          "CREATE TABLE history_items(id INTEGER,url TEXT,visit_count INTEGER);"
          "CREATE TABLE history_visits(history_item INTEGER,title TEXT,visit_time REAL);"
          "INSERT INTO history_items VALUES(1,'https://wal.example.test/',1);"
          "INSERT INTO history_visits VALUES(1,'WAL',1);");
  const auto wal = base::FilePath(file.value()+"-wal");
  const auto original = Bytes(file), original_wal = Bytes(wal);
  ReadOptions options; options.family = Family::kSafari; options.profile_path = path;
  auto result = ReadSafariCategory(options, kHistory, std::make_shared<std::atomic_bool>(false));
  Require(result.success && result.history.size() == 1, "Private snapshot includes uncheckpointed WAL");
  Require(Bytes(file) == original && Bytes(wal) == original_wal, "Snapshot leaves original DB/WAL unchanged");
  sqlite3_close(db);
}
}
int main() {
  @autoreleasepool {
    std::fprintf(stderr, "fixture: start\n");
    base::ScopedTempDir temporary;
    Require(temporary.CreateUniqueTempDir(), "create disposable fixture root");
    for (const char* name : {"Safari", "SafariExport", "Firefox", "WAL"})
      Require(base::CreateDirectory(temporary.GetPath().AppendASCII(name)), "create fixture source");
    std::fprintf(stderr, "fixture: Safari\n");
    Safari(temporary.GetPath().AppendASCII("Safari"));
    std::fprintf(stderr, "fixture: SafariExport\n");
    SafariExport(temporary.GetPath().AppendASCII("SafariExport"));
    std::fprintf(stderr, "fixture: Firefox\n");
    Firefox(temporary.GetPath().AppendASCII("Firefox"));
    std::fprintf(stderr, "fixture: WAL\n");
    WAL(temporary.GetPath().AppendASCII("WAL"));
    std::printf("Safari/Firefox readers: %d checks passed\n", checks);
  }
}
