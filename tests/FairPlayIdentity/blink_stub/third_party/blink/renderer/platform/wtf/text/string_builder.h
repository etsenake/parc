// Only the builder operations used by the real Safari identity header.
#ifndef PARC_TESTS_BLINK_STUB_STRING_BUILDER_H_
#define PARC_TESTS_BLINK_STUB_STRING_BUILDER_H_

#include "third_party/blink/renderer/platform/wtf/text/wtf_string.h"

namespace blink {
class StringBuilder {
 public:
  bool empty() const { return value_.empty(); }
  void Append(char c) { value_ += c; }
  void Append(const String& text) { value_ += text.str(); }
  String ToString() const { return String(value_); }

 private:
  std::string value_;
};
}  // namespace blink

#endif  // PARC_TESTS_BLINK_STUB_STRING_BUILDER_H_
