// Copyright 2026 Parc contributors.
#include "parc/importer/import_reader.h"
#include "parc/importer/import_snapshot.h"

#include <algorithm>
#include <iterator>
#include <limits>
#include <map>
#include <set>
#include <string>
#include <string_view>
#include <vector>

#include "base/strings/utf_string_conversions.h"
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
void WarnOnce(Batch& batch, const std::string& message) {
  if (std::find(batch.warnings.begin(), batch.warnings.end(), message) ==
      batch.warnings.end()) batch.warnings.emplace_back(message);
}
bool Importable(const GURL& url) {
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
Batch HistoryRows(sqlite3* database, const std::string& name,
                  const Cancellation& cancel) {
  Statement rows(database,
      "SELECT h.url, h.title, h.visit_count, h.hidden, h.typed, v.visit_date "
      "FROM moz_places h JOIN moz_historyvisits v ON h.id = v.place_id "
      "WHERE v.visit_type <= 3");
  if (!rows.valid()) return Failure(kHistory, name + " history has an unsupported database schema.");
  Batch batch;
  batch.category = kHistory;
  size_t count = 0;
  while (rows.Step()) {
    if (Cancelled(cancel)) return Failure(kHistory, "Import was cancelled.");
    if (++count > kMaxRows) return Failure(kHistory, name + " history exceeds the import limit.");
    GURL url(rows.Text(0));
    History entry;
    if (!Importable(url) || !Count(rows.Int(2)) || !Count(rows.Int(4)) ||
        !Time(rows.Int(5), entry.last_visit)) {
      WarnOnce(batch, "Unsupported or invalid " + name + " history entries were skipped.");
      continue;
    }
    entry.url = url.spec();
    entry.title = rows.Text16(1);
    entry.visits = static_cast<int>(rows.Int(2));
    entry.hidden = rows.Int(3) == 1;
    entry.typed = static_cast<int>(rows.Int(4));
    batch.history.push_back(std::move(entry));
  }
  if (!rows.done()) return Failure(kHistory, name + " history could not be read completely.");
  batch.success = true;
  return batch;
}
Batch FormRows(sqlite3* database, const std::string& name,
               const Cancellation& cancel) {
  Statement rows(database,
      "SELECT fieldname, value, timesUsed, firstUsed, lastUsed FROM moz_formhistory");
  if (!rows.valid()) return Failure(kAutofill, name + " form history has an unsupported database schema.");
  Batch batch;
  batch.category = kAutofill;
  size_t count = 0;
  while (rows.Step()) {
    if (Cancelled(cancel)) return Failure(kAutofill, "Import was cancelled.");
    if (++count > kMaxRows) return Failure(kAutofill, name + " form history exceeds the import limit.");
    if (rows.Text(0) == "searchbar-history") continue;
    Autofill entry;
    if (!Count(rows.Int(2)) || !Time(rows.Int(3), entry.created) ||
        !Time(rows.Int(4), entry.last_used)) {
      WarnOnce(batch, "Invalid " + name + " form history entries were skipped.");
      continue;
    }
    entry.fields["name"] = rows.Text16(0);
    entry.fields["value"] = rows.Text16(1);
    entry.use_count = static_cast<int>(rows.Int(2));
    batch.autofill.push_back(std::move(entry));
  }
  if (!rows.done()) return Failure(kAutofill, name + " form history could not be read completely.");
  batch.success = true;
  return batch;
}
struct Node {
  int64_t id = 0, parent = 0, position = 0, type = 0;
  std::string guid, url;
  std::u16string title;
};
struct Root {
  const char* guid;
  const char16_t* title;
  bool required;
};
constexpr char kMenu[] = "menu________";
constexpr Root kRoots[] = {{"toolbar_____", u"Bookmarks Toolbar", true},
                           {kMenu, nullptr, true},
                           {"unfiled_____", u"Other Bookmarks", true},
                           {"mobile______", u"Mobile Bookmarks", false}};
constexpr std::string_view kStockBookmarks[] = {
    "https://support.mozilla.org/products/firefox",
    "https://support.mozilla.org/kb/customize-firefox-controls-buttons-and-"
    "toolbars?utm_source=firefox-browser&utm_medium=default-bookmarks&utm_"
    "campaign=customize",
    "https://www.mozilla.org/contribute/",
    "https://www.mozilla.org/about/"};
bool Stock(const std::string& url) {
  return std::find(std::begin(kStockBookmarks), std::end(kStockBookmarks),
                   url) != std::end(kStockBookmarks);
}
Batch BookmarkRows(sqlite3* database, const std::string& name,
                   const Cancellation& cancel) {
  Batch batch;
  batch.category = kBookmarks;
  std::set<int64_t> excluded;
  const bool annotations = HasTable(database, "moz_items_annos");
  const bool attributes = HasTable(database, "moz_anno_attributes");
  if (annotations != attributes)
    return Failure(kBookmarks, name + " bookmark annotations are incomplete.");
  if (annotations) {
    Statement rows(database,
        "SELECT a.item_id FROM moz_items_annos a JOIN moz_anno_attributes n "
        "ON a.anno_attribute_id=n.id WHERE n.name IN "
        "('livemark/feedURI','bookmarkProperties/POSTData')");
    if (!rows.valid()) return Failure(kBookmarks, name + " bookmark annotations are malformed.");
    size_t count = 0;
    while (rows.Step()) {
      if (Cancelled(cancel)) return Failure(kBookmarks, "Import was cancelled.");
      if (++count > kMaxRows) return Failure(kBookmarks, name + " bookmarks exceed the import limit.");
      excluded.insert(rows.Int(0));
    }
    if (!rows.done()) return Failure(kBookmarks, name + " bookmark annotations could not be read completely.");
  }
  Statement rows(database,
      "SELECT b.id,b.parent,b.position,b.type,b.guid,b.title,p.url,p.title "
      "FROM moz_bookmarks b LEFT JOIN moz_places p ON b.fk=p.id "
      "ORDER BY b.parent,b.position,b.id");
  if (!rows.valid()) return Failure(kBookmarks, name + " bookmarks have an unsupported database schema.");
  std::map<int64_t, Node> nodes;
  std::map<int64_t, std::vector<int64_t>> children;
  std::map<std::string, int64_t> roots;
  size_t count = 0;
  while (rows.Step()) {
    if (Cancelled(cancel)) return Failure(kBookmarks, "Import was cancelled.");
    if (++count > kMaxRows) return Failure(kBookmarks, name + " bookmarks exceed the import limit.");
    Node node{rows.Int(0), rows.Int(1), rows.Int(2), rows.Int(3), rows.Text(4),
              rows.Text(6), rows.Text16(5)};
    if (node.title.empty()) node.title = rows.Text16(7);
    if (node.id <= 0 || node.position < 0 || !nodes.emplace(node.id, node).second)
      return Failure(kBookmarks, name + " bookmarks contain invalid or duplicate identities.");
    children[node.parent].push_back(node.id);
    for (const Root& root : kRoots) {
      if (node.guid != root.guid) continue;
      if (node.type != 2 || !roots.emplace(node.guid, node.id).second)
        return Failure(kBookmarks, name + " bookmark roots are ambiguous.");
    }
  }
  if (!rows.done()) return Failure(kBookmarks, name + " bookmarks could not be read completely.");
  for (const Root& root : kRoots) {
    if (root.required && !roots.contains(root.guid))
      return Failure(kBookmarks, name + " bookmark roots could not be identified.");
  }
  std::set<int64_t> visited;
  size_t stock = 0;
  auto read = [&](auto&& self, int64_t id, const std::string& parent,
                  size_t depth, std::vector<Bookmark>& out) -> bool {
    if (Cancelled(cancel) || depth > kMaxDepth || !visited.insert(id).second)
      return false;
    const Node& node = nodes.at(id);
    if (excluded.contains(id)) {
      WarnOnce(batch, name + " live bookmarks and POST-based bookmark entries were skipped.");
      return true;
    }
    const std::string key = "firefox:" + std::to_string(id);
    if (node.type == 2) {
      const size_t start = out.size(), dropped = stock;
      out.push_back({key, parent, node.title, {}, true});
      for (int64_t child : children[id])
        if (!self(self, child, key, depth + 1, out)) return false;
      if (out.size() == start + 1 && stock > dropped &&
          nodes.at(node.parent).guid == kMenu)
        out.pop_back();
    } else if (node.type == 1) {
      if (!children[id].empty()) return false;
      GURL url(node.url);
      if (url.SchemeIs("place")) return true;
      if (Stock(node.url)) {
        ++stock;
        return true;
      }
      if (Importable(url))
        out.push_back({key, parent,
                       node.title.empty() ? base::UTF8ToUTF16(url.spec()) : node.title,
                       url.spec(), false});
      else WarnOnce(batch, "Unsupported or invalid " + name + " bookmark URLs were skipped.");
    } else if (node.type != 3) {
      WarnOnce(batch, name + " unsupported dynamic bookmark items were skipped.");
    }
    return true;
  };
  for (const Root& root : kRoots) {
    const auto found = roots.find(root.guid);
    if (found == roots.end()) continue;
    const int64_t id = found->second;
    const std::string key = root.title ? "firefox:" + std::to_string(id) : "";
    std::vector<Bookmark> items;
    bool complete = visited.insert(id).second;
    for (int64_t child : children[id]) {
      if (!complete) break;
      complete = read(read, child, key, 1, items);
    }
    if (!complete)
      return Failure(kBookmarks, Cancelled(cancel) ? "Import was cancelled."
          : name + " bookmarks have a cyclic or excessively deep hierarchy.");
    if (items.empty()) continue;
    if (root.title)
      batch.bookmarks.push_back({key, {}, std::u16string(root.title), {}, true});
    std::move(items.begin(), items.end(), std::back_inserter(batch.bookmarks));
  }
  batch.success = true;
  return batch;
}
}

Batch ReadFirefoxCategory(const ReadOptions& options, uint32_t category,
                          const Cancellation& cancel) {
  if (Cancelled(cancel)) return Failure(category, "Import was cancelled.");
  const std::string name =
      options.source_name.empty() ? "Firefox" : options.source_name;
  if (options.family != Family::kFirefox || !options.profile_path.IsAbsolute())
    return Failure(category, "The selected " + name + " source is invalid.");
  if (category != kHistory && category != kBookmarks && category != kAutofill)
    return Failure(category, "This category is not supported by the " + name + " reader on macOS. Use the supported browser export flow when available.");
  SnapshotDatabase database;
  if (!database.Open(options.profile_path.AppendASCII(
          category == kAutofill ? "formhistory.sqlite" : "places.sqlite")))
    return Failure(category, database.error());
  Batch batch = category == kHistory ? HistoryRows(database.get(), name, cancel)
      : category == kBookmarks ? BookmarkRows(database.get(), name, cancel)
      : FormRows(database.get(), name, cancel);
  if (Cancelled(cancel)) return Failure(category, "Import was cancelled.");
  return batch;
}
}
