# Archive preview document ownership

`ArchivePreviewDocumentOwner` loads the existing Profile-scoped Note or Easel
store and real editor for one original archived member. It neither restores the
tab nor substitutes a snapshot. Admission checks the exact archived record,
Profile-removal state and caller's lease before and after loading. The window
retains the complete member set and owns its transition; callbacks bind to the
preview session rather than the selected tab behind it. Real title edits use
the normal document path and must be reflected in lease snapshots.

## Embedded pages and retirement

Configure an Easel through its existing `configurePages`, with validity bound to
the physical preview window, original member and lease. Native creation rechecks
that validity before commit. The retirement collector needs `noteEditor`,
`embeddedPages` and `hasPendingPageCreation`; retain these owners through consent
and repeat `prepareToClose()` at admission, commit and completion.
`retireAfterClose()` may dispose the Easel page owner only after its real pages
close. Refusal preserves the original editor and pages.

## Promotion constraint

Expand must transfer the same editor into the restored pane. Easel's
`WindowTransfer` snapshots original page/view identities and gates creation and
retirement. `prepareToClose()` refuses active web-input drafts and marked text;
a transfer must not cancel those edits. Stage all members under a whole-window
reservation and revalidate every identity and the archive lease before commit.
Notes also require title/URL callbacks to be rebound to the restored pane.

The store restore API publishes synchronously. Its callbacks alone do not
protect staged shell owners, so the promotion transaction remains unfinished.
Do not replace an editor to conceal a failed transfer. Group materialization,
presentation, whole-set retirement and restore belong to
[Archive preview](archive-preview.md). This seam is not an assertion of completed
preview behavior or browser-runtime acceptance.
