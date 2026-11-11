// Pure URL component checks. Does not create a browser, Profile or renderer.
#include "parc/native/native_internal_urls.h"
#include "url/origin.h"
#include "url/url_util.h"
#include <cstdio>
#include <cstdlib>

int main() {
  url::ScopedSchemeRegistryForTests registry;
  url::AddStandardScheme("chrome", url::SCHEME_WITH_HOST);
  url::AddStandardScheme("parc", url::SCHEME_WITH_HOST);
  unsigned checks = 0;
  auto expect = [&](bool ok, const char* label) {
    ++checks;
    if (!ok) { std::fprintf(stderr, "FAIL: %s\n", label); std::exit(1); }
  };
  for (const char* path : {"settings/", "password-manager/passwords", "extensions/", "flags/#item", "version/", "chrome-urls/", "settings/content?site=https%3A%2F%2Fexample.test%2Fa%3Fx%3D1#section"}) {
    const GURL visible(std::string("parc://") + path);
    const GURL actual = parc::CanonicalInternalURL(visible);
    expect(actual == GURL(std::string("chrome://") + path), "original components survive canonicalization");
    expect(parc::PublicInternalURL(actual) == visible, "public address round trip");
    expect(url::Origin::Create(actual).scheme() == "chrome", "controller origin remains Chromium");
    expect(parc::CanonicalInternalURL(actual) == actual, "canonicalization is idempotent");
  }
  for (const char* input : {"https://example.test/?next=chrome://settings/#chrome://flags", "chrome-untrusted://example/", "chrome://easel/not-a-uuid", "chrome-extension://abcdefghijklmnop/", "arc://settings/", "data:text/plain,chrome://settings/", "parc://easel/not-a-uuid", "parc://easel/550e8400-e29b-41d4-a716-446655440000?other=1"}) {
    const GURL url(input);
    expect(parc::CanonicalInternalURL(url) == url, "non-public or app-owned URL is untouched");
    expect(parc::PublicInternalURL(url) == url, "only actual chrome is projected");
  }
  expect(parc::IsNativeAppDocumentURL(GURL("PARC://easel/not-a-uuid")), "malformed Easel remains app-owned");
  expect(!parc::IsNativeAppDocumentURL(GURL("parc://settings/")), "WebUI is not an app document");
  expect(!parc::CanonicalInternalURL(GURL("arc://settings/")).SchemeIs("chrome"), "Arc is never an alias");
  std::printf("PASS: %u native internal URL assertions\n", checks);
}
