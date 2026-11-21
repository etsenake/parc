#import "ParcNativeTest.h"
#include "native_password_file.h"
#include <fstream>
#include <filesystem>
#include <string>
#include <vector>
using namespace parc::password_file;
namespace fs = std::filesystem;

static void Write(const fs::path& path, const std::string& value) {
  std::ofstream file(path);
  file << value;
}

static std::vector<std::string> Pieces(const std::string& csv, const Chunks& chunks) {
  std::vector<std::string> out;
  for (const auto& [begin, end] : chunks.ranges) out.push_back(csv.substr(0, chunks.header) + csv.substr(begin, end - begin));
  return out;
}

static bool Covers(const std::string& csv, const Chunks& chunks) {
  size_t next = chunks.header;
  for (const auto& [begin, end] : chunks.ranges) {
    if (begin != next || end <= begin) return false;
    size_t quotes = 0;
    for (size_t i = 0; i < begin; ++i) quotes += csv[i] == '"';
    if (csv[begin - 1] != '\n' || quotes % 2) return false;
    next = end;
  }
  return next == csv.size() || (chunks.ranges.empty() && chunks.header == csv.size());
}

static const std::string kHeader = "name,url,username,password,note\r\n";

static std::string Rows() {
  std::string rows;
  for (int i = 0; i < 10; ++i)
    rows += "Site " + std::to_string(i) + ",https://site" + std::to_string(i) + ".example.invalid/,user,made-up-" +
            std::to_string(i) + ",\"note with \"\"quotes\"\"\nand a second line\"\r\n";
  return rows;
}

static std::string Many() {
  std::string many = kHeader;
  for (int i = 0; i < 7000; ++i) many += "S,https://s" + std::to_string(i) + ".example.invalid/,u,made-up\n";
  return many;
}

@interface ParcNativeTests_PasswordFileTests : ParcNativeTestCase
@end

@implementation ParcNativeTests_PasswordFileTests {
  fs::path _root;
  fs::path _file;
}

- (void)setUp {
  [super setUp];
  char name[] = "/tmp/parc-password-file.XXXXXX";
  char* directory = mkdtemp(name);
  XCTAssertNotEqual(directory, nullptr);
  _root = fs::path(directory);
  _file = _root / "Passwords.csv";
}

- (void)tearDown {
  fs::remove_all(_root);
  [super tearDown];
}

- (void)testAMissingFileHasNoIdentity {
  PARC_CHECK(!Read(_file.string()).identity);
}

- (void)testAnEmptyFileHasNoIdentity {
  Write(_file, "");
  PARC_CHECK(!Read(_file.string()).identity);
}

- (void)testAFileReadsWithAStableIdentity {
  Write(_file, "URL,Username,Password\nhttps://example.invalid,a,synthetic\n");
  auto original = Read(_file.string());
  PARC_CHECK(original.identity.has_value());
  PARC_CHECK(original.bytes.find("synthetic") != std::string::npos);
  PARC_CHECK(Read(_file.string()).identity == original.identity);
}

- (void)testTheDigestDistinguishesFiles {
  Write(_file, "URL,Username,Password\nhttps://example.invalid,a,synthetic\n");
  const auto identity = Read(_file.string()).identity.value();
  auto changed = identity;
  changed.digest[0] ^= 1;
  PARC_CHECK(changed != identity);
}

- (void)testTheInodeDistinguishesFiles {
  Write(_file, "URL,Username,Password\nhttps://example.invalid,a,synthetic\n");
  const auto identity = Read(_file.string()).identity.value();
  auto changed = identity;
  changed.inode++;
  PARC_CHECK(changed != identity);
}

- (void)testTheModificationTimeDistinguishesFiles {
  Write(_file, "URL,Username,Password\nhttps://example.invalid,a,synthetic\n");
  const auto identity = Read(_file.string()).identity.value();
  auto changed = identity;
  changed.modified.tv_nsec++;
  PARC_CHECK(changed != identity);
}

- (void)testTheSizeDistinguishesFiles {
  Write(_file, "URL,Username,Password\nhttps://example.invalid,a,synthetic\n");
  const auto identity = Read(_file.string()).identity.value();
  auto changed = identity;
  changed.size++;
  PARC_CHECK(changed != identity);
}

- (void)testTheDeviceDistinguishesFiles {
  Write(_file, "URL,Username,Password\nhttps://example.invalid,a,synthetic\n");
  const auto identity = Read(_file.string()).identity.value();
  auto changed = identity;
  changed.device++;
  PARC_CHECK(changed != identity);
}

- (void)testRewritingAFileChangesItsIdentity {
  Write(_file, "URL,Username,Password\nhttps://example.invalid,a,synthetic\n");
  auto original = Read(_file.string());
  Write(_file, "URL,Username,Password\nhttps://example.invalid,a,different\n");
  PARC_CHECK(Read(_file.string()).identity != original.identity);
}

- (void)testReplacingAFileWithIdenticalBytesChangesItsIdentity {
  Write(_file, "URL,Username,Password\nhttps://example.invalid,a,synthetic\n");
  auto original = Read(_file.string());
  fs::rename(_file, _root / "old.csv");
  Write(_file, original.bytes);
  PARC_CHECK(Read(_file.string()).identity != original.identity);
}

- (void)testSymbolicLinksAreRefused {
  Write(_file, "URL,Username,Password\n");
  fs::create_symlink(_file, _root / "alias.csv");
  PARC_CHECK(!Read((_root / "alias.csv").string()).identity);
}

- (void)testDirectoriesAreRefused {
  PARC_CHECK(!Read(_root.string()).identity);
}

- (void)testPipesAreRefused {
  auto pipe = _root / "pipe.csv";
  PARC_CHECK(!mkfifo(pipe.c_str(), 0600));
  PARC_CHECK(!Read(pipe.string()).identity);
}

- (void)testFilesOverTheSizeLimitAreRefused {
  Write(_file, std::string(kMaximumBytes + 1, 'x'));
  PARC_CHECK(!Read(_file.string()).identity);
}

- (void)testFilesAtTheSizeLimitAreAccepted {
  Write(_file, std::string(kMaximumBytes, 'x'));
  PARC_CHECK(Read(_file.string()).identity.has_value());
}

- (void)testRowLimitsSplitWholeQuotedRowsUnderTheHeader {
  const std::string rows = Rows();
  auto split = Split(kHeader + rows, kChunkBytes, 3);
  PARC_CHECK(split.header == kHeader.size() && split.ranges.size() == 4 && Covers(kHeader + rows, split));
  auto parts = Pieces(kHeader + rows, split);
  PARC_CHECK(parts[0].rfind(kHeader, 0) == 0 && parts[3].rfind(kHeader, 0) == 0);
  PARC_CHECK(parts[0].find("made-up-2") != std::string::npos && parts[0].find("made-up-3") == std::string::npos);
  PARC_CHECK(parts[3].find("made-up-9") != std::string::npos);
  std::string joined;
  for (const auto& part : parts) joined += part.substr(kHeader.size());
  PARC_CHECK(joined == rows);
}

- (void)testByteLimitsSplitBetweenRows {
  const std::string rows = Rows();
  auto by_bytes = Split(kHeader + rows, 95, kChunkRows);
  PARC_CHECK(by_bytes.ranges.size() == 10 && Covers(kHeader + rows, by_bytes));
}

- (void)testSmallFilesStayWhole {
  const std::string rows = Rows();
  PARC_CHECK(Covers(kHeader + rows, Split(kHeader + rows)) && Split(kHeader + rows).ranges.size() == 1);
}

- (void)testAnUnterminatedFinalRowKeepsItsBytes {
  const std::string unterminated = kHeader + "A,https://a.example.invalid/,u,p\nB,https://b.example.invalid/,u,p";
  auto tail = Split(unterminated, kChunkBytes, 1);
  PARC_CHECK(tail.ranges.size() == 2 && tail.ranges.back().second == unterminated.size() && Covers(unterminated, tail));
}

- (void)testAnOpenQuotedFieldStaysTogether {
  const std::string open_quote = kHeader + "A,https://a.example.invalid/,u,\"p\nB,https://b.example.invalid/,u,p\nC,x,y,z\n";
  auto quoted = Split(open_quote, kChunkBytes, 1);
  PARC_CHECK(quoted.ranges.size() == 1 && quoted.ranges[0].second == open_quote.size() && Covers(open_quote, quoted));
}

- (void)testAnUnterminatedHeaderHasNoRows {
  PARC_CHECK(Split("url,username,password").ranges.empty() && Split("url,username,password").header == 21);
}

- (void)testATerminatedHeaderHasNoRows {
  PARC_CHECK(Split("url,username,password\n").ranges.empty() && Split("url,username,password\n").header == 22);
}

- (void)testQuotedNewlinesRemainInTheHeader {
  PARC_CHECK(Split("\"url\nusername\",password\nhttps://a.example.invalid/,p\n").header == 24);
}

- (void)testALargeFileSplitsTheSameWhenReadFromDisk {
  const std::string many = Many();
  auto large = Split(many);
  PARC_CHECK(large.ranges.size() == 3 && Covers(many, large));
  Write(_file, many);
  auto read_large = Read(_file.string());
  PARC_CHECK(read_large.identity.has_value() && read_large.bytes.size() > 0 &&
             Split(read_large.bytes).ranges == large.ranges);
}

@end
