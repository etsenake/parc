// Copyright 2026 Parc contributors.
#include "parc/importer/import_reader.h"
#include "parc/importer/import_snapshot.h"

#import <Foundation/Foundation.h>

#include <algorithm>
#include <cmath>
#include <limits>
#include <string>
#include <sys/stat.h>

#include "base/files/file_util.h"
#include "base/strings/sys_string_conversions.h"
#include "url/gurl.h"

namespace parc::importer {
namespace {
constexpr size_t kMaxRows = 1000000;
constexpr size_t kMaxPlistBytes = 64 * 1024 * 1024;
constexpr size_t kMaxDepth = 128;
constexpr long double kCocoaEpochMicros = 12622780800000000.0L;

bool Cancelled(const Cancellation& cancel) {
  return cancel && cancel->load(std::memory_order_relaxed);
}
Batch Failure(uint32_t category, std::string error) {
  Batch result;
  result.category = category;
  result.error = std::move(error);
  return result;
}
void WarnOnce(Batch& batch, const char* message) {
  if (std::find(batch.warnings.begin(), batch.warnings.end(), message) ==
      batch.warnings.end()) {
    batch.warnings.emplace_back(message);
  }
}
NSString* String(id value) {
  return [value isKindOfClass:[NSString class]] ? value : nil;
}
NSDictionary* Dictionary(id value) {
  return [value isKindOfClass:[NSDictionary class]] ? value : nil;
}

// The selected source directory already identifies the Safari profile. Never
// substitute another home/container path when access is denied or data is absent.
Batch ReadBookmarks(const ReadOptions& options, const Cancellation& cancel) {
  const auto path = options.profile_path.AppendASCII("Bookmarks.plist");
  struct stat before {}, after {};
  std::string bytes;
  if (stat(path.value().c_str(), &before) != 0 || !S_ISREG(before.st_mode) ||
      !base::ReadFileToStringWithMaxSize(path, &bytes, kMaxPlistBytes) ||
      stat(path.value().c_str(), &after) != 0) {
    return Failure(kBookmarks, "Safari bookmarks are unavailable, too large, or access is restricted.");
  }
  if (before.st_dev != after.st_dev || before.st_ino != after.st_ino ||
      before.st_size != after.st_size || before.st_mtimespec.tv_sec != after.st_mtimespec.tv_sec ||
      before.st_mtimespec.tv_nsec != after.st_mtimespec.tv_nsec ||
      before.st_ctimespec.tv_sec != after.st_ctimespec.tv_sec ||
      before.st_ctimespec.tv_nsec != after.st_ctimespec.tv_nsec) {
    return Failure(kBookmarks, "Safari changed its bookmarks during import. Close it and try again.");
  }
  if (Cancelled(cancel)) return Failure(kBookmarks, "Import was cancelled.");
  NSData* data = [NSData dataWithBytes:bytes.data() length:bytes.size()];
  id plist = [NSPropertyListSerialization propertyListWithData:data
      options:NSPropertyListImmutable format:nil error:nil];
  NSDictionary* root = Dictionary(plist);
  if (!root || ![root[@"Children"] isKindOfClass:[NSArray class]]) {
    return Failure(kBookmarks, "Safari bookmarks have an unsupported or malformed structure.");
  }
  Batch batch;
  batch.category = kBookmarks;
  size_t visited = 0;
  // Source positions are import-local IDs, never destination bookmark IDs.
  auto read = [&](auto&& self, NSDictionary* node, std::string key,
                  std::string parent, size_t depth, bool is_root) -> bool {
    if (Cancelled(cancel) || ++visited > kMaxRows || depth > kMaxDepth)
      return false;
    NSString* type = String(node[@"WebBookmarkType"]);
    if (is_root || [type isEqualToString:@"WebBookmarkTypeList"]) {
      NSString* title = String(node[@"Title"]);
      id children = node[@"Children"];
      if ((!is_root && !title) ||
          (children && ![children isKindOfClass:[NSArray class]])) return false;
      // Match the native Safari importer: root/menu are structural, while the
      // toolbar and ordinary folders remain explicit, including empty folders.
      if (!is_root && !(parent.empty() && [title isEqualToString:@"BookmarksMenu"])) {
        batch.bookmarks.push_back({key, parent, base::SysNSStringToUTF16(title), {}, true});
        parent = key;
      }
      size_t index = 0;
      for (id child in (NSArray*)children) {
        NSDictionary* dictionary = Dictionary(child);
        if (!dictionary || !self(self, dictionary, key + "/" + std::to_string(index),
                                  parent, depth + 1, false)) return false;
        ++index;
      }
      return true;
    }
    if (![type isEqualToString:@"WebBookmarkTypeLeaf"]) {
      WarnOnce(batch, "Unsupported Safari bookmark item types were skipped.");
      return true;
    }
    NSString* url = String(node[@"URLString"]);
    NSString* title = String(Dictionary(node[@"URIDictionary"])[@"title"]);
    if (!url || !title) return false;
    GURL parsed(base::SysNSStringToUTF8(url));
    if (!parsed.is_valid()) {
      WarnOnce(batch, "Bookmarks with invalid URLs were skipped.");
      return true;
    }
    batch.bookmarks.push_back({key, parent, base::SysNSStringToUTF16(title), parsed.spec(), false});
    return true;
  };
  if (!read(read, root, "safari", {}, 0, true)) {
    return Failure(kBookmarks, Cancelled(cancel) ? "Import was cancelled."
        : "Safari bookmarks have an invalid hierarchy or exceed the import limits.");
  }
  if (Cancelled(cancel)) return Failure(kBookmarks, "Import was cancelled.");
  batch.success = true;
  return batch;
}

Batch ReadHistory(const ReadOptions& options, const Cancellation& cancel) {
  SnapshotDatabase database;
  if (!database.Open(options.profile_path.AppendASCII("History.db")))
    return Failure(kHistory, database.error());
  Statement rows(database.get(),
      "SELECT i.url, v.title, i.visit_count, v.visit_time "
      "FROM history_items i JOIN history_visits v ON i.id = v.history_item");
  if (!rows.valid()) return Failure(kHistory, "Safari history has an unsupported database schema.");
  Batch batch;
  batch.category = kHistory;
  size_t count = 0;
  while (rows.Step()) {
    if (Cancelled(cancel)) return Failure(kHistory, "Import was cancelled.");
    if (++count > kMaxRows) return Failure(kHistory, "Safari history exceeds the import limit.");
    GURL url(rows.Text(0));
    const int64_t visits = rows.Int(2);
    const double seconds = rows.Double(3);
    const long double micros = static_cast<long double>(seconds) * 1000000 + kCocoaEpochMicros;
    if (!url.is_valid() || visits < 0 || visits > std::numeric_limits<int>::max() ||
        !std::isfinite(seconds) || micros < 0 ||
        micros >= static_cast<long double>(std::numeric_limits<int64_t>::max())) {
      WarnOnce(batch, "Invalid Safari history entries were skipped.");
      continue;
    }
    History entry;
    entry.url = url.spec();
    entry.title = rows.Text16(1);
    entry.visits = static_cast<int>(visits);
    entry.last_visit = static_cast<int64_t>(micros);
    batch.history.push_back(std::move(entry));
  }
  if (!rows.done()) return Failure(kHistory, "Safari history could not be read completely.");
  if (Cancelled(cancel)) return Failure(kHistory, "Import was cancelled.");
  batch.success = true;
  return batch;
}
}  // namespace

Batch ReadSafariCategory(const ReadOptions& options, uint32_t category,
                         const Cancellation& cancel) {
  @autoreleasepool {
    if (Cancelled(cancel)) return Failure(category, "Import was cancelled.");
    if (options.family != Family::kSafari || !options.profile_path.IsAbsolute())
      return Failure(category, "The selected Safari source is invalid.");
    if (category == kBookmarks) return ReadBookmarks(options, cancel);
    if (category == kHistory) return ReadHistory(options, cancel);
    return Failure(category, "This category is not supported by the Safari reader. Use the supported browser export flow when available.");
  }
}
}  // namespace parc::importer
