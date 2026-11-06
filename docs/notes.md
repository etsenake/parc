# Local Notes



## Evidence and adaptations





## Editing and lifetime


A failed validation or disk write leaves the original draft visible with Retry and Discard Draft. A close request is refused until it saves or the user discards that draft. An unrelated tab-model mutation cannot silently dispose of a failed draft. Successful writes use a private temporary file, file sync and atomic rename, then publish the new document revision. UUID paths, regular-file/symlink checks, rich-range validation and byte limits constrain the local format.

Deletion captures the exact profile/document and original saved-tab set, including tabs currently navigated away from that saved document. It joins the existing native retirement/beforeunload transaction and rejects changed consumers or stale owner/revision state. It persists tab-reference removal first. If that session write fails, the document stays intact. If document deletion subsequently fails, the genuine Library row remains available to reopen or retry; the error is reported. Successful Notes deletion clears title/body and retains a small identity tombstone so a stale session cannot resurrect it. Surviving split children keep their original group identity and normalized geometry. There is no whole-store Undo snapshot or silent cross-profile migration.

## Remaining scope

This delivery does not claim full historical Notes parity. The actual writer does not establish nested block editing. Paragraph/list nesting remains real attributed-text structure; it is not a separate invented block graph. The original title/body publication distinction is implemented below; historical local import is recovered as absent and the local disk save-effect delay is implemented below. The recovered selection menu, title/body boundary commands, remaining body Return→didPressEnter, beginning-of-line caret commands and existing-surface keyboard/AX/viewport-focus presentation below are implemented; commands are not inferred from names. Cloud sharing/collaboration and vendor services remain excluded. The recovered document layout, title typography and load-error owner are implemented below. Body defaults and the actual parent palette consumer are recovered below. Recovered format-menu motion is implemented below. The outer canvas now composites named NotesBackground over the enclosing Space theme using that Space’s content-over-background appearance, as recovered below. The paragraph gutter control and tracking lifetime are recovered below. The twelve eventual gutter actions and their compact grouped menu are attributed to the actual Notes builder; other shared rich-text capabilities are not automatically claimed as Notes UI parity.

`bash scripts/test-notes.sh` exercises real local store failure/reopen behavior, native editor/Undo/clipboard components without a displayed window, and model split/retirement/deletion ordering. Shared codec checks run through `bash scripts/test-easels.sh`. Compilation and component checks are separate from browser or visual acceptance; no functional browser tests were run for this batch.

## Local HTML archive export

File → Export Notes and the menu-derived command-bar command export the initiating regular profile. Before snapshotting, every original editor in that profile flushes its draft through its existing save owner; failed or composed drafts refuse export rather than silently exporting older content. The snapshot contains document ID, title, HTML and modification date. Shared document storage and editor history are unchanged.

The export controller belongs to the original physical window and Profile. HTML conversion uses the actual native attributed-text carrier; work yields between documents. ZIP preparation and destination copying run off the UI thread. A retired window/Profile cannot present or accept a later save dialog. User acceptance authorizes that exact immutable archive and destination. The save uses a staged copy and atomic replacement, so a preparation/copy failure leaves the previous destination intact. Temporary HTML/ZIP content is removed with its owned archive. An empty profile reports that there are no Notes to export.





## Paragraph gutter and formatting ownership



A transient formatting target retains exact body identity, document revision, attributed content and UTF-16 range. Changed contents (including attributes), cross-window publication, selection changes, geometry changes, editor retirement or a tombstone invalidate it. The inline menu leaves the original text view installed. Clicks outside it keep their ordinary destination; Escape dismisses the menu and preserves the selected paragraph. A native image sheet holds the original window/selection lease and cancellation inserts nothing. All successful changes follow the existing save/Undo/error path. Failed saves keep the genuine draft and still prevent closure.


The exact original tracking-area identity owns enter and exit. Entry can reveal retained valid paragraph metadata; movement selects the original body range and stops retargeting while the paragraph menu is visible. Exit retains metadata while hiding the idle control, and retains control visibility for an open paragraph menu. Scroll/layout recomputes only the retained paragraph anchor; it does not invent a pointer move or revive a control after exit. A cross-window revision, attributed-body change, read-only/tombstone state, marked text, sheet, key-window loss or owner detachment revokes action eligibility. Original body/selection/IME/Undo and actual menu actions stay installed. The extra empty layout fragment resolves to its actual end-of-body range, so its plus cannot target the preceding paragraph.


### Image picker and local image ownership


Parc keeps the exact originating Note window, body, attributes and selection instead of falling back to a later application key/main window. The sheet's one-shot callback reads a bounded regular local file, returns focus to the original text view and rechecks the actual target identity, window and current range before insertion. Cancellation, changed selection/content, composition, read-only/tombstone state or editor retirement inserts nothing. A known successful publication of that same editor's pending body preserves the existing target lease; unrelated saves do not. The actual native image edit owns selection, Undo/Redo and the existing local save/error path.


### Original native line targets

The original metadata producer receives the retained rich-editor container from the Notes controller, then uses its actual native body/layout manager and event point. Its `NSString.getLineStart(...contentsEnd:)` range **excludes the terminator**. Parc now uses this original content span, including native Unicode line separators. The image gate is precise: the original range contains an `NSTextAttachment` whose `NSTextAttachmentCell` has a nonnil image. Such a line has no gutter target; neighboring lines and attachments without an actual image are not conflated with that case.

The original newline branch compares the actual window point against the first-character anchor minus half the native rectangle height. At/below that boundary it produces a **zero-length action range at hitIndex+1**, a distinct icon-classification range at lineContentsEnd and its own native window anchor. The anchor incorporates positive enclosing-rectangle heights, authored-font offset and the recovered eight-point adjustment. Parc retains all of that transient metadata across geometry refresh and original-menu admission, so an insertion target cannot silently become a selected following paragraph. Actual paragraph formatting and native Undo still operate on the same original body; neither a new block nor copied text is created.


### Compact paragraph menu

The actual Notes factory installs **TextEditorFormatMenu.vertical** in the original document content. Its view uses a **34pt fixed width**, **2pt vertical padding and spacing**, a seven-point rounded named background and compact icon controls. The initial **eleven slots** are six paragraph actions, separator, Text Formatting group, separator, Insert Image and Link. The builder initializes its optional keyboard selection to nil. Actual checked formatting is independent of hover/keyboard highlight. The original control's hovered state does not select or format text.

The genuine FormatMenu reducer replaces the clicked Text Formatting item **in place** with Bold, Italic, Underline and Strikethrough. Other items and their order remain; there is no invented secondary popover. The group icon is the original 11pt bold `bold.italic.underline`; Aa/H1–H3 retain the recovered Nunito glyphs, and B/I/U/S use Nunito-Bold/Italic/Regular 14.4 with underline/strikethrough traits. Insert Image and Link use the factory Feather code points U+E981 and U+E998 from the bundled icomoon font at the original IconFontImageCache 20pt square. Menus are centered over their original gutter, contained horizontally in the editor and vertically within ten-point bounds; the original centerY equality has priority750. Parc uses the actual visible viewport and native scrolling when the menu is taller than the pane.

Every native button belongs to that exact menu and original document/paragraph admission, including the non-editing expansion. Closing the menu invalidates its retained controls before removal. A stale button cannot change a later range, dismiss a replacement menu or expand after an external document revision. Successful formatting still uses the real original text view, local save and native Undo, then returns focus to that body. Tooltips and native accessibility labels expose each compact action. Keyboard, accessibility and viewport-focus presentation of that existing menu is recovered below.


Paragraph-wide emphasis also edits the authored font when AppKit has temporarily substituted an emoji/glyph font. The same narrow `NSOriginalFont` contract already used by the durable carrier now applies before the shared native formatting transform and checked-state query. Explicit user fonts without that native marker are preserved; malformed metadata, unavailable explicit font styles and unsupported attributes still refuse the edit atomically. Native Undo retains the original attributed content. This change serves both Notes and Easel text without changing their stored formats.


## Native selection formatting

Selecting nonempty editable Note text presents the recovered horizontal selection menu: Format Selection, Bold, Italic, Underline, Strikethrough and Link. Whitespace-only selections and a sole attachment character do not produce the menu. The native Format Selection submenu offers Plain Text, Heading 1/2/3, Bulleted List and Numbered List, with checked state derived from the actual selected paragraphs. Inline emphasis keeps the selected text and menu; Escape dismisses the menu without collapsing that selection. The footer also provides keyboard and accessibility entry.

The menu retains the original body, document revision, attributed contents, full native selection ranges and window. Replacing text or formatting, changing the selection, moving focus to a different owner, starting composition, closing/hiding the editor or changing viewport geometry invalidates its actions. A retained old NSMenu cannot apply to a replacement selection. Automatic presentation keeps the body as first responder; explicit footer entry can focus the controls.

Discontiguous selections are one actual attributed edit, validated before mutation and saved through the existing Note session. Paragraph actions deduplicate affected paragraphs and map every UTF-16 selection through list markers and numbering. Undo restores original content and every selected range. A refused later range cannot leave an earlier range formatted. Link editing adds original document/window validation to the existing native link popover. No schema, storage or export change is involved.



### Selection control appearance and action lifetime





Fresh REA `ev_cc7739071517b716ef7a59702cc43f94ca4c19340301c33880b279a8a2a4d340` covers the horizontal layout; `ev_9fc82d8844798df2d91dc34e24e24f43e4b414cfccd2648961c55acbbbe89bb0` covers the Link flag. Full-image native imports and retained named-color evidence supply attribution. The separately retained 1.170 resource colors remain distinct from 1.122 mechanism evidence. Native per-slot width allocation/overflow, shadow and notification timing remain adaptations. AX/keyboard access of the existing selection bar is recovered below. Pressed fill now follows the recovered checked-then-hover helper rather than an invented AppKit highlight. Exact SwiftUI minimum-width redistribution was not measured. Recovered selected-index spring and immediate present/dismiss are recorded below. The retired Notes editor was not activated, and no functional browser tests ran. No historical pixel equality is claimed.

## Title and body keyboard ownership

The title is a plain `NSTextView` with its own native Undo manager, separately from the attributed body. It wraps with actual layout and retains its selection and IME draft. Pasting into the title reads the first plain-string pasteboard item and replaces newline characters with spaces; rich text and images are not silently accepted as title formatting. Initial forwarded focus chooses an empty title, otherwise the body, while an already active original responder keeps focus.

Title Tab and Down focus the body at offset zero without changing title content. Right at the title’s end does the same; ordinary Right and Shift-Tab retain native text behavior. Return and the native alternate-Return selector remove the title suffix beginning at the selection’s start and prepend it to the body, adding a newline before a nonempty body. The body then owns the caret at zero. The literal-Tab selector is consumed without inserting a title tab.

Body Up on its first visual line and Left at a collapsed start move to the title’s end. Ordinary body navigation stays native. Backspace at the body start is eligible only with default typing attributes: it removes the first body line and appends that plain text to the title, placing the title caret at the original join boundary. Styled/list/heading typing keeps the existing attributed editing behavior. A first line containing an image is refused with an error, preserving its original local bytes because the title cannot represent the attachment. Escape first dismisses the original paragraph/selection menu; without a menu it collapses the active field’s selection at its start. Composition, a different first responder, a non-key window, a sheet or a deleted document prevents boundary routing.

Both fields in a transfer are published to the original session in one atomic document write, validating both previous field values and the stable body ID. A disk error or cross-window conflict retains both drafts for Retry/Discard and blocks closure. Separate field-local Undo managers remain deliberate: Undo in the body changes the body, Undo in the title changes the title. Neither operation impersonates a whole-document Undo. Subsequent Undo saves use the existing field conflict checks; external body/title replacement invalidates that field’s stale editing history.


Current adaptations are explicit: UTF-16 scalar-safe offsets replace the reference’s inconsistent Character-count native offsets; CRLF is removed as one boundary; current AppKit glyph mapping drives visual-line checks; the supported local carrier represents default typing; paired durability and attachment-preserving refusal follow Parc’s local data contract. The title font and paragraph metrics are now source-recovered below. Current AppKit placeholder drawing and unclassified backend save-effect timing remain adaptations; no historical visual acceptance is claimed. This is source/component implementation, not a browser functional test or retired-Notes appearance claim.

## Remaining editor, menu and keyboard commands





Negative and out-of-scope findings, with the same helpers:

- Share-button / Firebase / URLInputter historical presentation, plus appearance, AX and motion, stay excluded or with NOTE23–NOTE26.

Native editor components cover body Return with an open automatic selection menu (nil index consumes; a keyboard index applies the selected original control and Undo), Return without a menu remaining native, and the three beginning-of-line selectors plus helper caret cases. No functional browser tests or retired-Notes appearance measurements were run.


## Native document presentation





## Native body defaults and parent palette




The original title placeholder producer and current native visibility rules are implemented below. Unclassified backend save effects and hover/motion remain unobserved. Original editor publication timing is now attributed below. The outer canvas/theme relationship is recovered in the document-appearance section. Retired Notes was not activated and no functional browser tests were performed. Notes remains prioritized through the remaining included interactions.

## Native title placeholder


Parc uses that same native property instead of painting text at the container origin. Empty focused and read-only titles keep the hint; real text and marked composition suppress it through AppKit. The attributed hint uses the actual Nunito ExtraBold34 title font, paragraph metrics and separately attributed surviving appearance-specific color. Title cursor and selected-text background now use their original named-style consumers as well. The hint is never inserted, copied, saved, selected, or registered as an Undo edit. Native title Undo/Redo, composition commit, retained save-failure drafts and tombstone ownership continue through the original local editor/session.



## Body publication and local save barriers

The actual Notes body publisher uses **Combine throttle, 0.5 seconds, DispatchQueue.main, latest=true**. Parc now uses that same publisher contract: an initial eligible native edit is scheduled on the main queue, and subsequent edits in the interval coalesce to the latest complete attributed body. This is a throttle, not a debounce that keeps postponing publication while typing. Title changes publish immediately through their separate path. Saving the body neither combines native Undo steps nor erases the title's separate Undo manager.

The callback stays with the original editor/session and its latest uncomposed draft. Composition revokes older queued input; only committed text is eligible. An original close/export/retry barrier commits composition and flushes the exact current draft synchronously. Title/body boundary transfers retain their existing atomic paired write. Discard and document tombstones revoke pending callbacks. A failed scheduled write retains native text, selection and Undo, reports the actual failure and refuses closure; it does not repeatedly retry without another edit or explicit Retry. A competing window's body update remains protected by the real expected-field comparison, while an independent title update survives a later body save. The local footer reports a pending save truthfully.





## Gutter icon classification and original list artwork

The actual `101b4ac90` producer classifies the original metadata icon range, preserving its separate newline insertion/action range. It recognizes the original tab-delimited ●/✺ bullet prefix or decimal marker within the first five characters before considering font. `10171b824 → 10090d954 → 10090dac8` selects the **first actual NSFont run**, skipping missing fonts and stopping immediately; absent fonts use the recovered body font. Exact point sizes **32/26/22** yield H1/H2/H3 regardless of family/boldness or paragraph headerLevel. Other nonempty text yields Aa. Empty means only newline characters removed, not whitespace trimmed. Only an exactly collapsed caret at that range may supply its typing-font heading; otherwise empty text yields Plus. Existing image-bearing attachment suppression, native text ranges, selection, IME and actual menu action/Undo ownership remain unchanged. Fresh REA: `ev_744d262a2227f6806e1692a4b523ce46e41299b82ecc74e36c728e885e5d683e`.

Current AppKit's genuine NSTextList uses • and decimal-with-period markers. Its existing exact marker validator supplies those two list icon adaptations only when the authored marker agrees with its actual list record; paragraph/list metadata without the marker cannot invent an icon. Stored text/fonts/list attributes are never rewritten by display classification. The menu's semantic checked/action state remains distinct from the gutter's visual font classification.



## Native document appearance and semantic ink


Parc now draws that named surface for the actual Note editor and load-error view and inherits native light/dark appearance. The surviving 1.170 resource provides **white at 85% alpha** in light appearance and **black at 50% alpha** in dark appearance. BodyText, TitleText, TitlePlaceholderText, Cursor, SelectionTextBackground and Link use their separately attributed light/dark resource variants. These are current surviving bytes for proven 1.122 named consumers, not a claim that their historical bytes or final rasterization were identical. The installed retired feature was not activated.

The current page-host and pane white layers previously obscured that transparency. Only an actually displayed NoteCanvasView now clears its pane backing; the common page host is clear while such a pane is displayed. The same original root window surface — the SPACE17 ThemeRendererView Metal/material underlay — remains below it. Ordinary browser/start/error/Easel presentations restore opaque pane backing, and the page host restores white when the last displayed Note leaves. Parked Notes do not determine the visible backing. Clearing those Parc-owned white layers is a narrow hierarchy adaptation so the recovered translucent fill can composite over that underlay.




Exact-source checks passed for 126 Swift application sources and the actual native editor/codec/export components: 32 NoteStore, 314 NoteEditor, eight original-editor retirement, 23 NoteTabs, 310 shared rich-text style and 20 Notes export assertions. Checks exercise light/dark color resolution, semantic save/reopen/private clipboard/formatting, legacy decoding and fixed authored colors, appearance changes without file/revision/Undo/selection mutation, and dark-appearance HTML export. No browser functional tests or displayed Notes window were used. The gutter/compact-menu palette is completed below. Outer compositing and Space content-appearance inheritance are implemented above; unobserved final rasterization remains separately bounded. Recovered format-menu motion and the haptic negative finding are recorded below.

## Gutter and compact-menu appearance

The existing gutter, paragraph menu and its rows now inherit the actual Notes document appearance through native dynamic named-color equivalents. The recovered `GutterButtonView` label always requests its unselected glyph and separately uses FormatMenuText for disclosure. Menu Text/Aa/H1–H3 explicitly retain FormatMenuText even when checked; list and emphasis glyphs use SelectedMenuItem only for actual checked formatting. Hover/keyboard focus remains distinct. Gutter selected, menu selected and shared hover backgrounds keep their separate named consumers and alpha values.

Original menu surface `1016f20a8` uses FormatMenuBackground with radius7 and a **0.5pt FormatMenuBorder only in dark appearance**. Actual item state helper `1016f42ec` prioritizes checked format over hover/keyboard selection; fresh REA `ev_4bf8e99e28ea1d0f71f73d5a762f8b01bd160870513744e5f8beb4e6cf982778` plus full-image imports establish the branch/name chain. Names and owners are Arc1.122; the separately retained1.170 assets supply local light/dark sRGB values. No installed resource is loaded at runtime, and retired Notes was not visually activated.


## Format-menu motion and haptic negative finding




## Keyboard, accessibility and viewport focus

Title/body Tab/Return/arrow/Backspace/Escape boundaries and native Find remain the NOTE13 contract. This section recovers keyboard, accessibility and viewport-focus presentation of the existing gutter, compact paragraph menu, selection menu, title/body fields, load-error surface, footer Retry/Discard, link popover and image sheet. It does not add editor commands, change pressed/glyph drawing or invent shortcuts. VoiceOver/Full Keyboard Access were not driven as acceptance.



Pointer/gutter presentation therefore keeps the body first responder with `selectedIndex` still nil. Body Down/Right continue to dismiss that menu through the existing NOTE13 command owner. Explicit footer/AX Format Paragraph or Format Selection focuses the compact menu or selection bar so arrows can move `selectedIndex` from nil onto the first or last enabled control, Return/Enter/Space activate `didPressEnter`, and Escape `didDismissMenu` restores the original body. Automatic nonempty selection presentation still keeps the body responder. Removing a focused menu restores the body only when that owned menu existed and first responder is the menu, a descendant, the window, nil or a detached view; it never steals another `NSTextView` or a live non-owned control such as footer Retry/Discard.

The hover gutter refuses first responder and draws no focus ring: it is an AX press target, not a key-loop stop. Title and body are native text areas; the title uses the recovered **Title** placeholder as its accessibility name. The load-error surface is an AX group whose heading is **Can't load this note**. Footer Retry/Discard and Format Selection/Paragraph are AX buttons chained after the body when visible; the last control is not wrapped back to the title, so the window key-view owner can still enter and leave the note pane. A stacked narrow save-failure hides the format fallback so Retry/Discard remain in that chain. Explicit footer/AX entry scrolls the presented paragraph or selection into the current viewport before menu geometry is measured; pointer, automatic presentation, native Find and forwarded page focus do not. Focused compact-menu and selection-bar controls scroll into view as arrows move `selectedIndex`. Image-sheet completion (success, cancel or failure) returns focus to the original body; a successful insert then reveals the new attachment. Link-popover close is a one-shot `NSPopover.didCloseNotification` for the `EaselLinkEditor` popover and restores that body unless another original text view or live non-owned control already owns focus. Current AppKit matching uses the editor type because this SDK has no `positioningView`.

Native component checks cover gutter body-responder presentation, footer/AX menu focus, nil `selectedIndex` then Down/Escape restore, title-focus preservation, load-error/footer/title AX names, visible Retry/Discard key-loop membership and image/link focus-return helpers. No functional browser tests or VoiceOver/FKA acceptance runs were performed.
