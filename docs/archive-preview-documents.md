# Archive preview document ownership

`ArchivePreviewDocumentOwner` can load the existing Profile-scoped Note or Easel
store and real editor for one archived member. The current Archive preview route
does not create this owner: it admits one HTTP(S) tab only. Notes, Easels and
complete splits can be restored through Put Back, but cannot be previewed in
Library.
[Archive previews](archive-preview.md) owns the user-facing behavior.

## Existing owner

The helper neither restores a tab nor substitutes a snapshot. Admission checks
the original archived record, Profile-removal state and caller's lease before
and after loading. Its editor exposes the original Note session or Easel page
owner. `prepareToClose()` flushes Note saves or asks the Easel to finish without
losing a draft. `retireAfterClose()` refuses while embedded pages or their
creation remain active, and retires the Easel page owner only after they close.

## Missing shell transaction

The containing preview still needs to retain the complete member set, configure
Easel pages against its original window and lease, and own presentation and
whole-set native close consent. Editor callbacks must bind to that preview,
including title edits, rather than the selected tab behind it. A refused close
must preserve the original editor and embedded pages.

Expand must transfer those same editors and page identities into restored panes.
Easel's existing `WindowTransfer` gates creation and retirement; active web-input
drafts and marked text must finish without being canceled. Notes need their
title and URL callbacks rebound to the restored pane. The shell must stage and
revalidate all owners before calling the store restore API, which publishes
synchronously. Replacing an editor after a failed transfer would lose its state.

This integration remains in [the backlog](backlog.md); the helper alone does not
provide a document or group preview.
