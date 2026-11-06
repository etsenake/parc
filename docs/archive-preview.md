# Archive preview handoff

The Library appearance owner delegated Archive row preview to
`codex/library-archive-preview`. Work is in progress; Archive/History's existing
LEFT rows are not complete. The shared Archive retirement dependency is owned by
`archive_retirement` in `codex-archive-retirement`.

Archive row opened the real page in a large centered rounded overlay over the
dimmed Library and current page. Close dismissed the overlay and left the
Archive entry. Expand dismissed overlay and Library, selected the page as a
normal sidebar tab, and the Archive entry was gone when Library reopened. The

`4e452201e483b5480c0403a9ef8566e10515cdcb78828622ff9032b202e29547`:
`HomeArchiveTabDelegateAction.onSelectedToPreviewItem(ArchivedItem)` is distinct
route; other item tags enter it, which does not prove each can be presented.
The exact Archive-specific teardown, promotion ordering and snapshot-cache
consumer remain open. Parc's proposed transfer of the preview's native page on

## Engine dependency

Receiving owner: the dedicated Parc engine owner from the earlier interrupted
“Build a usable Parc browser” chat. Root reports that owner is not reachable in
this team and has no usable agent ID. The request was relayed through the Library
owner and root; acceptance is pending. No replacement owner has been assigned.
The app needs cancellable asynchronous creation of a **normal, non-embedded**
page in the captured `PCNativeBrowserWindow` and exact profile. A pure caller
lease must be revalidated after asynchronous profile resolution and immediately
before committing creation/navigation. Cancellation before commit creates and
navigates nothing. Completion is once on main. No requested URL loads before the
page has an authoritative owner and attachment. The page belongs to the binding's
ordinary close coordinator and is not automatically adopted as a sidebar item.
The app must register the exact preview session and destination container before
any native creation, attachment, selection or close callback can expose its
page. The current `containerFor:disposition:` treats an unknown normal page as
a new Today tab, so an early callback without that registration would silently
create a durable item with the wrong source. Creation must let the shell resolve
that exact session rather than falling through to ordinary adoption. The native
host may ask for a container before the creation completion; returning nil does
not cancel the page, so the handshake must expose an exact reservation/identity
without guessing from URL or profile. Selection and close notifications must
identify the same page and binding, including
early close or cancellation, and must not select the underlying page or delete
the archived item. It must be possible for the app to select the preview and
later transfer its same page into the restored original item, subject to exact
ownership checks.
Existing `openURL` selects during asynchronous creation without a caller lease;
`openBackgroundURL` lacks a public validated/cancellable URL route;
`createEmbeddedPage` is Easel-classified and HTTP(S)-only. None supplies the
required general Archive page contract. The engine owner owns implementation,
checks, engine handoff and publication.

## App responsibilities

The initiating physical window holds the original item/profile/group identity,
Library/category and page/document owners. It must include preview pages and
editors in the existing shared whole-set retirement collector, retain them over
asynchronous close consent, and keep the underlying Library and selected page
intact until a transition succeeds. Close retains the archive record; Expand
must validate and restore the original item before transferring the materialized
owner. Retiring, stale or malformed groups must not partially materialize.
Archive deletion, clear, expiry, document deletion and profile removal must not
strand active owners or overwrite newer edits. Split geometry and typed Note/Easel
ownership are required; an ordinary URL substitute is insufficient. Web preview
metadata must remain local to the session until an explicit successful restore.
The normal native container, selection and close callbacks must recognize the
exact preview session before their ordinary tab fallback. The window must
include genuinely visible preview pages in native visibility and download
ownership, route crashes and focus to the preview, and never substitute the
underlying selected tab for popup, link, authentication or capture provenance.
Preview child-page routes require their own validated source and destination;
where those semantics are not established, the app must refuse the route rather
than attach it to the underlying tab. Hiding capture controls is not a capability
gate: native capture can start from the active page, so the preview must join
actual capture ownership, indicators and Stop controls, or the engine must refuse
the capability. Preserve the exact active-document and security-reservation
checks for authentication, uploads and external protocols.
No functional browser tests are authorized under the current direction.
