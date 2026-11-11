// Copyright 2026 Parc contributors.
#include "parc/parc_branding.h"

#include <memory>
#include <utility>

#include "base/memory/ref_counted_memory.h"
#include "content/public/browser/url_data_source.h"
#include "content/public/browser/web_contents.h"
#include "content/public/browser/web_ui.h"
#include "content/public/browser/web_ui_controller.h"
#include "content/public/browser/webui_config.h"
#include "content/public/browser/webui_config_map.h"
#include "content/public/common/url_constants.h"

namespace parc {
namespace {
constexpr char kLicenseHTML[] = R"PARC(<html><head><meta charset="utf-8"><title>Parc licences</title></head><body><h1>Parc</h1><p>Copyright 2026 Parc contributors.</p><p>Chromium and third-party notices: <a href="chrome://credits/">credits</a>.</p><h2>Retained Chromium Embedded Framework code</h2><pre>// Copyright (c) 2008-2020 Marshall A. Greenblatt. Portions Copyright (c)
// 2006-2009 Google Inc. All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are
// met:
//
//    * Redistributions of source code must retain the above copyright
// notice, this list of conditions and the following disclaimer.
//    * Redistributions in binary form must reproduce the above
// copyright notice, this list of conditions and the following disclaimer
// in the documentation and/or other materials provided with the
// distribution.
//    * Neither the name of Google Inc. nor the name Chromium Embedded
// Framework nor the names of its contributors may be used to endorse
// or promote products derived from this software without specific prior
// written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
// &quot;AS IS&quot; AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
// LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
// A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
// OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
// SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
// LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
// DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
// THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
</pre></body></html>)PARC";
class LicenseSource final : public content::URLDataSource {
 public:
  std::string GetSource() override { return "license"; }
  std::string GetMimeType(const GURL&) override { return "text/html"; }
  void StartDataRequest(const GURL&, const content::WebContents::Getter&,
                        GotDataCallback callback) override {
    std::move(callback).Run(
        base::MakeRefCounted<base::RefCountedString>(kLicenseHTML));
  }
};
class LicenseUI final : public content::WebUIController {
 public:
  explicit LicenseUI(content::WebUI* web_ui) : WebUIController(web_ui) {
    content::URLDataSource::Add(web_ui->GetWebContents()->GetBrowserContext(),
                              std::make_unique<LicenseSource>());
  }
};
}  // namespace
void RegisterLicenseWebUI() {
  content::WebUIConfigMap::GetInstance().AddWebUIConfig(
      std::make_unique<content::DefaultWebUIConfig<LicenseUI>>(
          content::kChromeUIScheme, "license"));
}
}  // namespace parc
