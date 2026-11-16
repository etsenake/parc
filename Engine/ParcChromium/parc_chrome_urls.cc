// Copyright 2026 Parc contributors.
#include "parc/parc_chrome_urls.h"

#include <algorithm>
#include <memory>
#include <string>
#include <string_view>
#include <tuple>
#include <utility>
#include <vector>

#include "base/functional/bind.h"
#include "base/memory/ref_counted_memory.h"
#include "base/strings/escape.h"
#include "base/strings/strcat.h"
#include "base/values.h"
#include "chrome/browser/browser_process.h"
#include "chrome/common/webui_url_constants.h"
#include "components/prefs/pref_service.h"
#include "components/webui/chrome_urls/pref_names.h"
#include "content/public/browser/browser_context.h"
#include "content/public/browser/internal_webui_config.h"
#include "content/public/browser/navigation_controller.h"
#include "content/public/browser/reload_type.h"
#include "content/public/browser/url_data_source.h"
#include "content/public/browser/web_contents.h"
#include "content/public/browser/web_ui.h"
#include "content/public/browser/web_ui_controller.h"
#include "content/public/browser/web_ui_message_handler.h"
#include "content/public/browser/webui_config.h"
#include "content/public/browser/webui_config_map.h"
#include "content/public/common/url_constants.h"
#include "url/gurl.h"
#include "url/url_constants.h"

namespace parc {
namespace {

constexpr char kStyle[] = R"PARC(:root{--paper:#FFFCEC;--ink:#100E22;--text:rgb(16 14 34/.74);--muted:rgb(16 14 34/.45);--card:rgb(16 14 34/.05);--link:#3139FB;color-scheme:light dark}
@media (prefers-color-scheme:dark){:root{--paper:#15141C;--ink:#FFFCEC;--text:rgb(255 252 236/.74);--muted:rgb(255 252 236/.45);--card:rgb(255 252 236/.06);--link:#7A80FF}}
body{margin:0;background:var(--paper);color:var(--text);font:15px/23px system-ui,-apple-system,"Helvetica Neue",sans-serif;-webkit-font-smoothing:antialiased}
main{max-width:860px;margin:0 auto;padding:56px 32px 72px}
h1{margin:0;color:var(--ink);font:italic 600 44px/1.1 ui-serif,Georgia,serif;letter-spacing:-.2px}
h2{margin:40px 0 12px;color:var(--ink);font:600 17px/24px system-ui,-apple-system,sans-serif}
p{margin:10px 0 0;max-width:620px}
ul{display:grid;grid-template-columns:repeat(auto-fill,minmax(230px,1fr));gap:4px 20px;margin:0;padding:0;list-style:none}
li{font:13px/24px ui-monospace,"SF Mono",Menlo,monospace;overflow-wrap:anywhere}
a{color:var(--link);text-decoration:none}
a:hover{text-decoration:underline}
.off{color:var(--muted)}
button{margin-top:14px;height:34px;padding:0 16px;border:0;border-radius:17px;background:var(--ink);color:var(--paper);font:600 13px/1 system-ui,-apple-system,sans-serif;cursor:pointer}
button:focus-visible{outline:2px solid var(--link);outline-offset:2px}
.commands li{color:var(--text)}
.internal{margin-top:16px}
)PARC";

constexpr char kScript[] =
    R"PARC(document.getElementById('debug').addEventListener('click', (event) => {
  chrome.send('setDebugPagesEnabled', [event.currentTarget.dataset.enable === 'true']);
});
)PARC";

constexpr char kStylePath[] = "parc_chrome_urls.css";
constexpr char kScriptPath[] = "parc_chrome_urls.js";

struct Page {
  GURL url;
  bool enabled;
  bool internal;
};

std::string PublicAddress(std::string_view spec) {
  std::string address(spec);
  const std::string chrome =
      base::StrCat({content::kChromeUIScheme, url::kStandardSchemeSeparator});
  if (address.starts_with(chrome)) {
    address.replace(0, chrome.size(), "parc://");
  }
  if (address.size() > 1 && address.back() == '/') {
    address.pop_back();
  }
  return base::EscapeForHTML(address);
}

std::vector<Page> Pages(content::BrowserContext* context) {
  std::vector<Page> pages;
  const std::string_view hosts[] = {
      chrome::kChromeUIProfileInternalsHost, content::kChromeUIBlobInternalsHost,
      content::kChromeUIDinoHost, chrome::kChromeUIExtensionsInternalsHost,
      chrome::kChromeUIPrefsInternalsHost};
  for (std::string_view host : hosts) {
    pages.push_back({GURL(base::StrCat({content::kChromeUIScheme,
                                        url::kStandardSchemeSeparator, host})),
                     true, false});
  }
  if (context) {
    for (const content::WebUIConfigInfo& info :
         content::WebUIConfigMap::GetInstance().GetWebUIConfigList(context)) {
      const GURL url = info.origin.GetURL();
      pages.push_back({url, info.enabled, content::IsInternalWebUI(url)});
    }
  }
  std::sort(pages.begin(), pages.end(), [](const Page& a, const Page& b) {
    return std::make_tuple(!a.url.SchemeIs(content::kChromeUIScheme),
                           std::string(a.url.host())) <
           std::make_tuple(!b.url.SchemeIs(content::kChromeUIScheme),
                           std::string(b.url.host()));
  });
  return pages;
}

void AppendItem(std::string& html, const Page& page) {
  const std::string address = PublicAddress(page.url.spec());
  if (page.enabled && page.url.SchemeIs(content::kChromeUIScheme)) {
    base::StrAppend(&html, {"<li><a href=\"", base::EscapeForHTML(page.url.spec()),
                            "\">", address, "</a></li>"});
  } else {
    base::StrAppend(&html, {"<li class=\"off\">", address, "</li>"});
  }
}

std::string PageHTML(content::BrowserContext* context) {
  PrefService* local_state = g_browser_process->local_state();
  const bool debugging =
      local_state &&
      local_state->FindPreference(chrome_urls::kInternalOnlyUisEnabled) &&
      local_state->GetBoolean(chrome_urls::kInternalOnlyUisEnabled);
  const std::vector<Page> pages = Pages(context);
  std::string html = base::StrCat(
      {"<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\">"
       "<meta name=\"color-scheme\" content=\"light dark\">"
       "<title>Parc’s internal pages</title><link rel=\"stylesheet\" href=\"",
       kStylePath,
       "\"></head><body><main><h1>Parc’s internal pages</h1>"
       "<p>Every built-in page in Parc. You can type any of them into the "
       "address bar, too.</p><h2>Pages</h2><ul>"});
  for (const Page& page : pages) {
    if (!page.internal) {
      AppendItem(html, page);
    }
  }
  base::StrAppend(
      &html,
      {"</ul><h2>Internal debugging pages</h2><p>",
       debugging ? "These pages are on. They’re for people working on the "
                   "browser itself, and can show unfinished or unstable tools."
                 : "These pages are off. They’re for people working on the "
                   "browser itself, and can show unfinished or unstable tools.",
       "</p><button id=\"debug\" type=\"button\" data-enable=\"",
       debugging ? "false" : "true", "\">",
       debugging ? "Turn off internal debugging pages"
                 : "Turn on internal debugging pages",
       "</button><ul class=\"internal\">"});
  for (const Page& page : pages) {
    if (page.internal) {
      AppendItem(html, page);
    }
  }
  base::StrAppend(&html,
                  {"</ul><h2>For debugging</h2><p>These crash or freeze a "
                   "page on purpose, so they aren’t links. Type one into the "
                   "address bar if you need it.</p><ul class=\"commands\">"});
  for (std::string_view command : chrome::ChromeDebugURLs()) {
    base::StrAppend(&html, {"<li>", PublicAddress(command), "</li>"});
  }
  base::StrAppend(&html, {"</ul></main><script src=\"", kScriptPath,
                          "\"></script></body></html>"});
  return html;
}

class ChromeUrlsSource final : public content::URLDataSource {
 public:
  std::string GetSource() override { return chrome::kChromeUIChromeURLsHost; }

  std::string GetMimeType(const GURL& url) override {
    if (url.path() == base::StrCat({"/", kStylePath})) {
      return "text/css";
    }
    if (url.path() == base::StrCat({"/", kScriptPath})) {
      return "text/javascript";
    }
    return "text/html";
  }

  void StartDataRequest(const GURL& url,
                        const content::WebContents::Getter& wc_getter,
                        GotDataCallback callback) override {
    std::string body;
    if (url.path() == base::StrCat({"/", kStylePath})) {
      body = kStyle;
    } else if (url.path() == base::StrCat({"/", kScriptPath})) {
      body = kScript;
    } else if (url.path() == "/") {
      content::WebContents* contents = wc_getter.Run();
      body = PageHTML(contents ? contents->GetBrowserContext() : nullptr);
    } else {
      std::move(callback).Run(nullptr);
      return;
    }
    std::move(callback).Run(
        base::MakeRefCounted<base::RefCountedString>(std::move(body)));
  }
};

class ChromeUrlsHandler final : public content::WebUIMessageHandler {
 public:
  void RegisterMessages() override {
    web_ui()->RegisterMessageCallback(
        "setDebugPagesEnabled",
        base::BindRepeating(&ChromeUrlsHandler::SetDebugPagesEnabled,
                            base::Unretained(this)));
  }

 private:
  void SetDebugPagesEnabled(const base::ListValue& args) {
    PrefService* local_state = g_browser_process->local_state();
    if (!local_state ||
        !local_state->FindPreference(chrome_urls::kInternalOnlyUisEnabled) ||
        args.empty() || !args[0].is_bool()) {
      return;
    }
    local_state->SetBoolean(chrome_urls::kInternalOnlyUisEnabled,
                            args[0].GetBool());
    web_ui()->GetWebContents()->GetController().Reload(
        content::ReloadType::NORMAL, false);
  }
};

class ChromeUrlsUI final : public content::WebUIController {
 public:
  explicit ChromeUrlsUI(content::WebUI* web_ui) : WebUIController(web_ui) {
    web_ui->AddMessageHandler(std::make_unique<ChromeUrlsHandler>());
    content::URLDataSource::Add(web_ui->GetWebContents()->GetBrowserContext(),
                                std::make_unique<ChromeUrlsSource>());
  }
};

}  // namespace

void RegisterChromeUrlsWebUI() {
  auto& configs = content::WebUIConfigMap::GetInstance();
  configs.RemoveConfig(GURL(base::StrCat({content::kChromeUIScheme,
                                          url::kStandardSchemeSeparator,
                                          chrome::kChromeUIChromeURLsHost})));
  configs.AddWebUIConfig(
      std::make_unique<content::DefaultWebUIConfig<ChromeUrlsUI>>(
          content::kChromeUIScheme, chrome::kChromeUIChromeURLsHost));
}

}  // namespace parc
