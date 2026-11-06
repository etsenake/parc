// Public addresses are a presentation/navigation boundary, never WebUI origins.
#ifndef CEF_LIBCEF_BROWSER_PARC_NATIVE_NATIVE_INTERNAL_URLS_H_
#define CEF_LIBCEF_BROWSER_PARC_NATIVE_NATIVE_INTERNAL_URLS_H_

#include "url/gurl.h"

namespace parc {
inline constexpr char kInternalScheme[] = "parc";

// Easels and Notes are app-owned documents. Malformed app addresses must not
// be handed to Chromium as privileged chrome://easel or chrome://note URLs.
inline bool IsNativeAppDocumentURL(const GURL& url) {
  return url.SchemeIs(kInternalScheme) &&
         (url.host() == "easel" || url.host() == "note");
}

inline GURL CanonicalInternalURL(const GURL& url) {
  if (!url.is_valid() || !url.SchemeIs(kInternalScheme) ||
      IsNativeAppDocumentURL(url))
    return url;
  GURL::Replacements replacement;
  replacement.SetSchemeStr("chrome");
  return url.ReplaceComponents(replacement);
}

inline GURL PublicInternalURL(const GURL& url) {
  if (!url.is_valid() || !url.SchemeIs("chrome") || (url.host() == "easel" || url.host() == "note"))
    return url;
  GURL::Replacements replacement;
  replacement.SetSchemeStr(kInternalScheme);
  return url.ReplaceComponents(replacement);
}
}  // namespace parc
#endif
