#ifndef PARC_TESTS_FAIRPLAY_SANDBOX_PROBE_WIRE_H_
#define PARC_TESTS_FAIRPLAY_SANDBOX_PROBE_WIRE_H_

#include <arpa/inet.h>
#include <unistd.h>

#include <cstdint>
#include <cstdlib>
#include <string>
#include <utility>
#include <vector>

namespace fpsb {

using Headers = std::vector<std::pair<std::string, std::string>>;

struct HttpRequest {
  std::string method;
  std::string url;
  Headers headers;
  std::vector<uint8_t> body;
};

struct HttpResponse {
  long status = 0;
  std::string error;
  std::string error_header;
  std::vector<uint8_t> body;
};

inline bool WriteAll(int fd, const void* data, size_t size) {
  const uint8_t* p = static_cast<const uint8_t*>(data);
  while (size) {
    ssize_t n = write(fd, p, size);
    if (n <= 0) return false;
    p += n;
    size -= size_t(n);
  }
  return true;
}

inline bool ReadAll(int fd, void* data, size_t size) {
  uint8_t* p = static_cast<uint8_t*>(data);
  while (size) {
    ssize_t n = read(fd, p, size);
    if (n <= 0) return false;
    p += n;
    size -= size_t(n);
  }
  return true;
}

inline bool SendMessage(int fd, const std::vector<uint8_t>& payload) {
  uint32_t length = htonl(uint32_t(payload.size()));
  return WriteAll(fd, &length, 4) && WriteAll(fd, payload.data(), payload.size());
}

inline bool ReceiveMessage(int fd, std::vector<uint8_t>* payload) {
  uint32_t length = 0;
  if (!ReadAll(fd, &length, 4)) return false;
  length = ntohl(length);
  if (length > 256u * 1024 * 1024) return false;
  payload->resize(length);
  return ReadAll(fd, payload->data(), length);
}

inline std::string OneLine(std::string s) {
  for (char& c : s) {
    if (c == '\n' || c == '\r') c = ' ';
  }
  return s;
}

inline bool NextLine(const std::vector<uint8_t>& data, size_t* pos, std::string* line) {
  for (size_t i = *pos; i < data.size(); ++i) {
    if (data[i] == '\n') {
      line->assign(data.begin() + long(*pos), data.begin() + long(i));
      *pos = i + 1;
      return true;
    }
  }
  return false;
}

inline std::vector<uint8_t> EncodeRequest(const HttpRequest& r) {
  std::string head = r.method + " " + OneLine(r.url) + "\n";
  for (const auto& [name, value] : r.headers) head += OneLine(name) + ": " + OneLine(value) + "\n";
  head += "\n";
  std::vector<uint8_t> out(head.begin(), head.end());
  out.insert(out.end(), r.body.begin(), r.body.end());
  return out;
}

inline bool DecodeRequest(const std::vector<uint8_t>& data, HttpRequest* r) {
  size_t pos = 0;
  std::string line;
  if (!NextLine(data, &pos, &line)) return false;
  size_t space = line.find(' ');
  if (space == std::string::npos) return false;
  r->method = line.substr(0, space);
  r->url = line.substr(space + 1);
  while (true) {
    if (!NextLine(data, &pos, &line)) return false;
    if (line.empty()) break;
    size_t colon = line.find(": ");
    if (colon == std::string::npos) return false;
    r->headers.emplace_back(line.substr(0, colon), line.substr(colon + 2));
  }
  r->body.assign(data.begin() + long(pos), data.end());
  return true;
}

inline std::vector<uint8_t> EncodeResponse(const HttpResponse& r) {
  std::string head = std::to_string(r.status) + "\n" + OneLine(r.error) + "\n" + OneLine(r.error_header) + "\n";
  std::vector<uint8_t> out(head.begin(), head.end());
  out.insert(out.end(), r.body.begin(), r.body.end());
  return out;
}

inline bool DecodeResponse(const std::vector<uint8_t>& data, HttpResponse* r) {
  size_t pos = 0;
  std::string status;
  if (!NextLine(data, &pos, &status) || !NextLine(data, &pos, &r->error) ||
      !NextLine(data, &pos, &r->error_header)) {
    return false;
  }
  r->status = std::strtol(status.c_str(), nullptr, 10);
  r->body.assign(data.begin() + long(pos), data.end());
  return true;
}

}

#endif
