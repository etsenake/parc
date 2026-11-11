// Copyright 2026 Parc contributors.
#include "parc/importer/import_reader.h"
#include "parc/importer/import_snapshot.h"

#include <algorithm>
#include <limits>
#include <map>
#include <set>
#include <string>
#include <vector>

#include "url/gurl.h"

namespace parc::importer {
namespace {
constexpr size_t kMaxRows = 1000000;
constexpr size_t kMaxDepth = 128;
constexpr int64_t kUnixEpochMicros = 11644473600000000;
bool Cancelled(const Cancellation& cancel) {
  return cancel && cancel->load(std::memory_order_relaxed);
}
Batch Failure(uint32_t category, std::string error) {
  Batch batch;
  batch.category = category;
  batch.error = std::move(error);
  return batch;
}
void WarnOnce(Batch& batch, const char* message) {
  if (std::find(batch.warnings.begin(), batch.warnings.end(), message) ==
      batch.warnings.end()) batch.warnings.emplace_back(message);
}
bool Importable(const GURL& url) {
  // Native Firefox importer exclusions: internal/query URLs are not navigable
  // in the destination browser. No URL reconstruction or POST-to-GET fallback.
  return url.is_valid() && !url.SchemeIs("wyciwyg") && !url.SchemeIs("place") &&
         !url.SchemeIs("about") && !url.SchemeIs("chrome");
}
bool Time(int64_t unix_micros, int64_t& output) {
  if (unix_micros < -kUnixEpochMicros ||
      unix_micros > std::numeric_limits<int64_t>::max() - kUnixEpochMicros)
    return false;
  output = unix_micros + kUnixEpochMicros;
  return true;
}
bool Count(int64_t value) {
  return value >= 0 && value <= std::numeric_limits<int>::max();
}
Batch HistoryRows(sqlite3* database, const Cancellation& cancel) {
  Statement rows(database,
      "SELECT h.url, h.title, h.visit_count, h.hidden, h.typed, v.visit_date "
      "FROM moz_places h JOIN moz_historyvisits v ON h.id = v.place_id "
      "WHERE v.visit_type <= 3");
  if (!rows.valid()) return Failure(kHistory, "Firefox history has an unsupported database schema.");
  Batch batch;
  batch.category = kHistory;
  size_t count = 0;
  while (rows.Step()) {
    if (Cancelled(cancel)) return Failure(kHistory, "Import was cancelled.");
    if (++count > kMaxRows) return Failure(kHistory, "Firefox history exceeds the import limit.");
    GURL url(rows.Text(0));
    History entry;
    if (!Importable(url) || !Count(rows.Int(2)) || !Count(rows.Int(4)) ||
        !Time(rows.Int(5), entry.last_visit)) {
      WarnOnce(batch, "Unsupported or invalid Firefox history entries were skipped.");
      continue;
    }
    entry.url = url.spec();
    entry.title = rows.Text16(1);
    entry.visits = static_cast<int>(rows.Int(2));
    entry.hidden = rows.Int(3) == 1;
    entry.typed = static_cast<int>(rows.Int(4));
    batch.history.push_back(std::move(entry));
  }
  if (!rows.done()) return Failure(kHistory, "Firefox history could not be read completely.");
  batch.success = true;
  return batch;
}
Batch FormRows(sqlite3* database, const Cancellation& cancel) {
  Statement rows(database,
      "SELECT fieldname, value, timesUsed, firstUsed, lastUsed FROM moz_formhistory");
  if (!rows.valid()) return Failure(kAutofill, "Firefox form history has an unsupported database schema.");
  Batch batch;
  batch.category = kAutofill;
  size_t count = 0;
  while (rows.Step()) {
    if (Cancelled(cancel)) return Failure(kAutofill, "Import was cancelled.");
    if (++count > kMaxRows) return Failure(kAutofill, "Firefox form history exceeds the import limit.");
    if (rows.Text(0) == "searchbar-history") continue;
    Autofill entry;
    if (!Count(rows.Int(2)) || !Time(rows.Int(3), entry.created) ||
        !Time(rows.Int(4), entry.last_used)) {
      WarnOnce(batch, "Invalid Firefox form history entries were skipped.");
      continue;
    }
    entry.fields["name"] = rows.Text16(0);
    entry.fields["value"] = rows.Text16(1);
    entry.use_count = static_cast<int>(rows.Int(2));
    batch.autofill.push_back(std::move(entry));
  }
  if (!rows.done()) return Failure(kAutofill, "Firefox form history could not be read completely.");
  batch.success = true;
  return batch;
}
struct Node {
  int64_t id = 0, parent = 0, position = 0, type = 0;
  std::string guid, url;
  std::u16string title;
};
Batch BookmarkRows(sqlite3* database, const Cancellation& cancel) {
  Batch batch;
  batch.category = kBookmarks;
  std::set<int64_t> excluded;
  // Modern databases can omit obsolete annotation tables entirely. If either
  // exists, require the complete pair rather than losing POST/livemark guards.
  const bool annotations = HasTable(database, "moz_items_annos");
  const bool attributes = HasTable(database, "moz_anno_attributes");
  if (annotations != attributes)
    return Failure(kBookmarks, "Firefox bookmark annotations are incomplete.");
  if (annotations) {
    Statement rows(database,
        "SELECT a.item_id FROM moz_items_annos a JOIN moz_anno_attributes n "
        "ON a.anno_attribute_id=n.id WHERE n.name IN "
        "('livemark/feedURI','bookmarkProperties/POSTData')");
    if (!rows.valid()) return Failure(kBookmarks, "Firefox bookmark annotations are malformed.");
    size_t count = 0;
    while (rows.Step()) {
      if (Cancelled(cancel)) return Failure(kBookmarks, "Import was cancelled.");
      if (++count > kMaxRows) return Failure(kBookmarks, "Firefox bookmarks exceed the import limit.");
      excluded.insert(rows.Int(0));
    }
    if (!rows.done()) return Failure(kBookmarks, "Firefox bookmark annotations could not be read completely.");
  }
  Statement rows(database,
      "SELECT b.id,b.parent,b.position,b.type,b.guid,b.title,p.url "
      "FROM moz_bookmarks b LEFT JOIN moz_places p ON b.fk=p.id "
      "ORDER BY b.parent,b.position,b.id");
  if (!rows.valid()) return Failure(kBookmarks, "Firefox bookmarks have an unsupported database schema.");
  std::map<int64_t, Node> nodes;
  std::map<int64_t, std::vector<int64_t>> children;
  std::map<std::string, int64_t> roots;
  size_t count = 0;
  while (rows.Step()) {
    if (Cancelled(cancel)) return Failure(kBookmarks, "Import was cancelled.");
    if (++count > kMaxRows) return Failure(kBookmarks, "Firefox bookmarks exceed the import limit.");
    Node node{rows.Int(0), rows.Int(1), rows.Int(2), rows.Int(3), rows.Text(4),
              rows.Text(6), rows.Text16(5)};
    if (node.id <= 0 || node.position < 0 || !nodes.emplace(node.id, node).second)
      return Failure(kBookmarks, "Firefox bookmarks contain invalid or duplicate identities.");
    children[node.parent].push_back(node.id);
    if (node.guid == "toolbar_____" || node.guid == "menu________" ||
        node.guid == "unfiled_____") {
      if (node.type != 2 || !roots.emplace(node.guid, node.id).second)
        return Failure(kBookmarks, "Firefox bookmark roots are ambiguous.");
    }
  }
  if (!rows.done()) return Failure(kBookmarks, "Firefox bookmarks could not be read completely.");
  if (roots.size() != 3)
    return Failure(kBookmarks, "Firefox bookmark roots could not be identified.");
  std::set<int64_t> visited;
  auto read = [&](auto&& self, int64_t id, std::string parent, size_t depth,
                  bool flatten) -> bool {
    if (Cancelled(cancel) || depth > kMaxDepth || !visited.insert(id).second)
      return false;
    const Node& node = nodes.at(id);
    if (excluded.contains(id)) {
      WarnOnce(batch, "Firefox live bookmarks and POST-based bookmark entries were skipped.");
      return true;
    }
    const std::string key = "firefox:" + std::to_string(id);
    if (node.type == 2) {
      if (!flatten) {
        batch.bookmarks.push_back({key, parent, node.title, {}, true});
        parent = key;
      }
      for (int64_t child : children[id])
        if (!self(self, child, parent, depth + 1, false)) return false;
    } else if (node.type == 1) {
      if (!children[id].empty()) return false;
      GURL url(node.url);
      if (Importable(url))
        batch.bookmarks.push_back({key, parent, node.title, url.spec(), false});
      else WarnOnce(batch, "Unsupported or invalid Firefox bookmark URLs were skipped.");
    } else {
      WarnOnce(batch, "Firefox separators and unsupported dynamic bookmark items were skipped.");
    }
    return true;
  };
  for (const char* root : {"toolbar_____", "menu________", "unfiled_____"}) {
    if (!read(read, roots.at(root), {}, 0, std::string_view(root) == "menu________"))
      return Failure(kBookmarks, Cancelled(cancel) ? "Import was cancelled."
          : "Firefox bookmarks have a cyclic or excessively deep hierarchy.");
  }
  // Nonstandard Firefox roots are not silently imported as ordinary bookmarks.
  // Standard root/separator metadata is intentionally not a destination item.
  batch.success = true;
  return batch;
}
}  // namespace

Batch ReadFirefoxCategory(const ReadOptions& options, uint32_t category,
                          const Cancellation& cancel) {
  if (Cancelled(cancel)) return Failure(category, "Import was cancelled.");
  if (options.family != Family::kFirefox || !options.profile_path.IsAbsolute())
    return Failure(category, "The selected Firefox source is invalid.");
  if (category != kHistory && category != kBookmarks && category != kAutofill)
    return Failure(category, "This category is not supported by the Firefox reader on macOS. Use the supported browser export flow when available.");
  SnapshotDatabase database;
  if (!database.Open(options.profile_path.AppendASCII(
          category == kAutofill ? "formhistory.sqlite" : "places.sqlite")))
    return Failure(category, database.error());
  Batch batch = category == kHistory ? HistoryRows(database.get(), cancel)
      : category == kBookmarks ? BookmarkRows(database.get(), cancel)
      : FormRows(database.get(), cancel);
  if (Cancelled(cancel)) return Failure(category, "Import was cancelled.");
  return batch;
}
}  // namespace parc::importer
