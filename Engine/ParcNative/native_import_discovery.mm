// Copyright 2026 Parc contributors.
#include <sys/stat.h>
#include <unistd.h>
#include <algorithm>
#include <cerrno>
#include <map>
#include "base/files/file_util.h"
#include "base/functional/bind.h"
#include "base/json/json_reader.h"
#include "base/strings/string_number_conversions.h"
#include "base/strings/string_split.h"
#include "base/strings/string_util.h"
#include "base/strings/sys_string_conversions.h"
#include "base/task/thread_pool.h"
#include "base/uuid.h"
#import "native_import_internal.h"
#include "parc/importer/import_reader.h"
namespace parc::importer {
NSError* ImportError(NSString* message) {
  return [NSError errorWithDomain:@"ParcBrowserImport"
                             code:1
                         userInfo:@{NSLocalizedDescriptionKey : message}];
}
bool SourceReady(const ProfileData& profile, std::string& error) {
  const auto& source = *profile.source;
  NSBundle* bundle = [NSBundle
      bundleWithPath:base::SysUTF8ToNSString(source.app_path.value())];
  struct stat directory{};
  const bool bundled = source.app_path.MatchesExtension(".app");
  if ((bundled && ![bundle.bundleIdentifier
                       isEqualToString:base::SysUTF8ToNSString(source.bundle_id)]) ||
      stat(profile.path.value().c_str(), &directory) != 0 ||
      !S_ISDIR(directory.st_mode) ||
      static_cast<uint64_t>(directory.st_dev) != profile.device ||
      static_cast<uint64_t>(directory.st_ino) != profile.inode) {
    error = "The selected browser or profile changed. Choose the source again.";
    return false;
  }
  return true;
}
namespace {
constexpr char kArcBundleID[] = "company.thebrowser.Browser";
constexpr char kArcData[] = "Library/Application Support/Arc";
bool ArcDataExists(const base::FilePath& home) {
  struct stat info{};
  const auto sidebar =
      home.Append(kArcData).AppendASCII("StorableSidebar.json");
  return stat(sidebar.value().c_str(), &info) == 0 || errno == EPERM ||
         errno == EACCES;
}
std::optional<base::DictValue> JSON(const base::FilePath& path) {
  std::string data;
  if (!base::ReadFileToStringWithMaxSize(path, &data, 64 * 1024 * 1024))
    return std::nullopt;
  return base::JSONReader::ReadDict(data, base::JSON_PARSE_CHROMIUM_EXTENSIONS);
}
struct ProfilesResult {
  std::vector<std::shared_ptr<ProfileData>> profiles;
  bool restricted = false;
  std::vector<std::string> constraints;
};
bool Readable(const base::FilePath& file, bool* restricted) {
  if (access(file.value().c_str(), R_OK) == 0)
    return true;
  if (errno == EACCES || errno == EPERM)
    *restricted = true;
  return false;
}
bool HasProfilePath(const ProfilesResult& result, const base::FilePath& path) {
  for (const auto& profile : result.profiles) {
    if (profile->path == path)
      return true;
  }
  return false;
}
void AddProfile(ProfilesResult& result,
                const std::shared_ptr<const Installation>& source,
                const base::FilePath& path,
                std::string name,
                bool listing) {
  struct stat directory{};
  base::FilePath normalized = base::MakeAbsoluteFilePath(path);
  if (normalized.empty())
    normalized = path;
  if (stat(normalized.value().c_str(), &directory) != 0 ||
      !S_ISDIR(directory.st_mode)) {
    if (errno == EACCES || errno == EPERM)
      result.restricted = true;
    return;
  }
  if (HasProfilePath(result, normalized))
    return;
  auto p = std::make_shared<ProfileData>();
  p->device = directory.st_dev;
  p->inode = directory.st_ino;
  p->source = source;
  p->path = normalized;
  p->name = std::move(name);
  p->identifier = base::Uuid::GenerateRandomV4().AsLowercaseString();
  auto can = [&](const char* relative) {
    return Readable(normalized.AppendASCII(relative), &p->restricted);
  };
  if (source->family == 0) {
    if (can("History"))
      p->categories |= PCNativeImportCategoryHistory;
    for (const auto& files :
         {kChromiumLocalBookmarks, kChromiumAccountBookmarks}) {
      if (can(files.plain) || can(files.encrypted))
        p->categories |= PCNativeImportCategoryBookmarks;
    }
    if (can("Network/Cookies") || can("Cookies"))
      p->categories |= PCNativeImportCategoryCookies;
    if (can(kChromiumLogins) || can(kChromiumAccountLogins))
      p->categories |= PCNativeImportCategoryPasswords;
    if (can("Web Data"))
      p->categories |= PCNativeImportCategoryAutofill;
    std::optional<base::DictValue> prefs;
    if (!listing || p->categories == 0) {
      prefs = JSON(normalized.AppendASCII("Secure Preferences"));
      if (!prefs)
        prefs = JSON(normalized.AppendASCII("Preferences"));
    }
    const auto* extensions =
        prefs ? prefs->FindDictByDottedPath("extensions.settings") : nullptr;
    if (extensions)
      for (const auto [id, value] : *extensions) {
        if (id.size() != 32 ||
            id.find_first_not_of("abcdefghijklmnop") != std::string::npos ||
            !value.is_dict())
          continue;
        const auto& entry = value.GetDict();
        const auto* manifest = entry.FindDict("manifest");
        if (!manifest || !entry.FindBool("from_webstore").value_or(false) ||
            entry.FindBool("was_installed_by_default").value_or(false))
          continue;
        const auto* title = manifest->FindString("name");
        p->extensions.emplace_back(id, title ? *title : id);
      }
    if (!p->extensions.empty())
      p->categories |= PCNativeImportCategoryExtensions;
    p->constraints.push_back(
        "Encrypted bookmarks, cookies, passwords and local payment data may "
        "require macOS Keychain authorization. Unsupported encryption is "
        "reported without importing those records.");
  } else if (source->family == 1) {
    if (can("History.db") || can("History.json"))
      p->categories |= PCNativeImportCategoryHistory;
    if (can("Bookmarks.plist"))
      p->categories |= PCNativeImportCategoryBookmarks;
    p->constraints.push_back(
        "Safari directly imports accessible history and bookmarks. Passwords "
        "require an explicit export from Passwords/Safari; cookies, payment "
        "data and Safari extensions are not imported by this source.");
  } else {
    if (can("places.sqlite"))
      p->categories |=
          PCNativeImportCategoryHistory | PCNativeImportCategoryBookmarks;
    if (can("formhistory.sqlite"))
      p->categories |= PCNativeImportCategoryAutofill;
    p->constraints.push_back(
        source->name + " passwords require an explicit password export. Parc "
        "does not load " + source->name + "'s external NSS libraries into "
        "its signed application. " + source->name + " add-ons and encrypted "
        "payment records are not imported.");
  }
  if (p->restricted)
    p->constraints.push_back(
        "macOS has restricted access to some source files. Grant the required "
        "file access in System Settings and reload this source to retry.");
  result.restricted |= p->restricted;
  result.profiles.push_back(std::move(p));
}
ProfilesResult Load(std::shared_ptr<const Installation> source,
                    base::FilePath home,
                    bool listing) {
  ProfilesResult result;
  const auto root = home.Append(base::FilePath(source->root_relative));
  if (source->family == 0) {
    auto state = JSON(root.AppendASCII("Local State"));
    const auto* cache =
        state ? state->FindDictByDottedPath("profile.info_cache") : nullptr;
    if (cache)
      for (const auto [directory, value] : *cache) {
        if (directory.empty() || directory == "." || directory == ".." ||
            directory.find('/') != std::string::npos || !value.is_dict())
          continue;
        const auto* name = value.GetDict().FindString("name");
        AddProfile(result, source, root.AppendASCII(directory),
                   name ? *name : directory, listing);
      }
    const char* known[] = {
        "Default", "Profile 1", "Profile 2", "Profile 3", "Profile 4", "Profile 5"};
    for (const char* directory : known)
      AddProfile(result, source, root.AppendASCII(directory), directory,
                 listing);
    if (result.profiles.empty() &&
        source->bundle_id == "com.operasoftware.Opera" &&
        base::PathExists(root.AppendASCII("Preferences")))
      AddProfile(result, source, root, "Opera", listing);
    auto blocked = [](const base::FilePath& path) {
      return access(path.value().c_str(), R_OK) != 0 &&
             (errno == EACCES || errno == EPERM);
    };
    if (blocked(root) || blocked(root.AppendASCII("Local State")))
      result.restricted = true;
    if (source->bundle_id == kArcBundleID &&
        blocked(root.DirName().AppendASCII("StorableSidebar.json")))
      result.restricted = true;
  } else if (source->family == 1) {
    AddProfile(result, source, root, "Safari", listing);
    result.constraints.push_back(
        "Safari imports the original default history/bookmark store. Separate "
        "newer Safari profile stores are not advertised by this importer.");
  } else {
    std::string ini;
    const auto ini_path = root.AppendASCII("profiles.ini");
    if (!base::ReadFileToStringWithMaxSize(ini_path, &ini, 1024 * 1024)) {
      result.restricted = base::PathExists(ini_path);
      return result;
    }
    std::map<std::string, std::string> section;
    auto flush = [&] {
      if (!section.contains("Path"))
        return;
      base::FilePath path(section["Path"]);
      if (section["IsRelative"] != "0")
        path = root.Append(path);
      AddProfile(
          result, source, path,
          section.contains("Name") ? section["Name"] : path.BaseName().value(),
          listing);
    };
    bool profile = false;
    for (auto line : base::SplitStringPiece(ini, "\n", base::TRIM_WHITESPACE,
                                            base::SPLIT_WANT_NONEMPTY)) {
      if (line.front() == '[') {
        if (profile)
          flush();
        section.clear();
        profile = line.starts_with("[Profile");
        continue;
      }
      if (!profile || line.front() == ';' || line.front() == '#')
        continue;
      const auto separator = line.find('=');
      if (separator == std::string_view::npos)
        continue;
      section[std::string(line.substr(0, separator))] =
          std::string(line.substr(separator + 1));
    }
    if (profile)
      flush();
  }
  if (result.restricted)
    result.constraints.push_back(
        "macOS has restricted access to this browser’s files. Grant Full Disk "
        "Access in System Settings, then return here.");
  if (result.profiles.empty())
    result.constraints.push_back(
        "No accessible source profiles were found. Check that this browser has "
        "a profile and that macOS permits access.");
  return result;
}
std::vector<Installation> Importable(std::vector<Installation> installed,
                                     base::FilePath home) {
  std::vector<Installation> importable;
  for (auto& source : installed) {
    if (source.family != 1) {
      const auto profiles =
          Load(std::make_shared<const Installation>(source), home, true);
      if (!profiles.restricted &&
          std::none_of(profiles.profiles.begin(), profiles.profiles.end(),
                       [](const auto& profile) {
                         return profile->categories != 0 ||
                                profile->restricted;
                       }))
        continue;
    }
    importable.push_back(std::move(source));
  }
  return importable;
}
}
}

@implementation PCNativeImportSource {
  std::shared_ptr<const parc::importer::Installation> _installation;
}
@synthesize identifier = _identifier, displayName = _displayName,
            appURL = _appURL;
- (instancetype)initWithInstallation:
    (std::shared_ptr<const parc::importer::Installation>)source {
  if ((self = [super init])) {
    _installation = std::move(source);
    _identifier = base::SysUTF8ToNSString(_installation->bundle_id);
    _displayName = base::SysUTF8ToNSString(_installation->name);
    _appURL = [NSURL
        fileURLWithPath:base::SysUTF8ToNSString(_installation->app_path.value())
            isDirectory:YES];
  }
  return self;
}
- (std::shared_ptr<const parc::importer::Installation>)installation {
  return _installation;
}
@end
@interface PCNativeImportExtension ()
- (instancetype)initWithIdentifier:(NSString*)identifier name:(NSString*)name;
@end
@implementation PCNativeImportExtension
@synthesize identifier = _identifier, displayName = _displayName;
- (instancetype)initWithIdentifier:(NSString*)identifier name:(NSString*)name {
  if ((self = [super init])) {
    _identifier = [identifier copy];
    _displayName = [name copy];
  }
  return self;
}
@end
@implementation PCNativeImportProfile {
  std::shared_ptr<const parc::importer::ProfileData> _data;
}
@synthesize identifier = _identifier, source = _source,
            displayName = _displayName, directoryName = _directoryName,
            supportedCategories = _supportedCategories,
            extensions = _extensions, access = _access,
            constraints = _constraints;
- (instancetype)initWithData:
                    (std::shared_ptr<const parc::importer::ProfileData>)data
                      source:(PCNativeImportSource*)source {
  if ((self = [super init])) {
    _data = std::move(data);
    _source = source;
    _identifier = base::SysUTF8ToNSString(_data->identifier);
    _displayName = base::SysUTF8ToNSString(_data->name);
    _directoryName = base::SysUTF8ToNSString(_data->path.BaseName().value());
    _supportedCategories =
        static_cast<PCNativeImportCategories>(_data->categories);
    _access = _data->restricted ? PCNativeImportAccessRestricted
                                : PCNativeImportAccessComplete;
    NSMutableArray* notes = [NSMutableArray array];
    for (const auto& x : _data->constraints)
      [notes addObject:base::SysUTF8ToNSString(x)];
    _constraints = [notes copy];
    NSMutableArray* extensions = [NSMutableArray array];
    for (const auto& [id, name] : _data->extensions)
      [extensions
          addObject:[[PCNativeImportExtension alloc]
                        initWithIdentifier:base::SysUTF8ToNSString(id)
                                      name:base::SysUTF8ToNSString(name)]];
    _extensions = [extensions copy];
  }
  return self;
}
- (std::shared_ptr<const parc::importer::ProfileData>)profileData {
  return _data;
}
@end
@implementation PCNativeImportProfileResult
@synthesize profiles = _profiles, access = _access, constraints = _constraints,
            error = _error;
- (instancetype)initWithProfiles:(NSArray<PCNativeImportProfile*>*)profiles
                      restricted:(BOOL)restricted
                     constraints:(NSArray<NSString*>*)constraints
                           error:(NSError*)error {
  if ((self = [super init])) {
    _profiles = [profiles copy];
    _access = restricted ? PCNativeImportAccessRestricted
                         : PCNativeImportAccessComplete;
    _constraints = [constraints copy];
    _error = error;
  }
  return self;
}
@end
@interface PCNativeImportDiscovery ()
- (instancetype)initWithCancellation:
    (std::shared_ptr<std::atomic_bool>)cancellation;
@end
@implementation PCNativeImportDiscovery {
  std::shared_ptr<std::atomic_bool> _cancellation;
}
- (instancetype)initWithCancellation:
    (std::shared_ptr<std::atomic_bool>)cancellation {
  if ((self = [super init]))
    _cancellation = std::move(cancellation);
  return self;
}
- (void)cancel {
  if (_cancellation)
    _cancellation->store(true);
}
- (void)dealloc {
  [self cancel];
}
@end
@implementation PCNativeBrowserApplication (DirectBrowserImportDiscovery)
+ (PCNativeImportDiscovery*)availableImportSourcesWithCompletion:
    (void (^)(NSArray<PCNativeImportSource*>*))completion {
  auto cancelled = std::make_shared<std::atomic_bool>(false);
  auto lease = [[PCNativeImportDiscovery alloc] initWithCancellation:cancelled];
  std::vector<parc::importer::Installation> installed;
  {
    const std::vector<parc::importer::Installation> candidates = {
        {0,
         "com.google.Chrome",
         "Google Chrome",
         "Library/Application Support/Google/Chrome",
         "Chrome Safe Storage",
         "Chrome",
         {}},
        {0,
         "com.brave.Browser",
         "Brave",
         "Library/Application Support/BraveSoftware/Brave-Browser",
         "Brave Safe Storage",
         "Brave",
         {}},
        {0,
         "com.microsoft.edgemac",
         "Microsoft Edge",
         "Library/Application Support/Microsoft Edge",
         "Microsoft Edge Safe Storage",
         "Microsoft Edge",
         {}},
        {0,
         "org.chromium.Chromium",
         "Chromium",
         "Library/Application Support/Chromium",
         "Chromium Safe Storage",
         "Chromium",
         {}},
        {0,
         "com.vivaldi.Vivaldi",
         "Vivaldi",
         "Library/Application Support/Vivaldi",
         "Vivaldi Safe Storage",
         "Vivaldi",
         {}},
        {0,
         "com.operasoftware.Opera",
         "Opera",
         "Library/Application Support/com.operasoftware.Opera",
         "Opera Safe Storage",
         "Opera",
         {}},
        {0,
         parc::importer::kArcBundleID,
         "Arc",
         "Library/Application Support/Arc/User Data",
         "Arc Safe Storage",
         "Arc",
         {}},
        {1, "com.apple.Safari", "Safari", "Library/Safari", "", "", {}},
        {2,
         "org.mozilla.firefox",
         "Firefox",
         "Library/Application Support/Firefox",
         "",
         "",
         {}},
        {2,
         "app.zen-browser.zen",
         "Zen",
         "Library/Application Support/zen",
         "",
         "",
         {}}};
    const base::FilePath home(base::SysNSStringToUTF8(NSHomeDirectory()));
    for (auto candidate : candidates) {
      NSURL* url = [NSWorkspace.sharedWorkspace
          URLForApplicationWithBundleIdentifier:base::SysUTF8ToNSString(
                                                    candidate.bundle_id)];
      if (candidate.bundle_id == parc::importer::kArcBundleID) {
        if (!parc::importer::ArcDataExists(home))
          continue;
        if (!url)
          url = [NSURL fileURLWithPath:base::SysUTF8ToNSString(
                                           home.Append(parc::importer::kArcData)
                                               .value())
                           isDirectory:YES];
      }
      if (!url)
        continue;
      candidate.app_path = base::FilePath(base::SysNSStringToUTF8(url.path));
      installed.push_back(std::move(candidate));
    }
  }
  base::ThreadPool::PostTaskAndReplyWithResult(
      FROM_HERE, {base::MayBlock(), base::TaskPriority::USER_VISIBLE},
      base::BindOnce(&parc::importer::Importable, std::move(installed),
                     base::FilePath(base::SysNSStringToUTF8(NSHomeDirectory()))),
      base::BindOnce(
          [](std::shared_ptr<std::atomic_bool> cancelled,
             void (^completion)(NSArray<PCNativeImportSource*>*),
             std::vector<parc::importer::Installation> importable) {
            if (cancelled->load())
              return;
            NSMutableArray* sources = [NSMutableArray array];
            for (auto& source : importable)
              [sources addObject:[[PCNativeImportSource alloc]
                                     initWithInstallation:
                                         std::make_shared<const parc::importer::
                                                              Installation>(
                                             std::move(source))]];
            completion([sources copy]);
          },
          cancelled, [completion copy]));
  return lease;
}
+ (PCNativeImportDiscovery*)
    loadImportSourceProfiles:(PCNativeImportSource*)source
                  completion:
                      (void (^)(PCNativeImportProfileResult*))completion {
  auto cancelled = std::make_shared<std::atomic_bool>(false);
  auto lease = [[PCNativeImportDiscovery alloc] initWithCancellation:cancelled];
  auto installation = [source installation];
  if (!installation) {
    dispatch_async(dispatch_get_main_queue(), ^{
      if (!cancelled->load())
        completion([[PCNativeImportProfileResult alloc]
            initWithProfiles:@[]
                  restricted:YES
                 constraints:@[]
                       error:parc::importer::ImportError(
                                 @"The selected browser is no longer "
                                 @"available.")]);
    });
    return lease;
  }
  base::ThreadPool::PostTaskAndReplyWithResult(
      FROM_HERE, {base::MayBlock(), base::TaskPriority::USER_VISIBLE},
      base::BindOnce(
          &parc::importer::Load,
          std::make_shared<const parc::importer::Installation>(*installation),
          base::FilePath(base::SysNSStringToUTF8(NSHomeDirectory())), false),
      base::BindOnce(
          [](std::shared_ptr<std::atomic_bool> cancelled,
             PCNativeImportSource* source,
             void (^completion)(PCNativeImportProfileResult*),
             parc::importer::ProfilesResult result) {
            if (cancelled->load())
              return;
            NSMutableArray* profiles = [NSMutableArray array];
            for (auto& p : result.profiles)
              [profiles addObject:[[PCNativeImportProfile alloc]
                                      initWithData:std::move(p)
                                            source:source]];
            NSMutableArray* constraints = [NSMutableArray array];
            for (const auto& s : result.constraints)
              [constraints addObject:base::SysUTF8ToNSString(s)];
            completion([[PCNativeImportProfileResult alloc]
                initWithProfiles:profiles
                      restricted:result.restricted
                     constraints:constraints
                           error:nil]);
          },
          cancelled, source, [completion copy]));
  return lease;
}
+ (PCNativeImportDiscovery*)
    loadSafariExportProfiles:(NSArray<NSURL*>*)directories
                       names:(NSArray<NSString*>*)names
                  completion:
                      (void (^)(PCNativeImportProfileResult*))completion {
  auto cancelled = std::make_shared<std::atomic_bool>(false);
  auto lease = [[PCNativeImportDiscovery alloc] initWithCancellation:cancelled];
  std::vector<std::pair<base::FilePath, std::string>> entries;
  for (NSUInteger index = 0; index < directories.count && index < names.count;
       ++index) {
    if (directories[index].isFileURL && directories[index].path.absolutePath)
      entries.emplace_back(
          base::FilePath(base::SysNSStringToUTF8(directories[index].path)),
          base::SysNSStringToUTF8(names[index]));
  }
  auto installation = std::make_shared<parc::importer::Installation>(
      parc::importer::Installation{1, "com.apple.Safari", "Safari", "", "", "",
                                   entries.empty() ? base::FilePath()
                                                   : entries.front().first.DirName()});
  PCNativeImportSource* source =
      [[PCNativeImportSource alloc] initWithInstallation:installation];
  base::ThreadPool::PostTaskAndReplyWithResult(
      FROM_HERE, {base::MayBlock(), base::TaskPriority::USER_VISIBLE},
      base::BindOnce(
          [](std::shared_ptr<const parc::importer::Installation> installation,
             std::vector<std::pair<base::FilePath, std::string>> entries) {
            parc::importer::ProfilesResult result;
            for (const auto& [path, name] : entries)
              parc::importer::AddProfile(result, installation, path, name, false);
            return result;
          },
          std::shared_ptr<const parc::importer::Installation>(installation),
          std::move(entries)),
      base::BindOnce(
          [](std::shared_ptr<std::atomic_bool> cancelled,
             PCNativeImportSource* source,
             void (^completion)(PCNativeImportProfileResult*),
             parc::importer::ProfilesResult result) {
            if (cancelled->load())
              return;
            NSMutableArray* profiles = [NSMutableArray array];
            for (auto& p : result.profiles)
              [profiles addObject:[[PCNativeImportProfile alloc]
                                      initWithData:std::move(p)
                                            source:source]];
            completion([[PCNativeImportProfileResult alloc]
                initWithProfiles:profiles
                      restricted:result.restricted
                     constraints:@[]
                           error:nil]);
          },
          cancelled, source, [completion copy]));
  return lease;
}
@end
