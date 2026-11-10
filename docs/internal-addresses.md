# Internal addresses



## Request and security ownership

The all-process content client registers `parc` as standard, secure, CORS-enabled and savable. It does not register a response factory, grant WebUI bindings, bypass CSP, grant file access or add service-worker privileges. A pure GURL component conversion changes only the scheme to `chrome` before the original `NavigateParams` policy path and in the real browser URL-handler chain. The handler returns false so Chromium’s remaining aliases, policy and controller processing continue. Original request bodies, referrers, initiator origins, callbacks, dispositions and Profile/OTR owners stay with the original request.

The actual document remains a `chrome://` origin. Current Chromium’s `WebUIConfigMap` still requires its registered origin, `IsWebUIEnabled(browser_context)` and `ShouldHandleURL`; renderer/process security checks remain unchanged. `HasWebUIScheme` recognizes the public scheme. This is necessary for `RenderFrameImpl`’s original top-level WebUI branch to transfer the complete request through `OpenURL` to the browser-owned navigation path, rather than begin an unsupported renderer/network request. The existing IPC validation, request fields and browser beforeunload/security policy stay authoritative. This classification does not register a `parc` WebUI controller or data source: the actual controller lookup remains restricted to Chromium’s real origins. Subframes do not receive a new rewrite or privilege bypass.


The app stores public destinations for normal/native tab adoption, command results and navigation updates. Legacy saved sessions migrate current and pinned destinations independently without changing IDs, Profile/Space membership, archive state or native ownership. Address edit/copy and restored sessions therefore use the same public scheme. Browser menus use the same real Settings/passwords/extensions routes. Easel routing is decided separately from browser WebUI.

## Validation boundary

Source/compiler/component checks cover scheme conversion and original request
ownership. They do not establish browser runtime acceptance. The public scheme
is presentation and routing; it is never a separate grant of WebUI privileges.
