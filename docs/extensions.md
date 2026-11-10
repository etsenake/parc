# Extensions

## Installation education and discovery — EXT11

Ordinary extension consent uses the actual extension name, icon and Chromium
permission messages with **Add Extension** / **Cancel** copy,
**It can:** heading and explicit no-special-permissions state. The sheet uses the native dialog container and appearance-aware palette. Every Chromium permission
message is kept; the list scrolls inside a 113-point region with a
bottom fade. Parc's `Borderless` mark identifies the application. Non-square extension
artwork is aspect-fitted in its 62-point slot; missing artwork uses the
`puzzlepiece.extension.fill` fallback.

The original captured Browser/Profile/page/document/window and exclusive
security reservation still own consent. Chromium's withholding checkbox,
500-millisecond unobstructed input delay, once-only decision and deferred
original-owner revalidation are preserved. Return accepts and Escape cancels.
Chromium 156 instead makes Cancel
the default for this prompt (`extension_install_dialog_view.cc`). Return only
accepts while the button is enabled and unobstructed, and never from a key
repeat or from a keyDown whose timestamp precedes the end of the current input
delay, so a Return held or pressed as the sheet appears cannot accept it.
Enterprise requests, pending policy, parent approval, re-enable, repair,
additional-permission and app/theme requests keep their actual
upstream-specific text and controls. Those Chromium 156 security/service
requirements are explicit current-engine adaptations.

Installer results present no separate native confirmation. A successful extension,
theme or bubble-app install shows no sheet, toast, pin or picker; an
extension's own welcome page still opens through Chromium if it creates one.
Only a non-bubble app opens the Apps page, which is the engine's own branch.
Failures show no separate alert; the Web Store page reports its own error.

Installed extension names now appear as genuine launch candidates in ordinary
Command Bar search and its Actions scope, separately from optional extension
omnibox keywords. The candidate retains the immutable native action token and
its original page/profile/model generation. Dispatch dismisses the command
surface, revalidates the original window, then calls the genuine native action
owner. Unload, replacement, navigation, profile/Space change and stale native
publications cannot retarget an old row. Split and background dispositions are
refused for these page-owned actions; native disabled-action context-menu
fallback remains available. Native model order is the bounded ranking adapter;
complete search ranking remains with the Command Bar.

Placement continues through the real profile toolbar pin state and the existing
Site Control Center, Extensions menu and current toolbar/sidebar anchor. Installation does not auto-pin an extension or force-open its picker.

## Focus, keyboard and accessibility — EXT13

[Extension interaction](extensions-interaction.md) describes sidebar/top-bar
feedback, the held-Command picker, immutable action leases, keyboard focus and
policy-aware accessibility. [Extension lifecycle](extensions-lifecycle.md)
owns popup/side-panel replacement, closure and saved-focus restoration.

### Popup toolbar enabled-extension availability

`hasEnabledExtensions(for:)` validates the selected attached page and its
Browser-owned Profile, then reads Chromium's enabled registry. It uses the
extension-settings visibility predicate, excluding normal internal components.
Availability includes extensions without toolbar actions. Off-the-record
registry lookup uses Chromium's original Profile; that count does not grant
incognito access. Every action applies its own page/permission checks.

Registry load/unload notifications feed a coalesced window callback. Shutdown
removes observation and invalidates pending deliveries.

### Popup extension-menu metadata carrier

`enabledExtensions(for:)` snapshots the same registry, including no-action
extensions. Manifest artwork loads asynchronously at 32 logical points with
available scale representations. Missing/pending/failed images stay nil; this
carrier does not fabricate a default icon. Menus omit nil-icon entries while
preserving the independent availability flag.

Each snapshot binds the original Browser, tab, document, generation and enabled
extension identity. Navigation, selection, registry changes and shutdown retire
it. Image completions revalidate that identity. Dispatch rejects security-modal
contexts and requires Chromium's actual current action model, returning false
when none exists or private access is unavailable.

## Chrome Web Store identity

`Engine/ParcInternalExtension` is a bundled component extension, registered by
`internal-extension.patch`, that labels the store's install/remove controls for
Parc and removes Chrome-switch prompts. Its fixed ID is
`nncglbbjcndfbjaofnljgecleghcjohe`. It matches the store host exactly and does
not change user-agent brands or other sites. Store host permission supplies the
URL; no `tabs` permission or unrelated Slack/Notion page styling is included.

## Checks and delivery boundary

Native consent components exercise cancellation, once-only decisions, input
delay, obstruction, permission layout and invalidation without an actual install.
Command Bar integration receives Swift compiler checks; native owners use their
pinned Chromium compiler targets. Metadata tests cover no-action entries,
staleness and security admission. Browser-test source compilation is distinct
from execution. Source checks do not establish real installs, device/browser
behavior or live accessibility. Current delivery status belongs in the
[product status](parity.md), not a stale pending-build note here.
