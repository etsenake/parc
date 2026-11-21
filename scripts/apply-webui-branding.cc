#include <fstream>
#include <iostream>
#include <iterator>
#include <string>
#include <string_view>

#include "webui_branding_rules.h"

int main(int argc, char** argv) {
  using namespace parc::branding;
  if (argc == 2 && std::string_view(argv[1]) == "--list") {
    for (const auto& edits : kResourceEdits) std::cout << edits.resource << '\n';
    return 0;
  }
  if (argc != 3) {
    std::cerr << "usage: apply-webui-branding --list | RESOURCE INPUT\n";
    return 2;
  }
  const auto* edits = FindResourceEdits(argv[1]);
  std::ifstream input(argv[2], std::ios::binary);
  if (!edits || !input) {
    std::cerr << "unknown resource or unreadable input: " << argv[1] << " " << argv[2] << '\n';
    return 2;
  }
  std::string text{std::istreambuf_iterator<char>(input), std::istreambuf_iterator<char>()};
  const auto outcome = ApplyResourceEdits(text, *edits);
  for (auto group : outcome.failed) std::cerr << argv[1] << ": missing " << group << '\n';
  std::cout << text;
  return outcome.failed.empty() ? 0 : 1;
}
