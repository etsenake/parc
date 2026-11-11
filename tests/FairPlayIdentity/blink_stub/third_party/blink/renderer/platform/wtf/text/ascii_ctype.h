#ifndef PARC_TESTS_BLINK_STUB_ASCII_CTYPE_H_
#define PARC_TESTS_BLINK_STUB_ASCII_CTYPE_H_

namespace blink {
template <typename T>
inline bool IsAsciiSpace(T c) {
  return c == ' ' || (c >= '\t' && c <= '\r');
}
template <typename T>
inline bool IsAsciiDigit(T c) {
  return c >= '0' && c <= '9';
}
template <typename T>
inline bool IsAsciiHexDigit(T c) {
  return IsAsciiDigit(c) || (c >= 'a' && c <= 'f') ||
         (c >= 'A' && c <= 'F');
}
template <typename T>
inline unsigned ToAsciiHexValue(T c) {
  return IsAsciiDigit(c) ? c - '0' : (c | 0x20) - 'a' + 10;
}
}

#endif
