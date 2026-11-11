// Copyright 2026 Parc contributors.
#include "parc/importer/import_snapshot.h"
#include <array>
#include <optional>
#include <cerrno>
#include <sys/stat.h>
#include "base/files/file_util.h"
#include "base/strings/utf_string_conversions.h"
#include "base/threading/platform_thread.h"
#include "base/time/time.h"
#include "sql/initialization.h"
namespace parc::importer {
namespace {
struct Identity { bool known = false; bool exists = false; struct stat info {}; };
Identity Identify(const base::FilePath& path) {
  Identity result;
  if (stat(path.value().c_str(), &result.info) == 0) {
    result.known = true;
    result.exists = true;
  } else {
    result.known = errno == ENOENT || errno == ENOTDIR;
  }
  return result;
}
bool Same(const Identity& a, const Identity& b) {
  return a.known && b.known && a.exists == b.exists && (!a.exists ||
      (a.info.st_dev == b.info.st_dev && a.info.st_ino == b.info.st_ino &&
       a.info.st_size == b.info.st_size &&
       a.info.st_mtimespec.tv_sec == b.info.st_mtimespec.tv_sec &&
       a.info.st_mtimespec.tv_nsec == b.info.st_mtimespec.tv_nsec &&
       a.info.st_ctimespec.tv_sec == b.info.st_ctimespec.tv_sec &&
       a.info.st_ctimespec.tv_nsec == b.info.st_ctimespec.tv_nsec));
}
}
SnapshotDatabase::SnapshotDatabase() = default;
SnapshotDatabase::~SnapshotDatabase() { if (database_) sqlite3_close(database_); }
bool SnapshotDatabase::Open(const base::FilePath& path) {
  if (database_ || !temporary_.CreateUniqueTempDir()) {
    error_ = "The import snapshot could not be created."; return false;
  }
  // SQLite sidecars append their suffix directly.
  const base::FilePath sidecar(path.value() + FILE_PATH_LITERAL("-wal"));
  const std::array<base::FilePath, 2> files{path, sidecar};
  auto destination = [&](const base::FilePath& file) {
    return temporary_.GetPath().Append(file.BaseName());
  };
  bool copied = false;
  for (int attempt = 0; attempt < 8; ++attempt) {
    const std::array<Identity, 2> before{Identify(path), Identify(sidecar)};
    if (!before[0].known || !before[1].known || !before[0].exists ||
        !S_ISREG(before[0].info.st_mode) ||
        (before[1].exists && !S_ISREG(before[1].info.st_mode))) {
      error_ = "The source database is unavailable or access is restricted.";
      return false;
    }
    bool copied_files = true;
    for (size_t i = 0; i < files.size(); ++i) {
      const auto target = destination(files[i]);
      base::DeleteFile(target);
      if (!before[i].exists)
        continue;
      if (!base::CopyFile(files[i], target)) {
        copied_files = false;
        break;
      }
    }
    if (copied_files && Same(before[0], Identify(path)) &&
        Same(before[1], Identify(sidecar))) {
      copied = true;
      break;
    }
    if (attempt < 7)
      base::PlatformThread::Sleep(base::Milliseconds(25 * (attempt + 1)));
  }
  if (!copied) {
    error_ = "The source database changed while it was being copied. Close the browser and try again.";
    return false;
  }
  const auto copy = destination(path);
  // Chromium's bundled SQLite omits automatic initialization. Only the owned
  // copy is writable, so SQLite may recover its copied WAL and create its SHM.
  sql::EnsureSqliteInitialized(false);
  if (sqlite3_open_v2(copy.value().c_str(), &database_, SQLITE_OPEN_READWRITE | SQLITE_OPEN_NOMUTEX, nullptr) != SQLITE_OK) {
    error_ = "The source database could not be opened."; return false;
  }
  sqlite3_busy_timeout(database_, 1000);
  return true;
}
Statement::Statement(sqlite3* db, const std::string& sql) {
  if (sqlite3_prepare_v2(db, sql.c_str(), -1, &statement_, nullptr) != SQLITE_OK) {
    if (statement_) sqlite3_finalize(statement_); statement_ = nullptr;
  }
}
Statement::~Statement() { if (statement_) sqlite3_finalize(statement_); }
bool Statement::Step() { result_ = statement_ ? sqlite3_step(statement_) : SQLITE_ERROR; return result_ == SQLITE_ROW; }
std::string Statement::Text(int column) const {
  const auto* value = sqlite3_column_text(statement_, column);
  return value ? std::string(reinterpret_cast<const char*>(value), sqlite3_column_bytes(statement_, column)) : std::string();
}
std::u16string Statement::Text16(int column) const { return base::UTF8ToUTF16(Text(column)); }
std::string Statement::Blob(int column) const {
  const auto* value = sqlite3_column_blob(statement_, column);
  return value ? std::string(static_cast<const char*>(value), sqlite3_column_bytes(statement_, column)) : std::string();
}
int64_t Statement::Int(int column) const { return sqlite3_column_int64(statement_, column); }
double Statement::Double(int column) const { return sqlite3_column_double(statement_, column); }
bool HasTable(sqlite3* db, std::string_view table) {
  Statement s(db, "SELECT name FROM sqlite_master WHERE type='table'");
  while (s.Step()) if (s.Text(0) == table) return true;
  return false;
}
bool HasColumn(sqlite3* db, std::string_view table, std::string_view column) {
  // Callers supply source-owned constant table identifiers, never SQL input.
  if (table.find_first_not_of("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_") != std::string_view::npos) return false;
  Statement s(db, "PRAGMA table_info(" + std::string(table) + ")");
  while (s.Step()) if (s.Text(1) == column) return true;
  return false;
}
}  // namespace parc::importer
