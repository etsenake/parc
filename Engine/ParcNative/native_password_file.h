// Copyright 2026 Parc contributors.
#pragma once
#include <CommonCrypto/CommonDigest.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>
#include <algorithm>
#include <array>
#include <cerrno>
#include <optional>
#include <string>
#include <string_view>
#include <utility>
#include <vector>
namespace parc::password_file {
constexpr size_t kMaximumBytes = 32 * 1024 * 1024;
constexpr size_t kChunkBytes = 1000 * 1024;
constexpr size_t kChunkRows = 3000;
struct Chunks {
  size_t header = 0;
  std::vector<std::pair<size_t, size_t>> ranges;
};
inline Chunks Split(std::string_view csv, size_t max_bytes = kChunkBytes, size_t max_rows = kChunkRows) {
  Chunks chunks;
  bool quoted = false, header = true;
  size_t start = 0, rows = 0;
  for (size_t i = 0; i < csv.size(); ++i) {
    if (csv[i] == '"') { quoted = !quoted; continue; }
    if (csv[i] != '\n' || quoted) continue;
    if (header) { header = false; chunks.header = start = i + 1; continue; }
    if (++rows >= max_rows || i + 1 - start >= max_bytes) {
      chunks.ranges.emplace_back(start, i + 1);
      start = i + 1; rows = 0;
    }
  }
  if (header) chunks.header = csv.size();
  else if (start < csv.size()) chunks.ranges.emplace_back(start, csv.size());
  return chunks;
}
struct Identity {
  dev_t device; ino_t inode; off_t size;
  timespec modified;
  std::array<unsigned char, CC_SHA256_DIGEST_LENGTH> digest;
  bool operator==(const Identity& other) const {
    return device == other.device && inode == other.inode && size == other.size &&
        modified.tv_sec == other.modified.tv_sec && modified.tv_nsec == other.modified.tv_nsec && digest == other.digest;
  }
};
struct ReadResult {
  std::string bytes;
  std::optional<Identity> identity;
  std::string error;
};
inline ReadResult Read(const std::string& path) {
  ReadResult result;
  const int fd = open(path.c_str(), O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK);
  if (fd < 0) { result.error = "The selected file could not be opened."; return result; }
  struct stat before = {}, after = {};
  if (fstat(fd, &before) || !S_ISREG(before.st_mode) || before.st_size <= 0 ||
      before.st_size > static_cast<off_t>(kMaximumBytes)) {
    close(fd); result.error = "Choose a nonempty CSV file no larger than 32 MB."; return result;
  }
  result.bytes.resize(before.st_size);
  size_t read_count = 0;
  while (read_count < result.bytes.size()) {
    const ssize_t count = read(fd, result.bytes.data() + read_count, result.bytes.size() - read_count);
    if (count < 0 && errno == EINTR) continue;
    if (count <= 0) break;
    read_count += count;
  }
  const bool unchanged = !fstat(fd, &after) && before.st_dev == after.st_dev && before.st_ino == after.st_ino &&
      before.st_size == after.st_size && before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec &&
      before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec;
  close(fd);
  if (!unchanged || read_count != result.bytes.size()) {
    std::fill(result.bytes.begin(), result.bytes.end(), 0); result.bytes.clear();
    result.error = "The selected file changed while it was being read. Choose it again."; return result;
  }
  Identity identity{before.st_dev, before.st_ino, before.st_size, before.st_mtimespec, {}};
  CC_SHA256(result.bytes.data(), static_cast<CC_LONG>(result.bytes.size()), identity.digest.data());
  result.identity = identity;
  return result;
}
}
