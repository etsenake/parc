#ifndef PARC_TESTS_BLINK_STUB_WTF_STRING_H_
#define PARC_TESTS_BLINK_STUB_WTF_STRING_H_

#include <cctype>
#include <cstdint>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace blink {

using wtf_size_t = std::size_t;
using UChar = char16_t;
using StringView = std::string_view;
template <typename T>
using Vector = std::vector<T>;

class String {
 public:
  String() = default;
  String(const char* characters) : value_(characters) {}  // NOLINT
  explicit String(std::string value) : value_(std::move(value)) {}

  bool empty() const { return value_.empty(); }
  wtf_size_t length() const { return value_.size(); }
  UChar operator[](wtf_size_t at) const { return value_.at(at); }
  String substr(wtf_size_t start) const { return String(value_.substr(start)); }
  static String Number(uint64_t value) { return String(std::to_string(value)); }
  friend String operator+(const char* prefix, const String& suffix) {
    return String(prefix + suffix.value_);
  }
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
  template <typename Finder>
  Vector<String> SplitSkippingEmpty(Finder finder) const {
    Vector<String> parts;
    wtf_size_t start = 0;
    for (wtf_size_t at = 0; at < length();) {
      if (const auto size = finder(StringView(value_), at)) {
        if (at > start) {
          parts.emplace_back(value_.substr(start, at - start));
        }
        at += *size;
        start = at;
      } else {
        ++at;
      }
    }
    if (start < length()) {
      parts.emplace_back(value_.substr(start));
    }
    return parts;
  }
  template <typename Predicate>
  String StripWhiteSpace(Predicate predicate) const {
    std::string::size_type start = 0;
    std::string::size_type end = value_.size();
    while (start < end && predicate(static_cast<UChar>(value_[start]))) {
      ++start;
    }
    while (end > start && predicate(static_cast<UChar>(value_[end - 1]))) {
      --end;
    }
    return String(value_.substr(start, end - start));
  }
  String StripWhiteSpace() const {
    return StripWhiteSpace([](UChar c) { return std::isspace(c); });
  }
  bool operator==(const char* other) const { return value_ == other; }
  const std::string& str() const { return value_; }

 private:
  std::string value_;
};

inline const String g_empty_string;

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

}

#endif
