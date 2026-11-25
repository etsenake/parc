// Copyright 2026 Parc contributors.
#include <CommonCrypto/CommonCryptor.h>
#include <CommonCrypto/CommonHMAC.h>
#include <CommonCrypto/CommonKeyDerivation.h>
#include <fcntl.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>
#include <array>
#include <cerrno>
#include <limits>
#include <map>
#include <set>
#include <tuple>
#include "base/base64.h"
#include "base/files/file_enumerator.h"
#include "base/files/file_util.h"
#include "base/files/scoped_file.h"
#include "base/posix/eintr_wrapper.h"
#include "base/strings/string_util.h"
#include "base/threading/platform_thread.h"
#include "base/time/time.h"
#include "parc/importer/import_reader.h"
namespace parc::importer {
namespace {
constexpr size_t kMaxSession = 64 * 1024 * 1024;
constexpr size_t kMaxDatabase = 128 * 1024 * 1024;
constexpr size_t kMaxExecutable = 512 * 1024 * 1024;
constexpr size_t kMaxSaltKeys = 4096;
constexpr uint32_t kSessionSignature = 0x53534E53;
constexpr uint32_t kPlainSessionVersion = 3;
constexpr uint32_t kEncryptedSessionVersion = 5;
constexpr size_t kPage = 4096;
constexpr size_t kReserve = 80;
constexpr size_t kIV = 16;
constexpr size_t kHMAC = 64;
constexpr size_t kSalt = 16;
constexpr size_t kWalHeader = 32;
constexpr size_t kFrameHeader = 24;
constexpr uint32_t kWalMagic = 0x377f0682;
constexpr uint32_t kWalVersion = 3007000;
constexpr size_t kBase64Key = 43;
constexpr std::array<uint8_t, 32> kDiaSaltKey{
    0x88, 0xe7, 0xb5, 0x51, 0xef, 0xd7, 0xb6, 0x89, 0xdb, 0x89, 0xe1,
    0x3f, 0xe6, 0x6d, 0x67, 0x02, 0x07, 0xb0, 0xbd, 0x64, 0x25, 0x78,
    0xf1, 0xd1, 0x70, 0xa9, 0xe8, 0x53, 0x5d, 0x04, 0xc8, 0xe3};
constexpr char kCancelled[] = "Import was cancelled.";
constexpr char kDamagedDatabase[] =
    "The Dia tab database is damaged or incomplete.";
using Key = std::array<uint8_t, 32>;
bool Stopped(const Cancellation& stop) {
  return stop && stop->load();
}
template <typename T>
void Wipe(T& bytes) {
  std::fill(bytes.begin(), bytes.end(), 0);
}
uint32_t Little32(std::string_view bytes, size_t offset) {
  const auto* p = reinterpret_cast<const uint8_t*>(bytes.data() + offset);
  return uint32_t{p[0]} | uint32_t{p[1]} << 8 | uint32_t{p[2]} << 16 |
         uint32_t{p[3]} << 24;
}
uint32_t Big32(const uint8_t* p) {
  return uint32_t{p[0]} << 24 | uint32_t{p[1]} << 16 | uint32_t{p[2]} << 8 |
         uint32_t{p[3]};
}
uint32_t Word(const uint8_t* p, bool big) {
  return big ? Big32(p)
             : uint32_t{p[0]} | uint32_t{p[1]} << 8 | uint32_t{p[2]} << 16 |
                   uint32_t{p[3]} << 24;
}
void PutLittle(std::string& out, uint32_t value, size_t bytes) {
  for (size_t i = 0; i < bytes; ++i)
    out.push_back(static_cast<char>((value >> (8 * i)) & 0xff));
}
bool SameFile(const struct stat& a, const struct stat& b) {
  return a.st_dev == b.st_dev && a.st_ino == b.st_ino &&
         a.st_size == b.st_size &&
         a.st_mtimespec.tv_sec == b.st_mtimespec.tv_sec &&
         a.st_mtimespec.tv_nsec == b.st_mtimespec.tv_nsec &&
         a.st_ctimespec.tv_sec == b.st_ctimespec.tv_sec &&
         a.st_ctimespec.tv_nsec == b.st_ctimespec.tv_nsec;
}
enum class Read { kRead, kMissing, kChanged, kRefused };
Read ReadFile(const base::FilePath& path,
              size_t limit,
              std::string& bytes,
              struct stat& info) {
  bytes.clear();
  base::ScopedFD file(HANDLE_EINTR(
      open(path.value().c_str(), O_RDONLY | O_NOFOLLOW | O_CLOEXEC)));
  if (!file.is_valid())
    return errno == ENOENT ? Read::kMissing : Read::kRefused;
  if (fstat(file.get(), &info) != 0 || !S_ISREG(info.st_mode) ||
      info.st_size < 0 || static_cast<uint64_t>(info.st_size) > limit)
    return Read::kRefused;
  bytes.resize(static_cast<size_t>(info.st_size));
  size_t done = 0;
  while (done < bytes.size()) {
    const ssize_t count = HANDLE_EINTR(
        read(file.get(), bytes.data() + done, bytes.size() - done));
    if (count < 0)
      return Read::kRefused;
    if (count == 0)
      return Read::kChanged;
    done += static_cast<size_t>(count);
  }
  return Read::kRead;
}
bool Unchanged(const base::FilePath& path, const struct stat& before) {
  struct stat now{};
  return lstat(path.value().c_str(), &now) == 0 && SameFile(before, now);
}
bool Absent(const base::FilePath& path) {
  struct stat now{};
  return lstat(path.value().c_str(), &now) != 0 && errno == ENOENT;
}
bool SessionName(std::string_view name) {
  for (std::string_view prefix : {"Session_", "Tabs_", "Apps_"}) {
    if (!name.starts_with(prefix))
      continue;
    const auto digits = name.substr(prefix.size());
    return !digits.empty() && digits.size() <= 20 &&
           digits.find_first_not_of("0123456789") == std::string_view::npos;
  }
  return false;
}
bool PlainSession(std::string_view in,
                  std::string_view key,
                  std::string& out,
                  std::string& error,
                  const Cancellation& stop) {
  if (in.size() < 8 || Little32(in, 0) != kSessionSignature ||
      Little32(in, 4) != kEncryptedSessionVersion) {
    error = "The encrypted session file has an unsupported format.";
    return false;
  }
  out.clear();
  out.reserve(in.size());
  PutLittle(out, kSessionSignature, 4);
  PutLittle(out, kPlainSessionVersion, 4);
  size_t offset = 8;
  bool decoded = false;
  while (in.size() - offset >= 4) {
    if (Stopped(stop)) {
      Wipe(out);
      error = kCancelled;
      return false;
    }
    const uint32_t size = Little32(in, offset);
    if (size == 0 || size > in.size() - offset - 4)
      break;
    auto plain = DecryptChromiumValue(in.substr(offset + 4, size), key);
    offset += 4 + size;
    if (!plain || plain->empty() ||
        plain->size() > std::numeric_limits<uint16_t>::max()) {
      if (plain)
        Wipe(*plain);
      if (decoded)
        break;
      Wipe(out);
      error = "The session file could not be decrypted.";
      return false;
    }
    PutLittle(out, static_cast<uint32_t>(plain->size()), 2);
    out += *plain;
    Wipe(*plain);
    decoded = true;
  }
  return true;
}
struct PageKeys {
  PageKeys() = default;
  PageKeys(const PageKeys&) = delete;
  PageKeys& operator=(const PageKeys&) = delete;
  ~PageKeys() {
    Wipe(cipher);
    Wipe(mac);
  }
  Key cipher{};
  Key mac{};
};
void Hmac256(const void* key,
             size_t key_size,
             std::string_view message,
             uint8_t* out) {
  CCHmac(kCCHmacAlgSHA256, key, key_size, message.data(), message.size(), out);
}
Key DiaKey(std::string_view root_key,
           std::string_view folder,
           const Key& salt_key) {
  const std::string label = "profile/" + std::string(folder) + "/tabs";
  Key salt{}, prk{}, key{};
  Hmac256(salt_key.data(), salt_key.size(), label, salt.data());
  Hmac256(salt.data(), salt.size(), root_key, prk.data());
  Hmac256(prk.data(), prk.size(), label + '\x01', key.data());
  Wipe(prk);
  return key;
}
bool PageAuthentic(const uint8_t* page, uint32_t number, const PageKeys& keys) {
  const size_t offset = number == 1 ? kSalt : 0;
  const size_t size = kPage - offset - kReserve;
  const uint8_t index[4] = {
      static_cast<uint8_t>(number), static_cast<uint8_t>(number >> 8),
      static_cast<uint8_t>(number >> 16), static_cast<uint8_t>(number >> 24)};
  CCHmacContext context;
  CCHmacInit(&context, kCCHmacAlgSHA512, keys.mac.data(), keys.mac.size());
  CCHmacUpdate(&context, page + offset, size + kIV);
  CCHmacUpdate(&context, index, sizeof(index));
  std::array<uint8_t, kHMAC> digest{};
  CCHmacFinal(&context, digest.data());
  return timingsafe_bcmp(digest.data(), page + offset + size + kIV, kHMAC) ==
         0;
}
bool DecryptPage(const uint8_t* page,
                 uint32_t number,
                 const PageKeys& keys,
                 uint8_t* out) {
  if (!PageAuthentic(page, number, keys))
    return false;
  const size_t offset = number == 1 ? kSalt : 0;
  const size_t size = kPage - offset - kReserve;
  size_t moved = 0;
  if (CCCrypt(kCCDecrypt, kCCAlgorithmAES, 0, keys.cipher.data(),
              keys.cipher.size(), page + offset + size, page + offset, size,
              out + offset, size, &moved) != kCCSuccess ||
      moved != size)
    return false;
  if (number == 1)
    memcpy(out, "SQLite format 3", kSalt);
  memset(out + kPage - kReserve, 0, kReserve);
  return true;
}
bool HeaderValid(const uint8_t* page) {
  return page[16] == 0x10 && page[17] == 0x00 &&
         page[20] == static_cast<uint8_t>(kReserve) && page[21] == 64 &&
         page[22] == 32 && page[23] == 32;
}
bool OpensFirstPage(const uint8_t* first,
                    std::string_view root_key,
                    std::string_view folder,
                    const Key& salt_key,
                    PageKeys& keys) {
  keys.cipher = DiaKey(root_key, folder, salt_key);
  std::array<uint8_t, kSalt> salt{};
  for (size_t i = 0; i < kSalt; ++i)
    salt[i] = first[i] ^ 0x3a;
  if (CCKeyDerivationPBKDF(kCCPBKDF2,
                           reinterpret_cast<const char*>(keys.cipher.data()),
                           keys.cipher.size(), salt.data(), salt.size(),
                           kCCPRFHmacAlgSHA512, 2, keys.mac.data(),
                           keys.mac.size()) != kCCSuccess)
    return false;
  std::array<uint8_t, kPage> page{};
  const bool opened = DecryptPage(first, 1, keys, page.data()) &&
                      HeaderValid(page.data());
  Wipe(page);
  return opened;
}
bool Base64Character(uint8_t c) {
  return base::IsAsciiAlphaNumeric(c) || c == '+' || c == '/';
}
std::vector<Key> SaltKeysIn(const base::FilePath& app,
                            const Cancellation& stop) {
  std::vector<Key> keys;
  if (app.empty())
    return keys;
  std::set<std::string> seen;
  base::FileEnumerator files(app.Append("Contents").Append("MacOS"), false,
                             base::FileEnumerator::FILES);
  std::vector<uint8_t> chunk(4 * 1024 * 1024);
  for (auto path = files.Next(); !path.empty(); path = files.Next()) {
    base::ScopedFD file(HANDLE_EINTR(
        open(path.value().c_str(), O_RDONLY | O_NOFOLLOW | O_CLOEXEC)));
    struct stat info{};
    if (!file.is_valid() || fstat(file.get(), &info) != 0 ||
        !S_ISREG(info.st_mode) ||
        static_cast<uint64_t>(info.st_size) > kMaxExecutable)
      continue;
    std::string run, candidate;
    bool overflow = false, pending = false;
    ssize_t count = 0;
    while ((count = HANDLE_EINTR(read(file.get(), chunk.data(), chunk.size()))) >
           0) {
      if (Stopped(stop))
        return keys;
      for (ssize_t i = 0; i < count; ++i) {
        const uint8_t c = chunk[i];
        if (pending) {
          pending = false;
          std::string decoded;
          if (!Base64Character(c) && c != '=' &&
              seen.insert(candidate).second &&
              base::Base64Decode(candidate + "=", &decoded) &&
              decoded.size() == std::tuple_size_v<Key>) {
            Key key{};
            std::copy(decoded.begin(), decoded.end(), key.begin());
            keys.push_back(key);
            if (keys.size() >= kMaxSaltKeys)
              return keys;
          }
        }
        if (Base64Character(c)) {
          if (!overflow) {
            run.push_back(static_cast<char>(c));
            if (run.size() > kBase64Key) {
              overflow = true;
              run.clear();
            }
          }
          continue;
        }
        if (c == '=' && !overflow && run.size() == kBase64Key) {
          candidate = run;
          pending = true;
        }
        run.clear();
        overflow = false;
      }
    }
  }
  return keys;
}
struct Wal {
  std::map<uint32_t, size_t> frames;
  uint32_t pages = 0;
};
void Checksum(bool big,
              const uint8_t* data,
              size_t size,
              uint32_t& first,
              uint32_t& second) {
  for (size_t i = 0; i + 8 <= size; i += 8) {
    first += Word(data + i, big) + second;
    second += Word(data + i + 4, big) + first;
  }
}
Wal CommittedFrames(std::string_view wal) {
  Wal result;
  const auto* data = reinterpret_cast<const uint8_t*>(wal.data());
  if (wal.size() < kWalHeader)
    return result;
  const uint32_t magic = Big32(data);
  if ((magic & ~1u) != kWalMagic || Big32(data + 4) != kWalVersion ||
      Big32(data + 8) != kPage)
    return result;
  const bool big = magic & 1;
  uint32_t first = 0, second = 0;
  Checksum(big, data, 24, first, second);
  if (first != Big32(data + 24) || second != Big32(data + 28))
    return result;
  const uint32_t salt1 = Big32(data + 16), salt2 = Big32(data + 20);
  std::map<uint32_t, size_t> pending;
  for (size_t offset = kWalHeader;
       wal.size() - offset >= kFrameHeader + kPage;
       offset += kFrameHeader + kPage) {
    const uint8_t* frame = data + offset;
    const uint32_t page = Big32(frame), commit = Big32(frame + 4);
    if (page == 0 || Big32(frame + 8) != salt1 || Big32(frame + 12) != salt2)
      break;
    Checksum(big, frame, 8, first, second);
    Checksum(big, frame + kFrameHeader, kPage, first, second);
    if (first != Big32(frame + 16) || second != Big32(frame + 20))
      break;
    pending[page] = offset + kFrameHeader;
    if (commit) {
      for (const auto& [number, at] : pending)
        result.frames[number] = at;
      pending.clear();
      result.pages = commit;
    }
  }
  return result;
}
bool DiaDatabase(std::string_view main,
                 std::string_view wal,
                 const ReadOptions& options,
                 std::string_view folder,
                 std::string& out,
                 std::string& error,
                 const Cancellation& stop) {
  if (main.size() % kPage) {
    error = kDamagedDatabase;
    return false;
  }
  const auto committed = CommittedFrames(wal);
  const size_t stored = main.size() / kPage;
  const size_t pages = committed.pages ? committed.pages : stored;
  const auto* database = reinterpret_cast<const uint8_t*>(main.data());
  const auto* log = reinterpret_cast<const uint8_t*>(wal.data());
  auto page_at = [&](uint32_t number) -> const uint8_t* {
    if (auto frame = committed.frames.find(number);
        frame != committed.frames.end())
      return log + frame->second;
    return number <= stored ? database + (number - 1) * kPage : nullptr;
  };
  const uint8_t* first = page_at(1);
  if (!pages || pages > kMaxDatabase / kPage || !first) {
    error = pages > kMaxDatabase / kPage
                ? "The Dia tab database exceeds supported limits."
                : "The Dia tab database is empty.";
    return false;
  }
  PageKeys keys;
  bool opened =
      OpensFirstPage(first, options.source_key, folder, kDiaSaltKey, keys);
  if (!opened) {
    for (const auto& salt_key : SaltKeysIn(options.app_path, stop)) {
      if (Stopped(stop))
        break;
      if (salt_key != kDiaSaltKey &&
          OpensFirstPage(first, options.source_key, folder, salt_key, keys)) {
        opened = true;
        break;
      }
    }
  }
  if (Stopped(stop)) {
    error = kCancelled;
    return false;
  }
  if (!opened) {
    error = "The Dia tab database could not be decrypted.";
    return false;
  }
  out.assign(pages * kPage, '\0');
  auto* plain = reinterpret_cast<uint8_t*>(out.data());
  for (uint32_t number = 1; number <= pages; ++number) {
    const uint8_t* page = page_at(number);
    if (Stopped(stop) || !page ||
        !DecryptPage(page, number, keys, plain + (number - 1) * kPage)) {
      Wipe(out);
      out.clear();
      error = Stopped(stop) ? kCancelled : kDamagedDatabase;
      return false;
    }
  }
  if (!HeaderValid(plain)) {
    Wipe(out);
    out.clear();
    error = kDamagedDatabase;
    return false;
  }
  plain[18] = 1;
  plain[19] = 1;
  return true;
}
bool ReadDatabase(const base::FilePath& path,
                  std::string& main,
                  std::string& wal,
                  std::string& error) {
  const base::FilePath sidecar(path.value() + "-wal");
  for (int attempt = 0; attempt < 8; ++attempt) {
    struct stat main_info{}, wal_info{};
    const Read database = ReadFile(path, kMaxDatabase, main, main_info);
    Read log = Read::kChanged;
    if (database == Read::kRead)
      log = ReadFile(sidecar, kMaxDatabase, wal, wal_info);
    if (database == Read::kMissing || database == Read::kRefused ||
        log == Read::kRefused) {
      error = database == Read::kMissing
                  ? "The Dia tab database is missing."
                  : "The Dia tab database is unavailable or exceeds "
                    "supported limits.";
      return false;
    }
    if (database == Read::kRead && log != Read::kChanged &&
        Unchanged(path, main_info) &&
        (log == Read::kMissing ? Absent(sidecar)
                               : Unchanged(sidecar, wal_info)))
      return true;
    if (attempt < 7)
      base::PlatformThread::Sleep(base::Milliseconds(25 * (attempt + 1)));
  }
  error =
      "The Dia tab database changed while it was being read. Try again in a "
      "moment.";
  return false;
}
}
DecryptedFile DecryptSidebarFile(const ReadOptions& options,
                                 const base::FilePath& file,
                                 SidebarFormat format,
                                 const Cancellation& stop) {
  DecryptedFile result;
  if (options.family != Family::kChromium ||
      !options.profile_path.IsAbsolute() || !file.IsAbsolute() ||
      file.ReferencesParent()) {
    result.error = "The source profile is invalid.";
    return result;
  }
  if (options.source_key.size() != kCCKeySizeAES128) {
    result.error = "The source browser's encryption key is unavailable.";
    return result;
  }
  const auto profile = base::MakeAbsoluteFilePath(options.profile_path);
  const auto parent = base::MakeAbsoluteFilePath(file.DirName());
  const auto name = file.BaseName().value();
  const bool placed =
      !profile.empty() && !parent.empty() &&
      (format == SidebarFormat::kDiaTabs
           ? parent == profile && name == kDiaTabs
           : parent.DirName() == profile &&
                 parent.BaseName().value() == kChromiumEncryptedSessions &&
                 SessionName(name));
  if (!placed) {
    result.error = "The requested file is not part of the source profile.";
    return result;
  }
  const auto path = parent.Append(name);
  std::string plain;
  bool decrypted = false;
  if (format == SidebarFormat::kChromiumSession) {
    std::string encrypted;
    struct stat info{};
    const Read status = ReadFile(path, kMaxSession, encrypted, info);
    if (status != Read::kRead)
      result.error = status == Read::kMissing
                         ? "The session file is missing."
                         : "The session file is unavailable or exceeds "
                           "supported limits.";
    else
      decrypted = PlainSession(encrypted, options.source_key, plain,
                               result.error, stop);
  } else {
    std::string main, wal;
    if (ReadDatabase(path, main, wal, result.error))
      decrypted = DiaDatabase(main, wal, options, profile.BaseName().value(),
                              plain, result.error, stop);
  }
  if (decrypted && Stopped(stop)) {
    decrypted = false;
    result.error = kCancelled;
  }
  if (decrypted) {
    result.success = true;
    result.data.assign(plain.begin(), plain.end());
  }
  Wipe(plain);
  return result;
}
}
