#include "native_password_file.h"
#include <cassert>
#include <fstream>
#include <iostream>
#include <filesystem>
#include <string>
#include <vector>
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
  expect(kMaximumBytes > 1000 * 1024 && kChunkBytes == 1000 * 1024 && kChunkRows == 3000);
  auto pieces = [](const std::string& csv, const Chunks& chunks) {
    std::vector<std::string> out;
    for (const auto& [begin, end] : chunks.ranges) out.push_back(csv.substr(0, chunks.header) + csv.substr(begin, end - begin));
    return out;
  };
  auto covers = [](const std::string& csv, const Chunks& chunks) {
    size_t next = chunks.header;
    for (const auto& [begin, end] : chunks.ranges) {
      if (begin != next || end <= begin) return false;
      size_t quotes = 0;
      for (size_t i = 0; i < begin; ++i) quotes += csv[i] == '"';
      if (csv[begin - 1] != '\n' || quotes % 2) return false;
      next = end;
    }
    return next == csv.size() || (chunks.ranges.empty() && chunks.header == csv.size());
  };
  const std::string header = "name,url,username,password,note\r\n";
  std::string rows;
  for (int i = 0; i < 10; ++i)
    rows += "Site " + std::to_string(i) + ",https://site" + std::to_string(i) + ".example.invalid/,user,made-up-" +
        std::to_string(i) + ",\"note with \"\"quotes\"\"\nand a second line\"\r\n";
  auto split = Split(header + rows, kChunkBytes, 3);
  expect(split.header == header.size() && split.ranges.size() == 4 && covers(header + rows, split));
  auto parts = pieces(header + rows, split);
  expect(parts[0].rfind(header, 0) == 0 && parts[3].rfind(header, 0) == 0);
  expect(parts[0].find("made-up-2") != std::string::npos && parts[0].find("made-up-3") == std::string::npos);
  expect(parts[3].find("made-up-9") != std::string::npos);
  std::string joined;
  for (const auto& part : parts) joined += part.substr(header.size());
  expect(joined == rows);
  auto by_bytes = Split(header + rows, 95, kChunkRows);
  expect(by_bytes.ranges.size() == 10 && covers(header + rows, by_bytes));
  expect(covers(header + rows, Split(header + rows)) && Split(header + rows).ranges.size() == 1);
  const std::string unterminated = header + "A,https://a.example.invalid/,u,p\nB,https://b.example.invalid/,u,p";
  auto tail = Split(unterminated, kChunkBytes, 1);
  expect(tail.ranges.size() == 2 && tail.ranges.back().second == unterminated.size() && covers(unterminated, tail));
  const std::string open_quote = header + "A,https://a.example.invalid/,u,\"p\nB,https://b.example.invalid/,u,p\nC,x,y,z\n";
  auto quoted = Split(open_quote, kChunkBytes, 1);
  expect(quoted.ranges.size() == 1 && quoted.ranges[0].second == open_quote.size() && covers(open_quote, quoted));
  expect(Split("url,username,password").ranges.empty() && Split("url,username,password").header == 21);
  expect(Split("url,username,password\n").ranges.empty() && Split("url,username,password\n").header == 22);
  expect(Split("\"url\nusername\",password\nhttps://a.example.invalid/,p\n").header == 24);
  std::string many = header;
  for (int i = 0; i < 7000; ++i) many += "S,https://s" + std::to_string(i) + ".example.invalid/,u,made-up\n";
  auto large = Split(many);
  expect(large.ranges.size() == 3 && covers(many, large));
  write(p, many);
  auto read_large = Read(p.string());
  expect(read_large.identity.has_value() && read_large.bytes.size() > 0 && Split(read_large.bytes).ranges == large.ranges);
  fs::remove_all(root);
  std::cout << checks << " actual file-admission/identity assertions passed; synthetic files only.\n";
}
