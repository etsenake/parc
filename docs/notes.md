# Local Notes

Notes are Markdown files on disk, opened in a native editor. Each Space's Profile
has a Notes folder, chosen in Settings like the Downloads location and
`~/Documents/Parc Notes` by default. New Note, New Note in Split View and the split
insertion bar create an `Untitled.md` file there and open it as a Today tab;
closing the tab archives it and keeps the file. File → Show Notes Folder reveals the
current Space's folder in Finder. Library → Easels & Notes lists that folder and
opens, renames or moves notes to the Trash; deleting a note first retires every
tab showing that file, in every Profile.

A note tab's address is its file's `file://` URL, and its title is the file name;
renaming a note moves every tab that shows it. The sidebar's URL pill shows the
file's name. A note's front-matter emoji icon is its tab icon in the sidebar,
Favorites, the folded Pinned peek, the tab switcher and the command bar; a local
image icon shows as a small rounded thumbnail, and anything else keeps the note
glyph. An open note's icon updates as it's edited, and other notes reread their
front matter off the main thread when their folder changes. Any regular Profile can open any
note file, so moving a tab to another Profile leaves the file where it is.
Parc appears in Finder's Open With list as an editor for Markdown and plain text.
Opening one from Finder or the Dock icon, dropping it on the sidebar, typing its
`file://` address, or following a link to one from a note or a page opens a note
tab instead of Chromium's file view; other file types still open in Chromium. A
page's link leaves the page and its history where they are and opens the note in
its own tab ([note links](navigation.md#links-to-markdown-and-text-files)).
Dropping notes on the sidebar shows the insertion line and opens their new tabs
right there; a note that already has a tab just comes forward. A `#heading` or
block anchor in the address scrolls to that spot, and clicking a note reminder
opens its note the same way, always in a regular window.
Old `parc://note/<UUID>` tabs from the previous format show a short error, and the
old `Profiles/<id>/Notes/*.json` documents are not read or migrated.

Private windows deliberately offer no Notes, as explained in
[capture Library](capture-library.md#private-media-ownership): a Markdown file
opened while a private window is in front opens in a regular window. Cloud
sharing, collaboration and vendor services are excluded.

Embed blocks hold a live web page in the note's Profile, with its sign-ins, at a
height people drag to taste. Click a page to use it; until then the note keeps
scrolling past it. The pages nap after four hours out of sight, follow the tab
between windows and ask before leaving, like an Easel's pages ([embedded pages](embedded-pages.md#live-embeds-in-notes)).

## Editing and lifetime

The body uses AppKit attributed text, native selection/caret, composition,
Undo/Redo, range formatting, paragraph/list commands, supported Markdown
transforms, links, rich clipboard and local image carriers. Cmd-F targets the
note's own find bar; only a focused [live embed](embedded-pages.md#live-embeds-in-notes)
hands Find to its page. Title and body have
separate native Undo managers and retain IME drafts until composition commits.

Each field update checks its prior value, preventing a stale window from
replacing a newer edit. Independent title changes preserve body Undo; external
body replacements invalidate stale local body history. Formatting targets retain
body identity, document revision, complete attributed content and UTF-16 range.
Changed text/attributes, selection, geometry, ownership, composition, tombstone
or cross-window publication revoke them. Only that editor's successful save of
the exact pending content may advance a retained target's durability revision.

Save/validation failures preserve the draft with Retry and Discard Draft and
block closure. Tab/window/Profile retirement flushes the real editor before
consent completes. A failed unrelated model mutation cannot dispose of its draft.
UUID paths, regular-file/symlink checks, range validation and byte limits protect
the local format.

## Body publication and local save barriers

Body changes use a 0.5-second main-queue Combine throttle with `latest=true`;
continuous typing still publishes rather than postponing forever. Title changes
publish immediately. In-memory publication does not combine native Undo steps.
Disk persistence follows a three-second delay that later edits replace.
Create and tombstone writes are immediate. Close, export, Retry and termination
flush all pending store writes, including documents without a live editor.

JSON encoding, the 8 MiB cap, exclusive temporary-file write, `fsync` and atomic
rename run at persistence, not on every keystroke. Library listing prefers the
live or pending document. A delayed write failure preserves that authoritative
memory state and reports its actual error; closure waits for a successful Retry.
Title/deletion notifications publish immediately, while body-only memory changes
do not publish the Library store-change stream.

Deletion captures the exact Profile/document and all saved-tab references,
including tabs currently navigated away. It uses genuine whole-set retirement,
persists tab-reference removal first, then deletes the document. A failed session
write preserves everything; a later document-delete failure leaves its real
Library row available for retry. A small identity tombstone prevents stale
sessions from recreating deleted content. Surviving split geometry remains intact.

## Paragraph gutter and formatting ownership

The paragraph menu offers Heading 1–3, Text, Bulleted List, Numbered List, Bold,
Italic, Underline, Strikethrough, Insert Image and Link. These use the shared
attributed-text operations. List nesting is actual `NSTextList` structure with
native Tab/Backtab and Undo, not a separate document tree.

The 42×30 gutter sits five points from the actual first-character rectangle.
It uses Nunito glyphs and a six-point disclosure triangle; an empty-line plus
omits that triangle. Idle opacity is 0.33 and hover/selected opacity is 1. Press
uses hover feedback, with selected state taking precedence. Paragraph tracking
retains its original line metadata while a menu is open; scrolling recomputes
that anchor without inventing pointer input. The extra empty line targets the
real end-of-body range.

Gutter icon classification is display-only: valid list markers take precedence,
then the first font run's 32/26/22-point size selects H1/H2/H3; ordinary text is Aa.
Empty means newline-only, not whitespace-trimmed. A collapsed caret at that
range may supply its typing font; otherwise an empty line uses Plus. No display
classification rewrites authored fonts or semantic paragraph attributes.

### Image picker and local image ownership

Insert Image opens a single-file sheet for JPEG, PNG, PDF, BMP or TIFF, bound to
the original Note window/body/range. Cancellation, stale contents, composition,
read-only/deleted state or retirement inserts nothing. Files are bounded regular
local files. JPEG/PNG/TIFF retain validated bytes; BMP becomes PNG; PDF uses its
first-page raster at one pixel per point. No private filesystem reference or
upload becomes part of the document. Native insertion owns selection and Undo.

## Native selection formatting

The compact horizontal selection bar shares the paragraph menu's controls and
light/dark palette. Checked formatting takes precedence over hover and keyboard
highlight. Link's checked state follows the first character of the primary
selected substring; its actual edit still binds the complete selection range.
The paragraph submenu remains a native menu with Plain Text, Heading 1–3 and the
two lists. Retired controls are disabled and disconnected before removal.

## Title and body keyboard ownership

The title is plain text. Paste takes the first plain-string item and replaces
newlines with spaces. Initial forwarded focus chooses an empty title, otherwise
the body, while an already active original responder retains focus.

- Title Tab/Down and Right at its end focus the body's start. Return and alternate
  Return move the title suffix beginning at selection start to the body, adding
  a newline before existing content. Literal Tab is consumed without insertion.
- Body Up on its first visual line and Left at a collapsed start focus the title's
  end. Backspace at the body start joins its first plain line to the title only
  with default typing attributes. An image-bearing line refuses with an error;
  styled/list/heading text retains native behavior.
- Escape dismisses an owned formatting menu first, otherwise collapses the active
  selection at its start. Body Return while a format menu exists is consumed,
  even when no keyboard item is selected; otherwise it stays native. Body
  Down/Right dismiss the menu and continue native movement.
- The three beginning-of-line/paragraph selectors use the shared scalar-safe
  prefix policy. CRLF is one boundary. Ordinary field behavior remains native
  outside these explicitly handled cases.

Composition, another responder, non-key windows, sheets and deletion block these
boundary commands. Transfers validate both previous field values and stable body
ID as one document update; failures preserve both drafts. Field-local Undo stays
separate and cannot impersonate a whole-document transaction.

## Native document presentation

A centered column prefers 900-point width and 100-point side margins, with 20-point
minimum sides and a 250-point field-width preference that can yield in narrow
panes. Top/bottom spacing is 64 and title/body spacing 16. Native measurement keeps
both original text views through reflow, including their selection and IME state.

New title/body defaults are Nunito ExtraBold 34 and Regular 18, line-height 1.25,
spacing 4 before / 8 after. Explicit saved formatting remains unchanged. Bundled
fonts retain their license and attribution in `Resources/NoteFonts`. The title's
empty placeholder is Title; the body has no invented placeholder.

NotesBackground is white at 85% in light appearance and black at 50% in dark.
Only a displayed Note clears the pane backing so this surface composites over
the existing Space theme. Other page types restore their backing. Named ink,
selection, cursor and links follow the Space's content appearance; appearance
changes never rewrite text, selection, Undo or saved files.

Default body ink uses optional `semanticInk=noteBody` in the rich carrier with
a black light/export fallback. Explicit authored colors and legacy untagged
runs remain fixed. Private rich clipboard and formatting preserve that tag;
HTML export resolves only semantic default ink to its fixed light fallback.

A real load failure displays Can't load this note and its local error instead
of a fake editor. Save failures stay in the editor with their original draft.
There is no artificial local-loading spinner.

## Format-menu motion

Selected-index movement and in-place item opacity use a spring with response
0.15, damping 0.825 and blend 0. Gutter hover and menu presentation/dismissal are
immediate. Reduce Motion settles existing animation and prevents new springs.
Notes does not emit haptic feedback.

## Keyboard, accessibility and viewport focus

Pointer/automatic menus keep the body first responder with no initial keyboard
selection. Explicit footer or accessibility Format Paragraph/Selection focuses
the menu; arrows select an enabled control and Return/Enter/Space activates it.
Escape returns to the original body without stealing another live control.

The gutter is an accessible press target, not a key-loop stop. Title/body remain
native text areas; footer Retry/Discard/Format buttons follow the body when
visible. The final control leaves traversal to the containing window. Explicit
format entry scrolls its target into view; pointer presentation does not.
Image and link-sheet completion return focus only to the original eligible body.

## Checks

`scripts/test-notes.sh` runs the windowless note tab checks (file addresses,
opening, renames, archive and restore, splits and deletion consent across Profiles)
and then `scripts/test-notes-editor.sh`, which covers the editor model and file
layer with temporary fixtures.
