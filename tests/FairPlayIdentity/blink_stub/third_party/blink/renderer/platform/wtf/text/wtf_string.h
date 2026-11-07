// Stand-in for Blink's WTF::String with only what
// Engine/ParcRenderer/parc_safari_identity.h calls, over ASCII std::string,
// for tests/FairPlayIdentity/renderer_gate_main.cc.
#ifndef PARC_TESTS_BLINK_STUB_WTF_STRING_H_
#define PARC_TESTS_BLINK_STUB_WTF_STRING_H_

#include <cctype>
#include <string>
#include <vector>

namespace blink {

class String {
 public:
  String() = default;
  String(const char* characters) : value_(characters) {}  // NOLINT
  explicit String(std::string value) : value_(std::move(value)) {}

  bool empty() const { return value_.empty(); }
  bool contains(const char* text) const {
    return value_.find(text) != std::string::npos;
  }
  bool starts_with(const char* text) const { return value_.rfind(text, 0) == 0; }
  std::vector<String> Split(char separator) const {
    std::vector<String> parts;
    std::string::size_type start = 0;
    while (true) {
      const std::string::size_type end = value_.find(separator, start);
      if (end != start) {
        parts.emplace_back(value_.substr(start, end - start));
      }
      if (end == std::string::npos) {
        return parts;
      }
      start = end + 1;
    }
  }
  String StripWhiteSpace() const {
    std::string::size_type start = 0;
    std::string::size_type end = value_.size();
    while (start < end && std::isspace(static_cast<unsigned char>(value_[start]))) {
      ++start;
    }
    while (end > start && std::isspace(static_cast<unsigned char>(value_[end - 1]))) {
      --end;
    }
    return String(value_.substr(start, end - start));
  }
  bool operator==(const char* other) const { return value_ == other; }
  const std::string& str() const { return value_; }

 private:
  std::string value_;
};

inline bool EqualIgnoringAsciiCase(const String& a, const char* b) {
  const std::string& value = a.str();
  std::string::size_type i = 0;
  for (; i < value.size() && b[i]; ++i) {
    if (std::tolower(static_cast<unsigned char>(value[i])) !=
        std::tolower(static_cast<unsigned char>(b[i]))) {
      return false;
    }
  }
  return i == value.size() && !b[i];
}

}  // namespace blink

#endif  // PARC_TESTS_BLINK_STUB_WTF_STRING_H_
