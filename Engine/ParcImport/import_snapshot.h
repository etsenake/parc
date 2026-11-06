// Copyright 2026 Parc contributors.
#pragma once
#include <string>
#include <string_view>
#include "base/files/file_path.h"
#include "base/files/scoped_temp_dir.h"
#include "third_party/sqlite/sqlite3.h"
namespace parc::importer {
// Never opens a user's database with SQLite. The database and optional WAL are
// copied, retrying while a live browser writes. The private copy is opened only
// when both files are unchanged through the copy; a still-changing source is
// refused instead of importing a torn snapshot.
class SnapshotDatabase {
 public:
  SnapshotDatabase();
  ~SnapshotDatabase();
  SnapshotDatabase(const SnapshotDatabase&) = delete;
  SnapshotDatabase& operator=(const SnapshotDatabase&) = delete;
  bool Open(const base::FilePath& path);
  sqlite3* get() const { return database_; }
  const std::string& error() const { return error_; }
 private:
  base::ScopedTempDir temporary_;
  sqlite3* database_ = nullptr;
  std::string error_;
};
class Statement {
 public:
  Statement(sqlite3*, const std::string& sql);
  ~Statement();
  Statement(const Statement&) = delete;
  Statement& operator=(const Statement&) = delete;
  bool Step();
  bool valid() const { return statement_ != nullptr; }
  bool done() const { return result_ == SQLITE_DONE; }
  std::string Text(int column) const;
  std::u16string Text16(int column) const;
  std::string Blob(int column) const;
  int64_t Int(int column) const;
  double Double(int column) const;
 private:
  sqlite3_stmt* statement_ = nullptr;
  int result_ = SQLITE_OK;
};
bool HasTable(sqlite3*, std::string_view table);
bool HasColumn(sqlite3*, std::string_view table, std::string_view column);
}  // namespace parc::importer
