// Copyright 2026 Parc contributors.
#ifndef PARC_PAGE_PREFERENCES_H_
#define PARC_PAGE_PREFERENCES_H_
namespace content { class WebContents; }
namespace blink::web_pref { struct WebPreferences; }
namespace parc {
bool SetPageInWindow(content::WebContents&, bool);
void SetMediaPowerRestricted(content::WebContents&, bool);
void ApplyPagePreferences(content::WebContents&, blink::web_pref::WebPreferences&);
}
#endif
