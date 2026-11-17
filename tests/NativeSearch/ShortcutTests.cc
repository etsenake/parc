#include <cstdio>
#include <optional>

#include "../../Engine/ParcNative/native_search_shortcuts.h"
#include "base/check.h"
#include "url/gurl.h"

namespace {
int checks = 0;
void Expect(bool value) {
  ++checks;
  CHECK(value);
}
constexpr char kPage[] = "https://okta.example.com/app";
bool Counts(std::optional<int> code,
            const char* destination = kPage,
            const char* visible = kPage,
            const char* redirect_origin = "",
            bool committed = true,
            bool primary_main_frame = true) {
  return parc::ShortcutNavigationCounts(primary_main_frame, committed, code,
                                        GURL(destination), GURL(visible),
                                        GURL(redirect_origin));
}
}

int main() {
  for (int code : {200, 203, 204, 299, 401, 407})
    Expect(Counts(code));
  for (int code : {0, 100, 199, 301, 304, 400, 403, 404, 408, 500, 503})
    Expect(!Counts(code));
  Expect(!Counts(std::nullopt));
  Expect(!Counts(200, kPage, kPage, "", false));
  Expect(!Counts(200, kPage, kPage, "", true, false));
  Expect(!Counts(200, "http://okta/", "http://search.isp.example/?q=okta",
                 "http://search.isp.example/"));
  Expect(!Counts(200, "http://okta/", "https://www.search.isp.example/results",
                 "http://search.isp.example/"));
  Expect(Counts(200, "http://okta/", "http://okta/", "http://search.isp.example/"));
  Expect(Counts(200, "http://search.isp.example/", "http://search.isp.example/?q=x",
                "http://search.isp.example/"));
  Expect(Counts(200, "http://okta.example.com/", "https://login.okta.example.com/",
                "http://search.isp.example/"));
  Expect(Counts(200, "http://okta/", "https://sso.corp.example/",
                "http://search.isp.example/"));
  Expect(Counts(200, "http://okta/", "http://search.isp.example/?q=okta"));
  std::printf("PASS: %d native search shortcut assertions\n", checks);
}
