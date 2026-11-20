# Internal addresses

Parc accepts `parc://` for Chromium-backed internal destinations, including Settings,
passwords, extensions, flags, version and the internal-page directory. The native
omnibox uses Chromium’s genuine built-in provider and controller inventory; Parc does
not maintain a replacement list of fake pages. Unknown hosts receive Chromium’s normal
controller/error behavior. `arc://` is not a registered or translated alias. Three hosts
are Parc's own pages behind real controllers: `parc://license`, `parc://whats-new`,
which replaces Chromium's What's New controller with the bundled release notes
([software updates](software-update.md#whats-new-page-ownership)), and `parc://chrome-urls`
(also reached as `parc://about`), Parc's own directory of internal pages: `parc_chrome_urls.cc`
replaces Chromium's controller from the same browser-main `PreBrowserStart` callback and
lists Chromium's real page inventory, `WebUIConfigMap` plus the pages without configs and
the debug commands, under `parc://` names. It keeps the internal debugging pages switch,
which sets the same local-state preference through a page message, and links only pages
the Profile can open.

`parc://easel/<UUID>` remains the app-owned Easel address. A note tab's address is its
Markdown or text file's `file://` URL, which opens in the native note editor rather
than Chromium. The retired `parc://note/<UUID>` form stays reserved so old tabs show a
short error instead of reaching Chromium. Malformed document addresses stay in those
typed app routes; they cannot acquire WebUI bindings. Conversely, unsupported
`chrome://easel` and `chrome://note` addresses are not projected into existing documents.

## Request and security ownership

The all-process content client registers `parc` as standard, secure, CORS-enabled and
savable. It does not register a response factory, grant WebUI bindings, bypass CSP,
grant file access or add service-worker privileges. A pure GURL component conversion
changes only the scheme to `chrome` before the original `NavigateParams` policy path and
in the real browser URL-handler chain. The handler returns false so Chromium’s remaining
aliases, policy and controller processing continue. Original request bodies, referrers,
initiator origins, callbacks, dispositions and Profile/OTR owners stay with the original
request.

The actual document remains a `chrome://` origin. Current Chromium’s `WebUIConfigMap`
still requires its registered origin, `IsWebUIEnabled(browser_context)` and
`ShouldHandleURL`; renderer/process security checks remain unchanged. `HasWebUIScheme`
recognizes the public scheme. This is necessary for `RenderFrameImpl`’s original
top-level WebUI branch to transfer the complete request through `OpenURL` to the
browser-owned navigation path, rather than begin an unsupported renderer/network
request. The existing IPC validation, request fields and browser beforeunload/security
policy stay authoritative. This classification does not register a `parc` WebUI
controller or data source: the actual controller lookup remains restricted to Chromium’s
real origins. Subframes do not receive a new rewrite or privilege bypass.

Controller-generated `chrome://` anchors, resources and endpoint constants remain
internal Chromium URLs. Original link activation reaches the real controller. At the
user boundary, Parc projects native page/navigation-history addresses, omnibox URL
labels, hover destinations, link copying, bookmarking and exported source metadata to
`parc://`. Context-menu Copy Link and Copy URL/Markdown preserve the actual Chromium
clipboard-policy endpoint while projecting only the copied destination. No query,
referrer, security origin, extension URL or `chrome-untrusted://` origin is rewritten.
Chromium's other WebUI pages keep their own text. Parc's network error pages and
security warnings show `parc://` in their titles and visible text, and Parc's directory
writes its names that way; their links still lead to the real `chrome://` controller
([error pages](web-interactions.md#network-error-pages-and-security-warnings)).

The app stores public destinations for normal/native tab adoption, command results and
navigation updates. Legacy saved sessions migrate current and pinned destinations
independently without changing IDs, Profile/Space membership, archive state or native
ownership. Address edit/copy and restored sessions therefore use the same public scheme.
Browser menus use the same real Settings/passwords/extensions routes. Easel routing is
decided separately from browser WebUI.

## Checks

`tests/NativeInternalURLs` covers scheme conversion, public address projection and
app-owned document boundaries. The public scheme is presentation and routing; it is
never a separate grant of WebUI privileges.
