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
#include "base/json/json_reader.h"
#include "base/strings/string_number_conversions.h"
#include "base/strings/sys_string_conversions.h"
#include "base/strings/utf_string_conversions.h"
#include "base/values.h"
#include "url/gurl.h"

namespace parc::importer {
namespace {
constexpr size_t kMaxRows = 1000000;
constexpr size_t kMaxPlistBytes = 64 * 1024 * 1024;
constexpr size_t kMaxHistoryJSONBytes = 256 * 1024 * 1024;
constexpr size_t kMaxCardsJSONBytes = 16 * 1024 * 1024;
constexpr int64_t kUnixEpochMicros = 11644473600000000LL;
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

bool SameFile(const struct stat& before, const struct stat& after) {
  return before.st_dev == after.st_dev && before.st_ino == after.st_ino &&
      before.st_size == after.st_size && before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec &&
      before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec &&
      before.st_ctimespec.tv_sec == after.st_ctimespec.tv_sec &&
      before.st_ctimespec.tv_nsec == after.st_ctimespec.tv_nsec;
}

Batch ReadBookmarks(const ReadOptions& options, const Cancellation& cancel) {
  const auto path = options.profile_path.AppendASCII("Bookmarks.plist");
  struct stat before {}, after {};
  std::string bytes;
  if (stat(path.value().c_str(), &before) != 0 || !S_ISREG(before.st_mode) ||
      !base::ReadFileToStringWithMaxSize(path, &bytes, kMaxPlistBytes) ||
      stat(path.value().c_str(), &after) != 0) {
    return Failure(kBookmarks, "Safari bookmarks are unavailable, too large, or access is restricted.");
  }
  if (!SameFile(before, after)) {
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

Batch ReadExportedHistory(const base::FilePath& path, const Cancellation& cancel) {
  struct stat before {}, after {};
  std::string bytes;
  if (lstat(path.value().c_str(), &before) != 0 || !S_ISREG(before.st_mode) ||
      !base::ReadFileToStringWithMaxSize(path, &bytes, kMaxHistoryJSONBytes) ||
      stat(path.value().c_str(), &after) != 0 || !SameFile(before, after)) {
    return Failure(kHistory, "The exported Safari history is unavailable, changed while reading, or too large.");
  }
  if (Cancelled(cancel)) return Failure(kHistory, "Import was cancelled.");
  std::optional<base::DictValue> root = base::JSONReader::ReadDict(
      bytes, base::JSON_PARSE_RFC | base::JSON_REPLACE_INVALID_CHARACTERS);
  std::string().swap(bytes);
  const base::DictValue* metadata = root ? root->FindDict("metadata") : nullptr;
  const std::string* type = metadata ? metadata->FindString("data_type") : nullptr;
  const base::ListValue* items = root ? root->FindList("history") : nullptr;
  if (!type || *type != "history" || !items)
    return Failure(kHistory, "The exported Safari history has an unsupported structure.");
  if (items->size() > kMaxRows) return Failure(kHistory, "Safari history exceeds the import limit.");
  Batch batch;
  batch.category = kHistory;
  for (const base::Value& value : *items) {
    if (Cancelled(cancel)) return Failure(kHistory, "Import was cancelled.");
    const base::DictValue* item = value.GetIfDict();
    const std::string* text = item ? item->FindString("url") : nullptr;
    const std::optional<double> time = item ? item->FindDouble("time_usec") : std::nullopt;
    std::optional<double> visits = item ? item->FindDouble("visit_count") : std::nullopt;
    if (item && !visits) visits = item->FindDouble("visits_count");
    const GURL url(text ? *text : std::string());
    constexpr double kLatest = 9e18;
    if (!url.is_valid() || !time || !std::isfinite(*time) || *time < 0 || *time >= kLatest ||
        (visits && (!std::isfinite(*visits) || *visits < 0))) {
      WarnOnce(batch, "Invalid Safari history entries were skipped.");
      continue;
    }
    History entry;
    entry.url = url.spec();
    if (const std::string* title = item->FindString("title")) entry.title = base::UTF8ToUTF16(*title);
    entry.visits = static_cast<int>(std::clamp(visits.value_or(1), 1.0, static_cast<double>(std::numeric_limits<int>::max())));
    entry.hidden = item->FindString("destination_url") != nullptr;
    entry.last_visit = static_cast<int64_t>(*time) + kUnixEpochMicros;
    batch.history.push_back(std::move(entry));
  }
  if (Cancelled(cancel)) return Failure(kHistory, "Import was cancelled.");
  batch.success = true;
  return batch;
}

void Wipe(std::string* text) {
  if (text) std::fill(text->begin(), text->end(), '\0');
}

struct CardWipe {
  base::ListValue* cards = nullptr;
  ~CardWipe() {
    if (!cards) return;
    for (base::Value& value : *cards) {
      if (base::DictValue* card = value.GetIfDict()) {
        for (const char* key : {"card_number", "cardholder_name", "card_name"}) Wipe(card->FindString(key));
      }
    }
  }
};

Batch ReadExportedCards(const ReadOptions& options, const Cancellation& cancel) {
  const auto path = options.profile_path.AppendASCII("PaymentCards.json");
  struct stat before {}, after {};
  std::string bytes;
  const bool read = lstat(path.value().c_str(), &before) == 0 && S_ISREG(before.st_mode) &&
      base::ReadFileToStringWithMaxSize(path, &bytes, kMaxCardsJSONBytes) &&
      stat(path.value().c_str(), &after) == 0 && SameFile(before, after);
  if (!read) {
    Wipe(&bytes);
    return Failure(kAutofill, "The exported Safari payment cards are unavailable, changed while reading, or too large.");
  }
  std::optional<base::DictValue> root = base::JSONReader::ReadDict(
      bytes, base::JSON_PARSE_RFC | base::JSON_REPLACE_INVALID_CHARACTERS);
  Wipe(&bytes);
  std::string().swap(bytes);
  base::ListValue* cards = root ? root->FindList("payment_cards") : nullptr;
  CardWipe wipe{cards};
  if (Cancelled(cancel)) return Failure(kAutofill, "Import was cancelled.");
  const base::DictValue* metadata = root ? root->FindDict("metadata") : nullptr;
  const std::string* type = metadata ? metadata->FindString("data_type") : nullptr;
  if (!type || *type != "payment_cards" || !cards)
    return Failure(kAutofill, "The exported Safari payment cards have an unsupported structure.");
  if (cards->size() > kMaxRows) return Failure(kAutofill, "Safari payment cards exceed the import limit.");
  Batch batch;
  batch.category = kAutofill;
  for (base::Value& value : *cards) {
    if (Cancelled(cancel)) break;
    base::DictValue* card = value.GetIfDict();
    std::string* number = card ? card->FindString("card_number") : nullptr;
    std::u16string digits;
    if (number) {
      digits.reserve(number->size());
      for (char c : *number)
        if (c != ' ' && c != '-') digits.push_back(static_cast<unsigned char>(c));
      Wipe(number);
    }
    if (digits.empty()) {
      WarnOnce(batch, "Safari payment cards without a card number were skipped.");
      continue;
    }
    Autofill entry;
    entry.kind = Autofill::Kind::kCard;
    entry.fields["number"] = std::move(digits);
    if (const std::string* name = card->FindString("cardholder_name"))
      entry.fields["name"] = base::UTF8ToUTF16(*name);
    if (const std::string* nickname = card->FindString("card_name"))
      entry.fields["nickname"] = base::UTF8ToUTF16(*nickname);
    const std::optional<int> month = card->FindInt("card_expiration_month");
    if (month && *month >= 1 && *month <= 12) entry.fields["month"] = base::NumberToString16(*month);
    const std::optional<int> year = card->FindInt("card_expiration_year");
    if (year && *year >= 1000 && *year <= 9999) entry.fields["year"] = base::NumberToString16(*year);
    batch.autofill.push_back(std::move(entry));
  }
  if (Cancelled(cancel)) {
    for (auto& entry : batch.autofill) {
      auto& digits = entry.fields["number"];
      std::fill(digits.begin(), digits.end(), u'\0');
    }
    return Failure(kAutofill, "Import was cancelled.");
  }
  batch.success = true;
  return batch;
}

Batch ReadHistory(const ReadOptions& options, const Cancellation& cancel) {
  const auto exported = options.profile_path.AppendASCII("History.json");
  if (!base::PathExists(options.profile_path.AppendASCII("History.db")) && base::PathExists(exported))
    return ReadExportedHistory(exported, cancel);
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
}

Batch ReadSafariCategory(const ReadOptions& options, uint32_t category,
                         const Cancellation& cancel) {
  @autoreleasepool {
    if (Cancelled(cancel)) return Failure(category, "Import was cancelled.");
    if (options.family != Family::kSafari || !options.profile_path.IsAbsolute())
      return Failure(category, "The selected Safari source is invalid.");
    if (category == kBookmarks) return ReadBookmarks(options, cancel);
    if (category == kHistory) return ReadHistory(options, cancel);
    if (category == kAutofill) return ReadExportedCards(options, cancel);
    return Failure(category, "This category is not supported by the Safari reader. Use the supported browser export flow when available.");
  }
}
}
