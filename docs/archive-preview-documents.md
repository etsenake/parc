# Archive preview document owner handoff

The Archive preview owner receives `ArchivePreviewDocumentOwner`, one per
original Note or Easel member. It loads the existing profile-scoped document
store and real editor; it does not restore the archived tab, own a lease, or
construct a substitute snapshot. Admission checks the exact archived record,
profile removal and the caller's current lease before and after loading. The
containing window retains and revalidates the lease and all members, and owns
the whole-group transition. Its callbacks must bind to that preview session,
not the underlying selected tab. Title edits use the normal document-title
update path; lease/operation snapshots must account for those real edits.

Configure Easel pages with the existing `configurePages` and a validity closure
bound to the preview's physical window, exact original member and lease. The
existing embedded-page creation revalidates that closure before native commit.
Expose `noteEditor`, `embeddedPages` and `hasPendingPageCreation` to the shared
retirement collector, retain the original owner/editor through consent and
repeat `prepareToClose()` at the admission, commit and completion boundaries.
Only after the real embedded pages have closed may `retireAfterClose()` dispose
the Easel page owner. A refusal preserves the editor and pages.

Expand must transfer the same editor object into the restored pane. The existing
Easel `WindowTransfer` snapshots exact page/view identities and gates creation
and retirement while a handoff is reserved. It can rebind the same physical
window and, before restore, rebind the retained original callbacks if staging
must be reversed. Before beginning a transfer, `prepareToClose()` refuses an
active web-input draft or marked text, so beginning the transfer cannot cancel
that draft. The consumer must establish and protect its whole-window
reservation, stage all members, revalidate their identities and the lease,
and handle synchronous model-publication callbacks. The current store restore
API publishes synchronously and does not itself guarantee that staged shell
owners survive those callbacks; that promotion transaction remains unresolved.
It must never replace the editor to paper over a failed transfer. A Note's
normal title and URL callbacks likewise need rebinding to the restored pane.
These are Parc adaptations; the reference identity and promotion ordering are
not established by the retained Archive evidence in
[archive-preview.md](archive-preview.md).

This is an integration seam, not completion of Archive preview. Group
materialization, presentation, whole-set retirement and restore remain with
`codex/library-archive-preview`; functional browser validation is not claimed.
