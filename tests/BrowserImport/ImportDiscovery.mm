#include "../Support/TestFailure.h"
#include <cstdio>
#include <cstdlib>
#import "../../Engine/ParcNative/native_import_discovery.mm"
#include "base/files/scoped_temp_dir.h"
#include "sql/initialization.h"
#include "third_party/sqlite/sqlite3.h"

namespace {
using parc::importer::Installation;
using parc::importer::ProfileData;
int checks = 0;
void Require(bool condition, const char* message) {
  ++checks;
  if (!condition) {
    std::fprintf(stderr, "FAILED: %s\n", message);
    std::exit(1);
  }
}
void Write(const base::FilePath& path, std::string_view contents = "{}") {
  Require(base::CreateDirectory(path.DirName()), "create fixture folder");
  Require(base::WriteFile(path, contents), "write fixture file");
}
base::FilePath Real(const base::FilePath& path) {
  return base::MakeAbsoluteFilePath(path);
}
std::shared_ptr<const Installation> Source(const char* bundle,
                                           const char* name,
                                           const char* folder) {
  return std::make_shared<const Installation>(
      Installation{0,
                   bundle,
                   name,
                   std::string("Library/Application Support/") + folder,
                   std::string(name) + " Safe Storage",
                   name,
                   {}});
}
const ProfileData* Named(const parc::importer::ProfilesResult& result,
                         std::string_view name) {
  for (const auto& profile : result.profiles) {
    if (profile->name == name)
      return profile.get();
  }
  return nullptr;
}
void OperaGXAtRoot(const base::FilePath& home) {
  const auto source = Source("com.operasoftware.OperaGX", "Opera GX",
                             "com.operasoftware.OperaGX");
  const auto root = home.Append(source->root_relative);
  const auto side = root.AppendASCII("_side_profiles");
  Write(root.AppendASCII("Preferences"));
  Write(root.AppendASCII("History"), "");
  Write(side.AppendASCII("3130_A/Preferences"));
  Write(side.AppendASCII("3130_A/History"), "");
  Write(side.AppendASCII("3130_A/Bookmarks"));
  Write(side.AppendASCII("3130_A/3130_A_sideprofile.json"),
        R"({"name": "Work", "color": 4280391411, "features": []})");
  Write(side.AppendASCII("3130_A/0000_sideprofile.json"),
        R"({"name": "Stray", "features": ["side-profile-clear-on-exit"]})");
  Write(side.AppendASCII("3130_B/Preferences"));
  Write(side.AppendASCII("3130_B/Default/Preferences"));
  Write(side.AppendASCII("3130_B/Default/Login Data"), "");
  Write(side.AppendASCII("3130_B/3130_B_sideprofile.json"),
        R"({"name": "Streaming", "features": ["side-profile-muted"]})");
  Write(side.AppendASCII("3130_C/Preferences"));
  Write(side.AppendASCII("3130_C/History"), "");
  Write(side.AppendASCII("3130_C/3130_C_sideprofile.json"),
        R"({"name": "Rogue", "features": ["side-profile-clear-on-exit"]})");
  Write(side.AppendASCII("3130_D/Preferences"));
  Write(side.AppendASCII("3130_D/History"), "");
  Write(side.AppendASCII("3130_E/On the side.ico"), "");
  Write(side.AppendASCII("3130_F/Preferences"));
  Write(side.AppendASCII("3130_F/Web Data"), "");
  Write(side.AppendASCII("3130_F/3130_F_sideprofile.json"), R"({"name": ""})");
  Write(side.AppendASCII("notes.txt"), "");

  const auto result = parc::importer::Load(source, home, false);
  Require(result.profiles.size() == 5,
          "Opera GX lists its root profile and each kept side profile");
  const auto& first = *result.profiles[0];
  Require(first.path == Real(root) && first.name == "Opera GX" &&
              first.directory == "com.operasoftware.OperaGX",
          "the root profile stays first under the browser's name");
  Require(result.profiles[1]->name == "Work" &&
              result.profiles[2]->name == "Streaming" &&
              result.profiles[3]->name == "Opera GX 4" &&
              result.profiles[4]->name == "Opera GX 5",
          "side profiles follow the root profile in folder order");
  const auto* work = Named(result, "Work");
  Require(work && work->path == Real(side.AppendASCII("3130_A")) &&
              work->directory == "3130_A",
          "a side profile kept in its own folder takes the name from the "
          "settings file named after that folder, not a stray copy");
  Require(work && (work->categories & PCNativeImportCategoryHistory) &&
              (work->categories & PCNativeImportCategoryBookmarks),
          "a side profile offers the data it holds");
  const auto* streaming = Named(result, "Streaming");
  Require(streaming &&
              streaming->path == Real(side.AppendASCII("3130_B/Default")) &&
              streaming->directory == "3130_B",
          "a side profile's Default folder wins when both hold Preferences, "
          "under the side folder's own name");
  Require(
      streaming && (streaming->categories & PCNativeImportCategoryPasswords),
      "side-profile passwords use the browser's Keychain key");
  Require(!Named(result, "Rogue"),
          "a side profile Opera clears on exit is not offered");
  const auto* unnamed = Named(result, "Opera GX 4");
  Require(unnamed && unnamed->directory == "3130_D",
          "a side profile without a settings file is numbered after the "
          "profiles before it");
  const auto* blank = Named(result, "Opera GX 5");
  Require(blank && blank->directory == "3130_F" &&
              (blank->categories & PCNativeImportCategoryAutofill),
          "a side profile with an empty name is numbered too");
  for (const auto& profile : result.profiles)
    Require(profile->source == source,
            "every side profile shares the browser's one Keychain key slot");
}
void OperaWithDefault(const base::FilePath& home) {
  const auto source =
      Source("com.operasoftware.Opera", "Opera", "com.operasoftware.Opera");
  const auto root = home.Append(source->root_relative);
  Write(root.AppendASCII("Local State"),
        R"({"profile": {"info_cache": {"Default": {"name": "Personal"}}}})");
  Write(root.AppendASCII("Default/Preferences"));
  Write(root.AppendASCII("Default/History"), "");
  Write(root.AppendASCII("_side_profiles/31303232/Default/Preferences"));
  Write(root.AppendASCII("_side_profiles/31303232/Default/History"), "");
  Write(root.AppendASCII("_side_profiles/31303232/31303232_sideprofile.json"),
        R"({"name": "Personal"})");

  const auto result = parc::importer::Load(source, home, false);
  Require(result.profiles.size() == 2,
          "Opera lists its Default and side profile");
  Require(result.profiles[0]->path == Real(root.AppendASCII("Default")) &&
              result.profiles[0]->directory == "Default",
          "Opera's own Default profile comes first");
  Require(result.profiles[1]->directory == "31303232" &&
              result.profiles[1]->name == "Personal",
          "a side profile never claims the Default folder name, even when it "
          "shares the main profile's name");
}
void SideProfileOnly(const base::FilePath& home) {
  const auto source = Source("com.operasoftware.OperaGX", "Opera GX",
                             "com.operasoftware.OperaGX");
  const auto side =
      home.Append(source->root_relative).AppendASCII("_side_profiles/77");
  Write(side.AppendASCII("Preferences"));
  Write(side.AppendASCII("History"), "");
  Write(side.AppendASCII("77_sideprofile.json"), R"({"name": "Travel"})");

  const auto listed = parc::importer::Load(source, home, true);
  Require(listed.profiles.size() == 1 && listed.profiles[0]->name == "Travel",
          "a side profile is listed even when the root holds no profile");
  Installation copy = *source;
  copy.app_path = home.AppendASCII("Opera GX.app");
  const auto importable = parc::importer::Importable({copy}, home);
  Require(importable.size() == 1,
          "Opera GX is offered when only a side profile holds data");
}
void ChromeIgnoresSideFolder(const base::FilePath& home) {
  const auto source = Source("com.google.Chrome", "Chrome", "Google/Chrome");
  const auto root = home.Append(source->root_relative);
  Write(root.AppendASCII("Default/Preferences"));
  Write(root.AppendASCII("Default/History"), "");
  Write(root.AppendASCII("_side_profiles/9/Preferences"));
  Write(root.AppendASCII("_side_profiles/9/History"), "");

  const auto result = parc::importer::Load(source, home, false);
  Require(
      result.profiles.size() == 1 && result.profiles[0]->directory == "Default",
      "only Opera and Opera GX read side profiles");
}
void FirefoxProfileGroups(const base::FilePath& home) {
  const auto source = std::make_shared<const Installation>(
      Installation{2, "org.mozilla.firefox", "Firefox",
                   "Library/Application Support/Firefox", {}, {}, {}});
  const auto root = home.Append(source->root_relative);
  Write(root.AppendASCII("profiles.ini"),
        "[Profile1]\nName=default\nIsRelative=1\nPath=Profiles/old.default\n\n"
        "[Profile0]\nName=default-release\nIsRelative=1\n"
        "Path=Profiles/abc.default-release\nStoreID=a1b2c3d4\n\n"
        "[Profile2]\nName=evil\nIsRelative=1\nPath=Profiles/evil\n"
        "StoreID=../escape\n\n"
        "[Install4F96D1932A9F858E]\nDefault=Profiles/abc.default-release\n");
  for (const char* folder : {"Profiles/old.default", "Profiles/abc.default-release",
                             "Profiles/evil", "Profiles/work.Work",
                             "Profiles/nameless"})
    Write(root.AppendASCII(folder).AppendASCII("places.sqlite"), "");
  Require(base::CreateDirectory(root.AppendASCII("Profile Groups")),
          "create the profile group folder");
  sql::EnsureSqliteInitialized(false);
  sqlite3* db = nullptr;
  Require(sqlite3_open(root.AppendASCII("Profile Groups/a1b2c3d4.sqlite")
                           .value().c_str(), &db) == SQLITE_OK,
          "create the profile group database");
  Require(sqlite3_exec(db,
              "CREATE TABLE Profiles(id INTEGER PRIMARY KEY, path TEXT UNIQUE, "
              "name TEXT, avatar TEXT, themeId TEXT, themeFg TEXT, themeBg TEXT);"
              "INSERT INTO Profiles(id, path, name) VALUES"
              "(1, 'Profiles/abc.default-release', 'Personal'),"
              "(2, 'Profiles/work.Work', 'Work'),"
              "(3, 'Profiles/nameless', ''),"
              "(4, 'Profiles/deleted', 'Deleted');",
              nullptr, nullptr, nullptr) == SQLITE_OK,
          "fill the profile group database");
  sqlite3_close(db);

  const auto result = parc::importer::Load(source, home, false);
  Require(result.profiles.size() == 5,
          "Firefox lists its profiles.ini profiles and the group's other "
          "profiles once each");
  Require(result.profiles[0]->name == "default" &&
              result.profiles[1]->name == "Personal" &&
              result.profiles[1]->path ==
                  Real(root.AppendASCII("Profiles/abc.default-release")),
          "the group's real name replaces the internal profiles.ini name "
          "instead of listing the profile twice");
  Require(result.profiles[2]->name == "evil",
          "a StoreID that is not a plain identifier is never followed");
  Require(result.profiles[3]->name == "Work" &&
              result.profiles[3]->path ==
                  Real(root.AppendASCII("Profiles/work.Work")) &&
              (result.profiles[3]->categories & PCNativeImportCategoryBookmarks),
          "a profile that exists only in the group is offered with its data");
  Require(result.profiles[4]->name == "nameless",
          "a group profile without a name falls back to its folder");
  Require(!Named(result, "Deleted"),
          "a group profile whose folder is gone is not offered");
  for (const auto& profile : result.profiles)
    Require(profile->source == source,
            "group profiles belong to the same Firefox source");
  const auto listed = parc::importer::Load(source, home, true);
  Require(listed.profiles.size() == 5,
          "the source list sees the same group profiles");
}
}

int main() {
  ParcExitOnUncaughtExceptions();
  @autoreleasepool {
    base::ScopedTempDir temporary;
    Require(temporary.CreateUniqueTempDir(), "create disposable fixture root");
    int index = 0;
    for (auto check : {OperaGXAtRoot, OperaWithDefault, SideProfileOnly,
                       ChromeIgnoresSideFolder, FirefoxProfileGroups}) {
      const auto home = temporary.GetPath().AppendASCII(
          "home" + base::NumberToString(++index));
      Require(base::CreateDirectory(home), "create fixture home");
      check(home);
    }
    std::printf("Import discovery: %d checks passed\n", checks);
  }
}
