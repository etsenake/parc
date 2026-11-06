#include "native_password_file.h"
#include <cassert>
#include <fstream>
#include <iostream>
#include <filesystem>
int main() {
  using namespace parc::password_file;
  namespace fs = std::filesystem;
  char name[] = "/tmp/parc-password-file.XXXXXX";
  const auto root = fs::path(mkdtemp(name));
  int checks = 0;
  auto expect = [&](bool value) { ++checks; assert(value); };
  auto write = [&](const fs::path& p, const std::string& value) { std::ofstream f(p); f << value; };
  const auto p = root / "Passwords.csv";
  expect(!Read(p.string()).identity);
  write(p, ""); expect(!Read(p.string()).identity);
  write(p, "URL,Username,Password\nhttps://example.invalid,a,synthetic\n");
  auto original = Read(p.string()); expect(original.identity.has_value());
  expect(original.bytes.find("synthetic") != std::string::npos);
  expect(Read(p.string()).identity == original.identity);
  auto changed = original.identity.value(); changed.digest[0] ^= 1; expect(changed != original.identity.value());
  changed = original.identity.value(); changed.inode++; expect(changed != original.identity.value());
  changed = original.identity.value(); changed.modified.tv_nsec++; expect(changed != original.identity.value());
  changed = original.identity.value(); changed.size++; expect(changed != original.identity.value());
  changed = original.identity.value(); changed.device++; expect(changed != original.identity.value());
  write(p, "URL,Username,Password\nhttps://example.invalid,a,different\n");
  expect(Read(p.string()).identity != original.identity);
  fs::rename(p, root / "old.csv"); write(p, original.bytes);
  expect(Read(p.string()).identity != original.identity);
  fs::create_symlink(p, root / "alias.csv"); expect(!Read((root / "alias.csv").string()).identity);
  expect(!Read(root.string()).identity);
  auto pipe = root / "pipe.csv"; assert(!mkfifo(pipe.c_str(), 0600)); expect(!Read(pipe.string()).identity);
  write(p, std::string(kMaximumBytes + 1, 'x')); expect(!Read(p.string()).identity);
  write(p, std::string(kMaximumBytes, 'x')); expect(Read(p.string()).identity.has_value());
  fs::remove_all(root);
  std::cout << checks << " actual file-admission/identity assertions passed; synthetic files only.\n";
}
