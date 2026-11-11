#import <Foundation/Foundation.h>

#include <unistd.h>

#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <string>
#include <thread>
#include <vector>

#include "probe_wire.h"

namespace {

fpsb::HttpResponse Fetch(const fpsb::HttpRequest& r) {
  NSMutableURLRequest* request =
      [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@(r.url.c_str())]];
  request.HTTPMethod = @(r.method.c_str());
  if (!r.body.empty()) request.HTTPBody = [NSData dataWithBytes:r.body.data() length:r.body.size()];
  request.timeoutInterval = 30;
  for (const auto& [name, value] : r.headers) {
    [request setValue:@(value.c_str()) forHTTPHeaderField:@(name.c_str())];
  }
  __block fpsb::HttpResponse result;
  dispatch_semaphore_t done = dispatch_semaphore_create(0);
  [[[NSURLSession sharedSession]
      dataTaskWithRequest:request
        completionHandler:^(NSData* data, NSURLResponse* response, NSError* error) {
          NSHTTPURLResponse* http = (NSHTTPURLResponse*)response;
          result.status = http.statusCode;
          const uint8_t* bytes = static_cast<const uint8_t*>(data.bytes);
          result.body.assign(bytes, bytes + data.length);
          if (NSString* header = http.allHeaderFields[@"X-AxDRM-ErrorMessage"]) {
            result.error_header = header.UTF8String;
          }
          if (error) result.error = error.localizedDescription.UTF8String;
          dispatch_semaphore_signal(done);
        }] resume];
  dispatch_semaphore_wait(done, DISPATCH_TIME_FOREVER);
  return result;
}

std::string HeaderValue(const fpsb::Headers& headers, const std::string& name) {
  for (const auto& [n, v] : headers) {
    if (n == name) return v;
  }
  return "";
}

uint64_t RangeLength(const std::string& range) {
  unsigned long long first = 0, last = 0;
  if (std::sscanf(range.c_str(), "bytes=%llu-%llu", &first, &last) != 2 || last < first) return 0;
  return last - first + 1;
}

}

int main(int argc, char** argv) {
  if (argc != 3) return 2;
  const int fd = std::atoi(argv[1]);
  NSString* cache_dir = @(argv[2]);
  const pid_t parent = getppid();
  std::thread([parent] {
    while (getppid() == parent) std::this_thread::sleep_for(std::chrono::seconds(1));
    _exit(0);
  }).detach();
  [[NSFileManager defaultManager] createDirectoryAtPath:cache_dir
                            withIntermediateDirectories:YES
                                             attributes:nil
                                                  error:nil];
  while (true) {
    @autoreleasepool {
      std::vector<uint8_t> message;
      fpsb::HttpRequest request;
      if (!fpsb::ReceiveMessage(fd, &message)) return 0;
      if (!fpsb::DecodeRequest(message, &request)) return 2;
      const std::string cache_key = HeaderValue(request.headers, "X-Fpsb-Cache");
      std::erase_if(request.headers, [](const auto& h) { return h.first == "X-Fpsb-Cache"; });
      NSString* cache_path = nil;
      if (request.method == "GET" && !cache_key.empty()) {
        cache_path = [cache_dir stringByAppendingPathComponent:@(cache_key.c_str())];
        if (NSData* cached = [NSData dataWithContentsOfFile:cache_path]) {
          fpsb::HttpResponse hit;
          hit.status = 200;
          const uint8_t* bytes = static_cast<const uint8_t*>(cached.bytes);
          hit.body.assign(bytes, bytes + cached.length);
          if (!fpsb::SendMessage(fd, fpsb::EncodeResponse(hit))) return 0;
          continue;
        }
      }
      fpsb::HttpResponse response = Fetch(request);
      const uint64_t range_length = RangeLength(HeaderValue(request.headers, "Range"));
      const bool complete = response.error.empty() &&
                            (range_length ? response.status == 206 && response.body.size() == range_length
                                          : response.status == 200 && !response.body.empty());
      if (cache_path && complete) {
        [[NSData dataWithBytes:response.body.data() length:response.body.size()] writeToFile:cache_path
                                                                                   atomically:YES];
      }
      if (!fpsb::SendMessage(fd, fpsb::EncodeResponse(response))) return 0;
    }
  }
}
