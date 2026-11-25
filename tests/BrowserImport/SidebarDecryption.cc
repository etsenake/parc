#include <CommonCrypto/CommonCryptor.h>
#include <CommonCrypto/CommonHMAC.h>
#include <CommonCrypto/CommonKeyDerivation.h>
#include <array>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include "base/base64.h"
#include "base/files/file_util.h"
#include "base/files/scoped_temp_dir.h"
#include "parc/importer/import_reader.h"
#include "sql/initialization.h"
#include "third_party/sqlite/sqlite3.h"
namespace {
using parc::importer::Cancellation;
using parc::importer::DecryptedFile;
using parc::importer::DecryptSidebarFile;
using parc::importer::Family;
using parc::importer::ReadOptions;
using parc::importer::SidebarFormat;
using Key = std::array<uint8_t, 32>;
constexpr size_t kPage = 4096;
constexpr size_t kReserve = 80;
constexpr size_t kSalt = 16;
constexpr size_t kIV = 16;
int checks = 0;
void Require(bool yes, const char* message) {
  ++checks;
  if (!yes) {
    fprintf(stderr, "FAILED: %s\n", message);
    exit(1);
  }
}
void SQL(sqlite3* db, const char* text) {
  char* error = nullptr;
  if (sqlite3_exec(db, text, nullptr, nullptr, &error) != SQLITE_OK) {
    fprintf(stderr, "SQL: %s\n", error);
    sqlite3_free(error);
    exit(1);
  }
}
std::string Bytes(const base::FilePath& path) {
  std::string data;
  Require(base::ReadFileToString(path, &data), "fixture bytes");
  return data;
}
void Write(const base::FilePath& path, std::string_view data) {
  Require(base::WriteFile(path, data), "fixture file");
}
base::FilePath Directory(const base::FilePath& path) {
  Require(base::CreateDirectory(path), "fixture directory");
  return path;
}
std::string Hex(const uint8_t* data, size_t size) {
  constexpr char kDigits[] = "0123456789abcdef";
  std::string hex;
  for (size_t i = 0; i < size; ++i) {
    hex.push_back(kDigits[data[i] >> 4]);
    hex.push_back(kDigits[data[i] & 0xf]);
  }
  return hex;
}
void PutLittle(std::string& out, uint32_t value, size_t bytes) {
  for (size_t i = 0; i < bytes; ++i)
    out.push_back(static_cast<char>((value >> (8 * i)) & 0xff));
}
uint32_t Big32(const uint8_t* p) {
  return uint32_t{p[0]} << 24 | uint32_t{p[1]} << 16 | uint32_t{p[2]} << 8 |
         uint32_t{p[3]};
}
void PutBig(uint8_t* p, uint32_t value) {
  p[0] = value >> 24;
  p[1] = value >> 16;
  p[2] = value >> 8;
  p[3] = value;
}
std::string EncryptValue(std::string_view value, std::string_view key) {
  std::array<char, 16> iv;
  iv.fill(' ');
  std::string encrypted(value.size() + 32, '\0');
  size_t count = 0;
  Require(CCCrypt(kCCEncrypt, kCCAlgorithmAES, kCCOptionPKCS7Padding,
                  key.data(), key.size(), iv.data(), value.data(), value.size(),
                  encrypted.data(), encrypted.size(), &count) == kCCSuccess,
          "fixture value encryption");
  encrypted.resize(count);
  return "v10" + encrypted;
}
std::string RootKey(std::string_view secret, int rounds) {
  std::array<uint8_t, kCCKeySizeAES128> key;
  const char salt[] = "saltysalt";
  Require(CCKeyDerivationPBKDF(kCCPBKDF2, secret.data(), secret.size(),
                               reinterpret_cast<const uint8_t*>(salt),
                               sizeof(salt) - 1, kCCPRFHmacAlgSHA1, rounds,
                               key.data(), key.size()) == kCCSuccess,
          "Safe Storage key derivation");
  return std::string(reinterpret_cast<const char*>(key.data()), key.size());
}
DecryptedFile Decrypt(const base::FilePath& profile,
                      std::string_view key,
                      const base::FilePath& file,
                      SidebarFormat format,
                      const Cancellation& stop) {
  ReadOptions options;
  options.family = Family::kChromium;
  options.profile_path = profile;
  options.source_key = std::string(key);
  return DecryptSidebarFile(options, file, format, stop);
}
std::string Plain(const DecryptedFile& file) {
  return std::string(file.data.begin(), file.data.end());
}
void Sessions(const base::FilePath& root, const Cancellation& stop) {
  const std::string key = "0123456789abcdef";
  const auto profile = Directory(root.AppendASCII("Default"));
  const auto folder = Directory(profile.AppendASCII("Sessions_Encrypted"));
  struct Command {
    uint8_t id;
    std::string payload;
    bool fallback;
  };
  const std::vector<Command> commands = {
      {9, std::string("\x01\x00\x00\x00\x00\x00\x00\x00", 8), false},
      {255, "", false},
      {12, std::string("\x01\x00\x00\x00\x01", 5), true},
      {6, std::string(300, 'x'), false},
  };
  std::string encrypted, expected;
  PutLittle(encrypted, 0x53534E53, 4);
  PutLittle(encrypted, 5, 4);
  PutLittle(expected, 0x53534E53, 4);
  PutLittle(expected, 3, 4);
  for (const auto& command : commands) {
    const std::string plain = static_cast<char>(command.id) + command.payload;
    const std::string sealed =
        EncryptValue(plain, command.fallback ? RootKey("", 1) : key);
    PutLittle(encrypted, static_cast<uint32_t>(sealed.size()), 4);
    encrypted += sealed;
    PutLittle(expected, static_cast<uint32_t>(plain.size()), 2);
    expected += plain;
  }
  const auto session = folder.AppendASCII("Session_13350000000000000");
  Write(session, encrypted + std::string("\x40\x00\x00", 3));
  const auto original = Bytes(session);
  auto result =
      Decrypt(profile, key, session, SidebarFormat::kChromiumSession, stop);
  Require(result.success && Plain(result) == expected,
          "encrypted session becomes the plain SNSS stream");
  Require(Bytes(session) == original, "encrypted session untouched");
  result = Decrypt(profile, "fedcba9876543210", session,
                   SidebarFormat::kChromiumSession, stop);
  Require(!result.success && result.data.empty(),
          "a wrong key refuses the session");
  const auto plain_version = folder.AppendASCII("Tabs_13350000000000001");
  std::string old = encrypted;
  old[4] = 3;
  Write(plain_version, old);
  Require(!Decrypt(profile, key, plain_version,
                   SidebarFormat::kChromiumSession, stop)
               .success,
          "only the encrypted session version is accepted");
  const auto stray = Directory(profile.AppendASCII("Sessions"))
                         .AppendASCII("Session_13350000000000000");
  Write(stray, encrypted);
  Require(!Decrypt(profile, key, stray, SidebarFormat::kChromiumSession, stop)
               .success,
          "a session outside Sessions_Encrypted is refused");
  const auto named = folder.AppendASCII("Current Session");
  Write(named, encrypted);
  Require(!Decrypt(profile, key, named, SidebarFormat::kChromiumSession, stop)
               .success,
          "an unexpected session file name is refused");
  const auto other = Directory(root.AppendASCII("Profile 1"));
  Require(!Decrypt(other, key, session, SidebarFormat::kChromiumSession, stop)
               .success,
          "a session from another profile is refused");
}
void Hmac256(const void* key, size_t size, std::string_view data, uint8_t* out) {
  CCHmac(kCCHmacAlgSHA256, key, size, data.data(), data.size(), out);
}
Key DiaKey(std::string_view root_key, std::string_view folder) {
  std::string salt_key;
  Require(base::Base64Decode("iOe1Ue/XtonbieE/5m1nAgewvWQlePHRcKnoU10EyOM=",
                             &salt_key) &&
              salt_key.size() == 32,
          "published Dia salt key");
  const std::string label = "profile/" + std::string(folder) + "/tabs";
  Key salt{}, prk{}, key{};
  Hmac256(salt_key.data(), salt_key.size(), label, salt.data());
  Hmac256(salt.data(), salt.size(), root_key, prk.data());
  Hmac256(prk.data(), prk.size(), label + '\x01', key.data());
  return key;
}
struct Cipher {
  Key key{};
  Key mac{};
  std::string salt;
};
Cipher MakeCipher(const Key& key, std::string_view salt) {
  Cipher cipher;
  cipher.key = key;
  cipher.salt = std::string(salt);
  std::array<uint8_t, kSalt> mixed;
  for (size_t i = 0; i < kSalt; ++i)
    mixed[i] = static_cast<uint8_t>(salt[i]) ^ 0x3a;
  Require(CCKeyDerivationPBKDF(kCCPBKDF2,
                               reinterpret_cast<const char*>(key.data()),
                               key.size(), mixed.data(), mixed.size(),
                               kCCPRFHmacAlgSHA512, 2, cipher.mac.data(),
                               cipher.mac.size()) == kCCSuccess,
          "SQLCipher HMAC key derivation");
  return cipher;
}
std::string SealPage(std::string_view plain, uint32_t number,
                     const Cipher& cipher) {
  Require(plain.size() == kPage, "whole plaintext page");
  std::string page(plain);
  auto* out = reinterpret_cast<uint8_t*>(page.data());
  const auto* in = reinterpret_cast<const uint8_t*>(plain.data());
  const size_t offset = number == 1 ? kSalt : 0;
  const size_t size = kPage - offset - kReserve;
  std::array<uint8_t, kIV> iv;
  for (size_t i = 0; i < kIV; ++i)
    iv[i] = static_cast<uint8_t>(number * 31 + i * 7);
  size_t moved = 0;
  Require(CCCrypt(kCCEncrypt, kCCAlgorithmAES, 0, cipher.key.data(),
                  cipher.key.size(), iv.data(), in + offset, size,
                  out + offset, size, &moved) == kCCSuccess &&
              moved == size,
          "SQLCipher page encryption");
  memcpy(out + offset + size, iv.data(), kIV);
  const uint8_t index[4] = {
      static_cast<uint8_t>(number), static_cast<uint8_t>(number >> 8),
      static_cast<uint8_t>(number >> 16), static_cast<uint8_t>(number >> 24)};
  CCHmacContext context;
  CCHmacInit(&context, kCCHmacAlgSHA512, cipher.mac.data(), cipher.mac.size());
  CCHmacUpdate(&context, out + offset, size + kIV);
  CCHmacUpdate(&context, index, sizeof(index));
  CCHmacFinal(&context, out + offset + size + kIV);
  if (number == 1)
    memcpy(out, cipher.salt.data(), kSalt);
  return page;
}
std::string SealDatabase(std::string_view plain, const Cipher& cipher) {
  Require(plain.size() % kPage == 0, "whole plaintext database");
  std::string sealed;
  for (size_t i = 0; i < plain.size() / kPage; ++i)
    sealed += SealPage(plain.substr(i * kPage, kPage),
                       static_cast<uint32_t>(i + 1), cipher);
  return sealed;
}
void Checksum(bool big, const uint8_t* data, size_t size, uint32_t& first,
              uint32_t& second) {
  for (size_t i = 0; i + 8 <= size; i += 8) {
    const uint32_t a =
        big ? Big32(data + i)
            : uint32_t{data[i]} | uint32_t{data[i + 1]} << 8 |
                  uint32_t{data[i + 2]} << 16 | uint32_t{data[i + 3]} << 24;
    const uint32_t b =
        big ? Big32(data + i + 4)
            : uint32_t{data[i + 4]} | uint32_t{data[i + 5]} << 8 |
                  uint32_t{data[i + 6]} << 16 | uint32_t{data[i + 7]} << 24;
    first += a + second;
    second += b + first;
  }
}
std::string SealWal(std::string_view plain, const Cipher& cipher) {
  Require(plain.size() >= 32, "plaintext WAL header");
  std::string sealed(plain.substr(0, 32));
  const auto* header = reinterpret_cast<const uint8_t*>(plain.data());
  const bool big = Big32(header) & 1;
  uint32_t first = Big32(header + 24), second = Big32(header + 28);
  for (size_t offset = 32; offset + 24 + kPage <= plain.size();
       offset += 24 + kPage) {
    std::string frame(plain.substr(offset, 24));
    const uint32_t number =
        Big32(reinterpret_cast<const uint8_t*>(frame.data()));
    const std::string page =
        SealPage(plain.substr(offset + 24, kPage), number, cipher);
    auto* head = reinterpret_cast<uint8_t*>(frame.data());
    Checksum(big, head, 8, first, second);
    Checksum(big, reinterpret_cast<const uint8_t*>(page.data()), kPage, first,
             second);
    PutBig(head + 16, first);
    PutBig(head + 20, second);
    sealed += frame + page;
  }
  return sealed;
}
std::string Titles(const DecryptedFile& file, const base::FilePath& scratch) {
  const auto copy = scratch.AppendASCII("opened.db");
  base::DeleteFile(copy);
  Write(copy, Plain(file));
  sqlite3* db = nullptr;
  Require(sqlite3_open_v2(copy.value().c_str(), &db, SQLITE_OPEN_READONLY,
                          nullptr) == SQLITE_OK,
          "decrypted database opens");
  sqlite3_stmt* query = nullptr;
  Require(sqlite3_prepare_v2(db,
                             "SELECT group_concat(title, ',') FROM (SELECT "
                             "title FROM spaces ORDER BY id)",
                             -1, &query, nullptr) == SQLITE_OK &&
              sqlite3_step(query) == SQLITE_ROW,
          "decrypted spaces query");
  const auto* text = sqlite3_column_text(query, 0);
  std::string titles = text ? reinterpret_cast<const char*>(text) : "";
  sqlite3_finalize(query);
  sqlite3_close(db);
  return titles;
}
void DiaTabs(const base::FilePath& root, const Cancellation& stop) {
  const std::string root_key = RootKey("synthetic-dia-safe-storage-secret", 1003);
  Require(Hex(reinterpret_cast<const uint8_t*>(root_key.data()),
              root_key.size()) == "7797c8b7a074125d621c7a9a446293a1",
          "Safe Storage root key matches the research vector");
  const Key key = DiaKey(root_key, "Default");
  Require(Hex(key.data(), key.size()) ==
              "6f54effc655b9c0a0af0f3fcaeafe12471ef99b824cde109e894e04dbb82de92",
          "tabs key matches the research vector");
  const auto scratch = Directory(root.AppendASCII("scratch"));
  const auto source = scratch.AppendASCII("plain.db");
  sql::EnsureSqliteInitialized(false);
  sqlite3* db = nullptr;
  Require(sqlite3_open(source.value().c_str(), &db) == SQLITE_OK,
          "plaintext fixture database");
  SQL(db, "PRAGMA page_size=4096;");
  int reserve = static_cast<int>(kReserve);
  Require(sqlite3_file_control(db, "main", SQLITE_FCNTL_RESERVE_BYTES,
                               &reserve) == SQLITE_OK,
          "SQLCipher reserve bytes");
  SQL(db,
      "PRAGMA journal_mode=WAL;PRAGMA wal_autocheckpoint=0;"
      "CREATE TABLE spaces(id TEXT,title TEXT);"
      "CREATE TABLE tabs(id TEXT,url TEXT);"
      "INSERT INTO spaces VALUES('s1','Home');"
      "INSERT INTO tabs VALUES('t1','https://example.test/');"
      "PRAGMA wal_checkpoint(TRUNCATE);"
      "INSERT INTO spaces VALUES('s2','Work');");
  const std::string plain_main = Bytes(source);
  const std::string plain_wal =
      Bytes(base::FilePath(source.value() + "-wal"));
  sqlite3_close(db);
  Require(plain_main.size() == 3 * kPage &&
              static_cast<uint8_t>(plain_main[20]) == static_cast<uint8_t>(kReserve),
          "three-page plaintext with SQLCipher's reserve");
  Require(plain_wal.size() > 32 + 24 + kPage, "uncheckpointed WAL frames");
  const Cipher cipher =
      MakeCipher(key, std::string("fixture-kdf-salt", kSalt));
  const auto profile = Directory(root.AppendASCII("Dia/Default"));
  Write(profile.AppendASCII("Preferences"), "{}");
  const auto tabs = profile.AppendASCII("tabs.db");
  const auto wal = base::FilePath(tabs.value() + "-wal");
  const std::string sealed_main = SealDatabase(plain_main, cipher);
  const std::string sealed_wal = SealWal(plain_wal, cipher);
  Write(tabs, sealed_main);
  Write(wal, sealed_wal);
  auto result = Decrypt(profile, root_key, tabs, SidebarFormat::kDiaTabs, stop);
  Require(result.success && result.data.size() == 3 * kPage,
          "SQLCipher database with WAL decrypts");
  Require(Plain(result).starts_with(std::string("SQLite format 3\0", 16)) &&
              result.data[18] == 1 && result.data[19] == 1,
          "plaintext header opens without a WAL");
  Require(Titles(result, scratch) == "Home,Work",
          "committed WAL frames are folded in");
  Require(Bytes(tabs) == sealed_main && Bytes(wal) == sealed_wal,
          "encrypted database and WAL untouched");
  Write(wal, sealed_wal + sealed_wal.substr(32, 24 + kPage / 2));
  result = Decrypt(profile, root_key, tabs, SidebarFormat::kDiaTabs, stop);
  Require(result.success && Titles(result, scratch) == "Home,Work",
          "a torn trailing frame is ignored");
  std::string foreign = sealed_wal;
  foreign[32 + 8] ^= 0x55;
  Write(wal, foreign);
  result = Decrypt(profile, root_key, tabs, SidebarFormat::kDiaTabs, stop);
  Require(result.success && Titles(result, scratch) == "Home",
          "frames from another WAL generation are ignored");
  base::DeleteFile(wal);
  result = Decrypt(profile, root_key, tabs, SidebarFormat::kDiaTabs, stop);
  Require(result.success && Titles(result, scratch) == "Home",
          "a database without a WAL decrypts");
  result = Decrypt(profile, RootKey("another secret", 1003), tabs,
                   SidebarFormat::kDiaTabs, stop);
  Require(!result.success && result.data.empty(), "a wrong key is refused");
  std::string tampered = sealed_main;
  tampered[2 * kPage + 100] ^= 0x01;
  Write(tabs, tampered);
  result = Decrypt(profile, root_key, tabs, SidebarFormat::kDiaTabs, stop);
  Require(!result.success && result.data.empty(),
          "a page failing its HMAC is refused");
  Write(tabs, sealed_main);
  const auto renamed = profile.AppendASCII("other.db");
  Write(renamed, sealed_main);
  Require(!Decrypt(profile, root_key, renamed, SidebarFormat::kDiaTabs, stop)
               .success,
          "only tabs.db is read");
  const auto nested = Directory(profile.AppendASCII("nested"));
  Write(nested.AppendASCII("tabs.db"), sealed_main);
  Require(!Decrypt(profile, root_key, nested.AppendASCII("tabs.db"),
                   SidebarFormat::kDiaTabs, stop)
               .success,
          "a tabs.db outside the profile folder is refused");
  const auto linked = Directory(root.AppendASCII("Dia/Linked"));
  Require(base::CreateSymbolicLink(tabs, linked.AppendASCII("tabs.db")),
          "fixture symbolic link");
  Require(!Decrypt(linked, root_key, linked.AppendASCII("tabs.db"),
                   SidebarFormat::kDiaTabs, stop)
               .success,
          "a symbolic link is refused");
  const auto other = Directory(root.AppendASCII("Dia/Profile 7"));
  Write(other.AppendASCII("tabs.db"), sealed_main);
  Require(!Decrypt(other, root_key, other.AppendASCII("tabs.db"),
                   SidebarFormat::kDiaTabs, stop)
               .success,
          "another profile's label cannot open the database");
  stop->store(true);
  Require(!Decrypt(profile, root_key, tabs, SidebarFormat::kDiaTabs, stop)
               .success,
          "cancelled reads return nothing");
  stop->store(false);
}
}
int main() {
  base::ScopedTempDir temp;
  Require(temp.CreateUniqueTempDir(), "isolated root");
  auto stop = std::make_shared<std::atomic_bool>(false);
  Sessions(temp.GetPath().AppendASCII("Chrome"), stop);
  DiaTabs(temp.GetPath(), stop);
  printf("PASS: %d sidebar decryption checks\n", checks);
  return 0;
}
