# Address and command bar

**November 9 address editor:** clicking the sidebar, page-toolbar or popup URL
opens the separate 350-point compact editor anchored to that control, as in
addresses and native search suggestions, and navigates the original current
tab. It does not offer application commands, document actions or Actions scope.
Cmd-L and Cmd-T retain the large command palette and its existing command and
tab-switching features. The compact surface shares the original page/profile
lease, genuine native navigation requests, IME, selection and dismissal owner.


The command bar is a temporary child panel of one browser window. Cmd-L begins with the current native page URL selected; Cmd-T begins with an empty field. It uses AppKit's field editor for selection, undo, input methods and ordinary text copy. Explicit native-result selection can project provider edit text while retaining the typed query and original request; eligible default results can now select their genuine inline suffix while typing.

Rows retain one of three distinct actions:

- Chromium autocomplete rows keep the original `PCNativeSearchNavigation` token. Activation passes that token to the existing native loader, preserving its classified URL, POST content, headers, profile and one-shot consumption.
- Existing-tab rows keep the original tab ID and display **Switch to Tab**. Activation uses the existing tab/Space/window selection and transfer path; it does not reload the tab's URL.
- App-command rows keep a weak reference to the original registered menu item, its owning window and the shortcut-registry revision. Availability and activation both use the actual menu target's validation. Activation passes that same item as sender, retaining dynamic tags and represented objects. Native text-editing commands and Copy URL keep their separate focused-responder meaning. Manage Passwords retains its existing genuine engine route.



A session leases the original Space, profile, tab, Peek, browser wrapper, page and window identity. Closing, transfer, selection change, profile change, sheet/security presentation, app deactivation or panel key loss cancels it. The original responder and native text-selection range are restored on Escape or a committed action only while that owner remains eligible. An outside click keeps its new focus. A previously dismissed panel cannot clear a replacement panel. Posted favicon callbacks use the existing exact-profile, exact-URL database service and cannot update a dismissed or replaced owner.

The existing Tabs → Copy Page URL command uses Cmd-Shift-C. With the command bar open, it copies the highlighted row's actual URL and is unavailable for a command or unresolved input row. Otherwise it copies the current native page URL, including the active Peek. Cmd-C remains the field editor's ordinary selected-text operation.

## Reference and adaptations


- Installed Cmd-L selected the complete current URL. Cmd-T showed other open tabs with **Switch to Tab**, followed by history rows. Typing `arc` showed **Archive Tab** with its shortcut before search results. Down changed the highlighted row without changing the input; Escape returned focus to the original renderer. The reference used a dark rounded panel over a light Space, single-line 50-point rows, inline subdued host text, a leading result icon and trailing shortcut/arrow badges. No command or destination was executed during reference capture.



## Appearance and theme








- Title CommandBarTextPrimaryColor (0.8), subtitle CommandBarTextSecondaryColor (0.33). Selected: white and white at 0.5.
- A selected favicon sits on a white 24-point tile; a hovered one has none. Type Travel glyphs always have a tile: CommandBarAccessoryBackgroundColor with CommandBarAccessoryForegroundColor ink, white with the selected colour when selected. Keycaps and the Switch to Tab arrow follow the same pairs.


### Checking appearance in a running build

The offscreen harness can't sample what's behind its window, so these numbers need a running build. Use a dark green Space, Cmd-T, and read pixels from a screenshot (halve 2x captures):

- Divider under the field: one device pixel, white at 0.1, about 15–20 levels above the panel, inset 12 points.
- Selected row: the Space's `focus` at 0.81 over the panel; Josh's green measures about (20, 111, 67) over black.
- Selected field text: the palette's `subtitle`, about (90, 125, 108) on that green.
- Shadow: a soft black falloff around the bar, heavier below, with no visible edge where it stops.
- A press just outside the bar, in the shadow, lands on the page and closes the bar.
- A light Space shows a light bar in a dark-mode Mac, and a dark Space a dark one.

Offscreen renders and the selection fade strip are in `work/cursor-review-images/cb-look/`. `tests/CommandBar/AppearanceTests.swift` checks:
- the surface layers and views in both appearances;
- the shadow window, its mask and its mouse transparency;
- the hairline;
- the row highlight's attachment, geometry and fade;
- cell tiles, colours and type, including after an appearance change.
## Result row content




## Split submission

The field editor's Option-Return command opens an eligible selected navigation or original tab in a new split pane immediately after the focused pane. The table's Option-Return uses the same owner. Ordinary Return, clicks, native editing and marked-text composition retain their existing routes. Commands and password-management rows have no split destination. An unavailable destination leaves the command bar open; no tab or placeholder is created.

A native suggestion passes its original `PCNativeSearchNavigation` through the existing loader. An unresolved address/history input is classified by the original profile, then passes that token through the same route. No target URL is loaded as a substitute for the classified POST, headers or transition. The shell's URL is only model metadata. Existing eligible tab rows reuse their exact identity. A tab already in the split receives focus without cloning or reordering.

The window leases the original session, Space, profile, selected pane IDs, focused tab, browser and page. It validates the original native window/security capability after panel dismissal. Pending classification is cancelled by a replacement command session, source URL/loading change, owner/selection loss or window key loss. The model transaction validates the expected selection and inserts the pane in one publication. A new request cannot overwrite an existing tab identity. The original pane orientation and relative proportions are retained; normalization and a maximum of four panes follow Parc's existing split model.





## Website search scope



Accepted entry clears the field and shows the actual native engine name in a scope pill. Native `snapshotChanged` supplies the active identity and scoped results. Publication revisions order snapshots; they are never compared to a navigation token's distinct search-preferences revision. A new query clears old offers immediately. The field keeps its own typed text; asynchronous provider snapshots do not replace composition or text selection.


Escape first leaves the native scope, restores the command session's original input selected in its native field editor, and leaves the command bar open. A second Escape dismisses the session and restores its original eligible browser responder. Cmd-T/sidebar sessions restore their original empty input using the same owner. Backspace on an already empty scoped field instead restores the immediately preceding unscoped query with the caret at its end. Deleting selected nonempty query text remains an ordinary native edit and leaves the scope active; another Backspace exits. Each accepted re-entry records a fresh preceding query. The three recovered native commands are `deleteBackward:`, `deleteBackwardByDecomposingPreviousCharacter:` and `deleteWordBackward:`; marked-text composition is not intercepted.

The header keeps the observed input top edge while scoped results grow downward: empty entry is a compact 64-point surface; result rows reuse the recovered 50-point height. The pill has a truncated engine label and accessibility scope value; its default fill is the theme's `focus` ([Appearance and theme](#appearance-and-theme)), and its site colour, glow and the Tab hint follow [Website scope colour, pill and Tab hint](#website-scope-colour-pill-and-tab-hint). The offered hint has a native press/focus action and explicit Tab help. Constrained narrow/sidebar layout and immediate resizing are Parc adaptations.

### Website scope colour, pill and Tab hint




Differences that remain:

- Private windows take no favicon colour: the favicon service refuses off-the-record profiles (`native_favicons.mm`, `Request`), so a non-bundled engine keeps the theme colour there.
- An engine without overlay 299's fields gives every scope the theme colour and no host-matched hint; the app checks for each field before reading it.

### Scope mechanism reference



Installed Arc1.170 appearance was inspected through the real Search Wikipedia/Tab accessory, Tab entry into an empty pill, a typed scoped query, Escape restoring the original current address selected and a second Escape returning renderer focus. No Return/navigation or preference change was executed. Hover/pressed/disabled reference appearance, scope menus, full AX/keyboard-layout behavior, provider ranking, exact animation and haptics remain distinct comparison work.

### Space entry and profile catalog

Space entry requires the exact currently selected native offer, its actual originating profile preference, no active scope and new field text exactly equal to the preceding query plus one space. It reuses `enterScope` before issuing an ordinary autocomplete update. Failed or stale offers fall through to ordinary text editing. The native preference `omnibox.keyword_space_triggering_enabled` supplies `PCNativeOmniboxScope.spaceTriggerEnabled`; its changes invalidate existing offers through the same search-preferences revision. Parc retains the registered Chromium preference default and any user/managed value. No global key monitor, URL recognition or second navigation pipeline is involved.






Installed Arc1.170 inspection confirmed Tab entry, a Space remaining ordinary text in its configured profile, empty Backspace restoring `wikipedia` with a caret, re-entry, selected-query deletion retaining the pill, a second Backspace exiting, and Cmd-T scoped Escape restoring an empty open panel before a second Escape returned original renderer focus. No destination or preference action was executed. Scope switching, full Type Travel ranking, exact unavailable-provider visuals, animation/haptics, all IME/layout combinations and the complete restoration matrix remain separate evidence boundaries. Extension keyword callbacks have the separate native owner below.

## Contextual Type Travel: Focus on a Space

Named Spaces now participate in the ordinary command bar as **Focus on [Space]** actions. The row uses a separate Space icon/name capsule, the same 50-point result geometry and the existing hover, Up/Down, Return, click and accessibility activation. Empty input retains its tab/history rows; website scope retains only the genuine native scope results. Space commands have no URL to copy and no Option-Return split destination.

Each action carries the original Space and profile IDs. The originating command session still leases its exact window, Space, profile, tab, page and Peek. Availability uses the existing Space command gate; activation dismisses the panel, validates the original session and destination again, then calls the same `selectSpaceFromUser` transaction as the Spaces menu. This preserves per-Space split/focus continuity, actual profile preparation and the checked-current-Space no-op. Private and popup windows do not publish Space actions. Window/security changes cannot redirect an old action into another window.

Model publication refreshes the names and icons without changing stable action IDs. Deleted Spaces, removed profiles and profile reassignment cannot satisfy a captured target. If an explicitly highlighted contextual row disappears or stops matching after publication, it stays disabled until the user edits or selects another row; Return cannot silently become a web search. Duplicate names display the actual profile label, and the full name/profile remains in the native accessibility label and tooltip. This disambiguation and expired-row presentation are Parc adaptations.






## Highlighted result text and ordinary Tab

Arrow and direct native table/accessibility selection now display the selected provider's real edit text in the field. The typed provider query stays separate from this temporary projection. A matching suffix is selected using UTF-16 ranges; a non-prefix completion is selected in full. Moving onto a command, original-tab switch or typed Space/folder action restores the preceding query instead of turning that action's label into a search. Provider publications retain an unchanged field selection, so an asynchronous result refresh cannot undo a native caret adjustment.

Tab first enters an actual selected website-scope offer, as before. Otherwise it accepts the displayed completion and places the native caret at its end without navigating, submitting a command or traversing to a different key view. The native explicit-Tab capability is limited to genuine search-what-you-typed, search-suggestion and calculator matches. Other native results can still have their already projected text selection collapsed by Tab. Search-history and other-engine results are not treated as generic search-suggestion actions. Return and Option-Return retain the original complete navigation token; accepted edit text never replaces its POST body, headers, transition or original Profile. Actual subsequent typing starts a fresh query through the existing producer. Composition and normal AppKit editing remain in their existing owner.



## Contextual Type Travel: Open Folder

Named ordinary folders in the originating profile's Spaces participate as **Open [folder]** actions. Activating one dismisses the command bar, validates the original window, profile, folder and ancestor path, then uses the shared sidebar reveal transaction. It focuses the actual destination Space, expands the ancestors and the target when it has children, closes a covering Library, reveals the sidebar, scrolls the original row into view and requests its attention highlight. It does not open all the folder's tabs or change the selected page merely to highlight a folder. Space switching retains its existing selection/focused-pane continuity and native security gates.

The result carries the original folder ID, Space/profile IDs and ordered ancestor IDs. Duplicate names expose their actual Space and ancestor path in the row, tooltip and accessibility label. A rename refreshes the label without changing identity; reparenting, removal, profile retirement or a foreign-profile destination cannot retarget the chosen action. The existing expired-contextual-row rule prevents an explicitly selected vanished folder from becoming a web search on Return. Mouse/keyboard/AX activation uses the same action. Private/popup and active Peek ownership refuse the route. Empty input, native website scope, native navigation tokens, ordinary menu/Notes commands and Option-Return remain with their existing owners; a folder has no URL to copy or split destination.





## Suggestion deletion

A removable native suggestion exposes **Delete Suggestion** while hovered. **Command–Option–Delete** removes the highlighted eligible suggestion; VoiceOver has the same named custom action. The field keeps its original provider query and the command bar stays open. Removal clears the projected completion, keeps the adjacent surviving row highlighted, and waits for the same provider's replacement publication. Native marked-text composition and ordinary editing remain untouched. Commands, original tabs, Focus on Space, Open Folder, and local empty-input recent visits are not inferred to be deletable from their labels or URLs.

Eligibility belongs to the live native session. The original delivered `PCNativeSearchNavigation` object must still match the session publication, exact Profile, owner window and original document; newer query/results, scope or engine changes, navigation, transfer, close, cancellation and profile retirement revoke deletion. The session retains the complete originating `AutocompleteMatch` only while its real controller/providers live. On accepted removal it revokes all deletion offers, stops provider work with Chromium's interaction reason, consumes the exact target token and calls `AutocompleteController::DeleteMatch` with the original full match. It never rebuilds a request or deletes global history by a displayed URL. Other navigation tokens keep their full POST/headers/transition ownership.



Chromium persists through the actual provider: local History/Shortcuts removal and search-provider remote deletion keep upstream behavior and private-profile restrictions. Acceptance means the provider operation was invoked and its result set is refreshed; it is not a guarantee of successful remote deletion. A bookmark or typed result may remain independently after its history backing is removed. Parc adds no service, separate history database or context-menu action. The xmark glyph, 23-point hit area, native accessibility action/announcement, exact post-removal row clamping and immediate updates are explicit adaptations; complete pointer/pressed/theme/motion/haptic parity remains open. The native unit, whole app and real inert AppKit row components are checked separately from browser behavior; no functional browser tests ran.

## Force-open while keeping the command bar open

**Command–Return**, **Command–keypad Enter** and **Command–Option–Return** open an eligible web result in a new background Today tab and keeps the command bar, query, highlight and field-editor selection open. Each accepted invocation creates a distinct unread item in the original Space and Profile. It does not focus the new page, add a split pane or switch to an existing tab with the same URL. The original selected tab, focused split pane and per-Space return arrangement remain unchanged. Option–Return retains its separate split action; ordinary Return retains navigation versus exact-tab switching.

The result keeps its real Chromium request. Native background creation copies the immutable classified destination, transition, POST content and headers into a fresh one-shot operation, creates an actual background WebContents, attaches it to the original window's parked page owner, and loads that request. It never issues a preliminary GET of the search URL. The original published token stays available for another background open, ordinary activation, completion or its genuine deletion action. An existing web-tab result uses that original tab's current address through the real classifier; it creates a new page rather than transferring, splitting or resetting the original. Typed menu/Space/Folder actions retain their ordinary action and dismissal. Parc local Note/Easel tab results retain exact-ID switching rather than becoming renderer URLs; this local-document boundary is an explicit adaptation.





This route reuses the existing opaque native navigation token, background-operation generation, scoped query and original owner checks. Typed folder force-open actions retain their existing copy behavior; ordinary commands and local-document identities retain their established dispatch. There is no new window factory, URL reconstruction, history clone, key monitor, motion or haptic. Shift-only Return remains a distinct original flags-4 path associated with excluded Instant Links evidence; this batch does not assign it a new ordinary navigation meaning. Control–Return, Command–Shift–Return and other unproved combinations remain native responder operations. The full modifier matrix and held-modifier presentation are not inferred from the included force-open branch.



## Default-result inline completion

Typing at the end of an ordinary command query can now select the suffix supplied by the genuine native default match. The typed query remains separate from displayed completion, and Return/Option–Return/Command–Option–Return retain the identical navigation token with its POST, headers, transition and original Profile. A command, tab, Space, folder or local document row never acquires a suffix from its title or URL. Existing website-scope entry takes precedence; scoped results keep their existing separate behavior.

The native query captures whether automatic completion is eligible. That value survives asynchronous Profile acquisition and preferences refresh and drives Chromium's `prevent_inline_autocomplete` input. A publication exposes completion only for `AutocompleteResult.default_match()` with `allowed_to_be_default_match` and a nonempty `inline_autocompletion`; it appends that actual provider suffix to the actual input. Explicit arrow/Tab completion continues to use `fill_into_edit`, a distinct provider field. Legacy callers and initial address restoration suppress automatic completion.

The field editor rechecks actual selection, marked text, key window and native session/source ownership before applying a publication. Backspace, other native deletion, mid-string edits, explicit row/caret selection and composition suppress automatic replacement. An unchanged publication preserves the native caret. Deleting only a selected suffix leaves the literal query; the next insertion can complete again. AppKit's actual text-storage replacement record distinguishes deletion from replacing a selected long URL with shorter typed text. Tab accepts a displayed suffix, Escape restores the original eligible responder, and the existing source/document cancellation and original-request submission routes remain authoritative.



Current Chromium default ranking, actual text-storage deletion detection (including non-keyboard deletion), UTF-16 range safety, initial-restoration suppression and explicit caret-intent retention are Parc adaptations. No motion or haptic is added. Broader ASE archetype/ranking behavior, the unresolved state-keypath branch, automatic scoped/Type Travel completion, undo grouping parity and all native input-method/accessibility appearance combinations remain distinct. The existing focused editor component and full source compiler checks cover this bounded implementation; no functional browser tests ran.


## Website scope menu

The active website-search pill now opens one native menu from click, secondary click or its accessible button action. The menu offers **Remove “[site]” Site Search**, **Change Site Search**, **Manage…** and **Learn More**, matching the retained menu builder and separately inspected installed appearance. Change lists the originating Profile's actual enabled website templates, excluding the current engine, shadowed keyword records, extension callbacks and starter-pack commands. Switching preserves the provider query and its native edit range; a completion projected from the previous engine is dropped rather than turned into a new request. Ordinary Return, Option–Return, background force-open and native result deletion keep their existing complete request owners.

Remove deletes the actual saved TemplateURL through `KeywordEditorController`, with its current `CanRemove` and `ShouldConfirmRemoval` gates. Default, protected policy and starter entries remain unavailable. Required confirmation uses an owned sheet; cancel retains the query/selection, and retirement closes only that sheet. An OTR session can change scopes but cannot mutate the regular profile's engines or open its management page. The catalog's existing recorded-once policy prevents a deliberately deleted bundled template from reappearing on the next service notification or launch.






## Cyclic result selection

Up and Down now wrap among the current query's actual results: Up from the first selects the last, and Down from the last selects the first. The selected row scrolls into view without moving focus out of the native input. A genuine native result can project its original completion with the suffix selected; menu actions, Space/folder commands and local-document tabs retain their typed identities and do not become editable search strings. Selection never activates a row.

Traversal uses the live table snapshot and the provider query, not a temporarily displayed completion. The existing original-result selection path retains opaque navigation requests and invalidates pending background opens when their selected target changes. Dismissed sessions, expired original owners and marked-text composition refuse movement. Empty and single-result states are safe; explicit expired rows retain their disabled submission behavior. Clearing the query preserves the separate sidebar cursor and the existing empty-query recent-row policy. The current native `moveUp:`/`moveDown:` bindings and table arrows share this route; no physical-key shortcuts or global input monitors are added.


Installed Arc1.170 query-only inspection confirmed first-to-last Up, last-to-first Down, native suffix selection, selected-row scrolling and Escape restoring the original page focus. No result or navigation was executed. Parc's existing empty-query recent-row clamp is a retained adaptation; broader empty-query ranking, physical-key aliases, complete IME/AX/layout behavior and exact transition motion/haptics remain distinct. No animation is added, including under Reduce Motion. The actual AppKit table/editor component and full source compiler check cover this bounded implementation, not browser runtime acceptance.


## Pointer hover and original-row activation

Moving the pointer over a result now highlights that row without changing the keyboard-selected result, the input completion/caret, or the target of Return and Copy URL. A selected row keeps its selected appearance even while hovered. A genuine removable suggestion exposes its existing Delete Suggestion control from this same row hover owner; clicking that native control remains separate from opening the row. Mere row appearance does not create hover.

An actual row mouseDown submits its captured original result directly. Decorative content cannot fall through to stock table selection or steal input focus. Native request tokens preserve POST/headers and original Profile/document/window; original tab/Note, menu, Space and folder targets remain typed. A retained row/accessibility action belongs to one result publication and cannot activate a replacement with the same display ID. Disabled/expired results, marked text, invalid original owner, hidden/detached rows and inactive windows refuse. Existing supported Option and Command–Option submission variants share the split/background owner; pointer background-open preserves the previously selected keyboard result. The complete modifier universe is not inferred by this batch.


The installed Arc1.170 selected-row/input/focus reference from cyclic selection remains applicable. Modern hover/pressed appearance was not observed: permitted automation lacks a standalone pointer-hover action, and no personal result was activated. Existing selected geometry plus the subtle native hover color, strict publication/window cleanup and refused unsupported modifiers are explicit Parc adaptations. No animation/haptic is added, including under Reduce Motion. Actual offscreen AppKit row/table components and the full application compiler check cover this source slice; no functional browser test or runtime acceptance is claimed.


## Contextual Favorite and Unfavorite

**Favorite Tab** and **Unfavorite Tab** are now typed contextual command results. The action captures the originating sidebar's ordinary-tab collection before the child panel takes key focus; with no collection, it uses the original active ordinary tab. An unsupported folder, whole split or split-pane collection never silently falls back to that tab. All targets must be outside Favorites for Favorite, or inside Favorites for Unfavorite. Mixed membership offers neither command. Existing same-profile tab results already cover switching to Today, pinned and Favorite tabs by original ID; these new commands change membership rather than activate another result.

Favorite appends the original items to the Profile's Favorites. Unfavorite places them at the beginning of Today in the originating current Space. The atomic model transaction retains each original ID and current URL, existing pinned home, history, selected pages and per-Space return arrangement. Promoting a Today snapshots its current URL/title as its saved home; returning to Today uses the existing Today boundary. Neither action loads a URL, closes a page or reconstructs a native wrapper. A failed durable write leaves the whole model unchanged and presents the existing error surface.

The result owns original item IDs/incarnations, kind, parent folder, source Space and Profile. The shell also leases its physical window, original selected page/panes, tab ownership and any actual native browser/page or local Note/Easel editor. Private/popup/Peek, security sheets, close/retirement/transfer and changed source/destination ownership refuse admission. Current title/URL updates from the same item are retained; an intervening membership or parent change cannot retarget the action. The original payload is revalidated after normal panel dismissal. Explicitly selected expired commands stay disabled, and pointer/AX dispatch retains the existing exact result publication. Website scopes, native completion/deletion and classified requests remain separate; Option-Return refuses these non-navigation rows, while background force-open retains their ordinary typed action/dismissal.





## Contextual Type Travel: Pin to an existing folder

**Pin to [folder]** now retains the original sidebar collection, or the original current item when there is no sidebar collection. It supports an ordinary Today/pinned/Favorite tab, a whole folder tree and a whole persisted split. A selected unsupported item never becomes the current tab implicitly. The actual folder name is a capsule with its original same-profile Space/ancestor context; live sources, target parent, hierarchy, Profile and original tab creation identities are revalidated before an action can run.



The command retains the same native row, pointer publication, keyboard/AX activation and explicit stale-row refusal as the existing typed actions. It has no navigation token, cannot be deleted as a suggestion, and never becomes scoped-search input or a split navigation. **Option–Return refuses this non-navigation row.** Command–Option–Return follows the distinct copy-to-folder action below; it never silently moves the originals for a copy gesture.



## Contextual force-open: copy into an existing folder

Command–Option–Return on **Pin to [folder]** copies the captured tab/Favorite, folder tree, whole split or ordered collection into that original same-profile destination. It dismisses the typed-action panel, retains the original selection/pages and creates fresh item, folder and split identities in one durable save. Original title/custom title, saved title, mute, folder disclosure, split orientation/proportions/anchor and mixed child order survive. The original folder row and owner gates remain authoritative; Option–Return is still unavailable, and a stale collection or destination never becomes a different target.



Original and copied trees are validated before the single save and original windows/pages/local editors are retained. Source retirement, transfer, Profile removal, pending sheets/security, changed command selection and replaced originals refuse. Copies do not close a page, so no beforeunload transaction is bypassed. Typed Note/Easel items now use the recovered reference-copy branches: fresh sidebar IDs retain the same existing document ID. The exact Profile's real document store validates each original file, live session and referenced assets before the mixed collection can commit. A local URL alone cannot authorize an alias. No document, image or embedded-object bytes are rewritten, and typed aliases never enter renderer eager-opening. See [typed document reference copies](folder-commands.md#typed-note-and-easel-reference-copies). This replaces the earlier unverified assumption that these branches required deep document clones.


## Actions scope: command-only Type Travel

Tab on an actually empty ordinary input opens **Actions**. It shows the original
registered menu commands, app-owned Manage Passwords and the existing typed Space, folder, pin/copy, Favorite
and Rename actions, up to 100 results. Queries filter these same commands; there
is no URL, history, tab-switch or default-search fallback. Return, pointer and
accessibility retain their existing original-target dispatch and current
availability checks, including the separate force-open folder-copy disposition.
The Actions capsule is a static scope label; website pills keep their actual
provider menu. No application-wide shortcut or `>` prefix is invented.

Empty Tab toggles out of either scope through its own restoration owner. Empty
Backspace leaves Actions; deleting nonempty/selected text remains native editing
and requires a later empty-input action to exit. Escape leaves Actions with empty
input in the open command session; the next Escape dismisses it and restores the
original eligible responder. Nonempty Tab keeps native editing/completion and
never executes a command. Marked text is handled by the input method first.
Actions entered from the sidebar search session preserves its separate keyboard
highlight and resumes that owner on exit.

The command-only state belongs to the original panel/window/Profile session.
Entering invalidates the preceding ordinary native request with empty input;
Actions edits never start native autocomplete. Native publications cannot replace
the command rows or produce a site-scope error inside Actions. Exiting starts a
fresh ordinary request in the same native session. Existing document, selection,
window, profile, security, modal, deactivation and retirement cancellation applies.
No native navigation token is converted to text or revived across scope entry.

input constructs `(ScopedSearchType.typeTravel, ScopedSearchEntryStrategy.tab)`
query/edit policy; Escape is mode 0 and Backspace mode 1. Original metadata and
value witnesses resolve the enum/tuple; fresh REA pseudocode is cross-checked
against those instructions, rather than treated as original Swift source.

command-only `space` results, empty Tab toggle, empty Backspace exit, re-entry,
nonempty Tab retention and Escape-to-empty-panel followed by renderer return.
No command was executed. The existing local command matching/order and admitted
algorithm. Native text/label geometry, the theme-focus Actions capsule, empty-result message, AX
help, sidebar placement and immediate Reduce Motion-compatible presentation are
explicit adaptations. Full command coverage, exact ranking, all scope/IME/theme
variants, pressed/hover geometry, transitions and haptics remain separate.


## Typed Type Travel commands


|---|---|---|
| 3 / 4 `undoAction` / `redoAction` | **Undo [action]** / **Redo [action]** | the window Undo stack's current step (`FolderUndoManager`), the same step Edit → Undo names |
| 1 `moveToSpace` | **Pin to [Space]** | the sidebar's Move to Space transaction (`prepareSidebarSpaceMove`) for the captured sidebar selection or current item |
| 13 `moveToNewFolder` | **Pin to New Folder** | New Folder with *n* Items (`SidebarFolderFromItems`), its Undo step and rename prompt |
| 19 `duplicateCurrentTab` | **Duplicate Current Tab** | the sidebar's Duplicate transaction, as Tabs → Duplicate |
| 21 `replacePinnedTab` | **Replace Pin with Current Page** | new: the pinned or Favorite item keeps its identity and takes its current page as its saved home (`BrowserStore.replaceSavedHome`) |
| 23 / 24 `convertTo…SplitView` | **Convert to Horizontal/Vertical Split View** | the split pane menu's orientation flip |
| 25–28 `add…Split` | **Add Right/Left/Top/Bottom Split** | the split pane menu's Add, which opens the insertion panel |
| 8 `newWebDocument` | **New [document]** | a new tab at the type's creation URL in the originating Space and Profile |
| 34 `openAirTrafficControl` | **Air Traffic Control** | Settings → Links and its Air Traffic Control editor |

Four other typed candidates are served by Parc menu items, which keep their menu
words: **Toggle Sidebar** (case 17, View → Show / Hide Sidebar), **Reset Tab**
(20, Tabs → Reset Tab to Original URL) and **New Parc Note** (31, File →
(Parc Folders, Parc Profile), and typing "arc note" still finds it. The
coordinator confirmed this name on November 1.

to its literal and localization comment. Undo/Redo append the action name to
"Undo "/"Redo " (comments "Undo an action"/"Redo an action"). Move to Space
builds "Pin to " plus the Space name (comment "Action to move to Pinned in
<space>"); Parc's matching also accepts "move". A web document is "New " plus
Duplicate, Undo and split cases reach the window's own owners rather than a URL.

are Google Doc (`doc.new`), Google Sheet (`sheet.new`), Google Slide
(`slide.new`), Figma Document (`figma.new`), FigJam (`figjam.new`), Notion Page
(`notion.so/new`), Repl (`replit.com/new`), Google Meet (`meet.new`), Linear
Issue (`linear.app/new`), Word Doc (`word.new`) and Confluence Page
(`make.page`), each with its engagement domains (for example Drive and Docs for
has no engagement score in the app, so it offers a type when the Profile's own
history has a visit to one of its domains or their subdomains. That is a stated
adaptation, accepted by the coordinator on November 1 in Josh's absence.

Availability is answered while the panel is open from the captured sidebar
items, Space, Profile, split and Undo state; the original move, folder,
duplicate and split owners refuse while a command bar is open, so they run after
dismissal and check everything again. A command whose state changed is refused
with a beep, never redirected. Popup windows offer none of them. Private
windows offer no Space, folder, document, Search Settings or Air Traffic
Control commands; their Settings-pane and appearance commands use the
application's Settings and appearance owners. Option-Return has no split destination
for them; Command-Option-Return keeps their ordinary action. An explicitly
highlighted typed command that disappears stays disabled, as other typed rows
do.

Pin to [Space] lists every other Space, including other Profiles', and moves the
item into that Space's Pinned section (`SidebarSpaceMove.pinsToday`): a Today
tab or split becomes pinned and takes its current page as its saved home, as
promoting a Today tab does elsewhere. Rows are offered only when the pure
`SidebarSpaceMove` check passes; Pin to New Folder and Duplicate Current Tab
(`TypeTravelInput.sidebar`, `+0xa0`) with no Profile comparison. Another
Profile's row shows that Profile's name beside the Space, and choosing it goes
through Parc's existing Move to another Profile's Space owner, including its
one row; the second variant's rendered title was not recovered.

### Settings panes

General, Profiles, Max only when its AI flag is on, Shortcuts, Links, App Icon,
and bump 0.6 for General, 0.5 otherwise. Parc offers seven, each opening its
matching Settings pane:

|---|---|---|---|
| Account | **Settings** | membership card, id card, arc card, open account preferences | Membership |
| General | **Open General Preferences** | autofill, credit cards, general | General |
| Profiles | **Open Profile Preferences** | profile | Profiles |
| Shortcuts | **Edit Keyboard Shortcuts** | shortcuts, open shortcuts, edit keyboard shortcuts, key bindings, hotkeys, keyboard shortcuts, hot keys | Shortcuts |
| App Icon | **Open App Icon** | app icon, custom app icon | Icon |
| Advanced | **Open Advanced Preferences** | advanced | Advanced |

Account title "Settings" sits beside the existing Settings… menu command.

### MainMenu Type Travel data

runtime attributes on its MainMenu items: `arcTypeTravelID`, `arcTypeTravelIcon`,
`arcTypeTravelTriggers`, `arcTypeTravelCandidateBump`, `arcTypeTravelTitle`,
`arcTypeTravelDisregardCache` and `arcTypeTravelMinQueryLengthForMatch`. The 1.122
`Base.lproj/MainMenu.nib`, an asset the 1.122 binary can't answer for, read with
a bounded NIBArchive decode of its `NSIBUserDefinedRuntimeAttributesConnector`
records (117 items).

`CommandBarMenuItemInfo` keeps that data for the 70 Parc commands that match an
becomes the row title (Share… shows **Share URL**). No item sets a minimum query
length. The disregard-cache flag is not ported, since Parc has no
recently-used cache for it to bypass. Items for excluded features have no
"Changelog; Whats new; What's new", and "parc updates" for "arc updates"),
because it opens Parc's own bundled What's New page. Check for Updates… keeps
([software update](software-update.md#parc)). Getting Started stays out
by the October 26 direction that onboarding replay lives only in Settings →
General.

their nib icon, triggers and bump:

  Parc's version and build, `Chromium Embedded Framework.framework`'s version
  adaptation. The keyboard inventory previously listed this item with
  is now built at the coordinator's direction.
- **Reveal Parc Data** (`list.clipboard`, bump 0.1) selects Parc's data folder
  (the store's directory, `~/Library/Application Support/Parc` by default) in
  Finder. Ephemeral and private stores have none to reveal.
  Developer toolbar's compatibility path: one viewport capture opened straight
  in the unified Frame in Portrait Mode editor. Josh's October 25 unified
  screenshot direction removed the separate File/page-menu Portrait entry; this
  row enters that same editor rather than a separate flow.

- **Open Task Manager** (`exclamationmark.triangle`; triggers Task, Manager,
  Task Manager, Cpu, Memory: RAM) opens Chromium's own task manager. The
  engine's page-tool route gains `PCNativePageToolTaskManager`
  (`native_appkit_bridge.h`). `PageToolCommand` maps it to
  `IDC_TASK_MANAGER_MAIN_MENU`, which `BrowserCommandController` enables through
  `CanOpenTaskManager()` and runs as `OpenTaskManager(browser,
  task_manager::StartAction::kMainMenu)`. It is gated by
  `chrome::IsCommandEnabled` on the page's real Browser, like the other tools,
  and runs through `chrome::ExecuteCommand` (`native_appkit_page.mm`). That
  engine change is overlay 300, pending an engine build. The task manager doesn't
  require a live renderer (`PageToolBrowser(…, false)` in `CanPerformPageTool` and
  `PerformPageTool`), so a crashed or hung page can still open it. Its two changed units
  compile with their real Chromium 156 flags (`tests/EaselEmbeddedSnapshot/run.py`:
  `native_appkit_page.mm`, `native_page_capture.mm`).

  An engine without the case returns 0 from `PageToolCommand`, so
  `canPerformPageTool` is false and the row isn't offered. After dismissal
  the command checks the same original page and tool again before running.

  **Every page-tool row.** The engine allows a page tool (Developer Tools,
  Inspect Elements, JavaScript Console, Network Inspector, View Source, Print,
  Save Page As, Clear Browsing Data, Clear Cache/Cookies and Refresh, Cast,
  Task Manager) only while the page's window is key. An open command bar's
  own panel holds key, so those rows used to show as disabled. The window now
  asks the engine for every tool just before the bar opens and stores the
  answers with that panel and page (`CommandBarPageToolSnapshot`). While that
  bar is open, `canPerformPageTool` answers from the snapshot. Another page
  never inherits it, and once the bar closes the snapshot is cleared. Running
  a menu-backed row revalidates its menu item after dismissal, when the
  engine is asked live; a refusal beeps instead of running. The same beep now
  applies to any menu command the command bar dispatches, rather than failing
  silently. Whether Chromium's views task manager dialog
  presents correctly over Parc's AppKit windows needs that build; no runtime
  check has run.

Still missing, with reasons:

- **Open Task Manager without a page.** A Note, an Easel or an empty window
  has no native page, and the page-tool route runs on a page's Browser, so the
  row isn't offered there. It needs a window-level engine route: a
  `PCNativeBrowserWindow` call that runs `IDC_TASK_MANAGER_MAIN_MENU` on the
  window's own Browser, gated on `chrome::IsCommandEnabled`.
  writes ("Backup can be restored" / "a backup file can be imported",
  `.restoreFromBackup`). Parc's `BrowserStore` writes no backup copies, so
  there is nothing to restore. It needs a backup writer in the store plus the
  import, validation and replacement flow.
- **Expand / Collapse Pinned Section** (`chevron.down` / `chevron.right`) needs
  the sidebar's collapsible pinned section, which Parc doesn't have. That means
  per-Space collapsed state (`SidebarSpaceState.collapsePinnedSectionEnabled`,
  `spacesWithCollapsedPinnedSections`), the header chevron, hover and click,
  and the hidden-row layout ([sidebar contract](sidebar-resize.md#space-header)).
  It belongs to the Sidebar family.

The appearance items carry a Type Travel title but no binding ID, so Parc's
registry never listed them. They are now typed commands: **Switch to Light
Mode**, **Switch to Dark Mode** and **Switch to Automatic Appearance**, with the
nib's triggers. Each sends the existing View → Appearance action, so the
window's "Update Appearance" Undo step is unchanged. Show Spelling and Grammar
also has a Type Travel ID; it acts on a focused text owner, which the command
bar's own field would be, so it is not offered.

Trigger phrases and bumps reach the shared ranking (`CommandBarRanking`).
`CommandBarRanking.commandCandidate` gives every action candidate each trigger
phrase as its own text, so "night mode" is an exact match for Switch to Dark
Mode. It adds `CommandBarMenuItemInfo.rankingBump`, the bump × 0.06, to the
action's `0.85 × quality`. With that weight the largest bump (Export Notes,
17) beside the URL/title/hot-word match scores, frequency, typed count,
most-visited rank, site engagement and global site rank. `ASE2.ImportanceConfiguration`
`typedCountEver`, `mostVisitedRank`, `siteEngagementScore`, `globalSiteRank` and
`typeTravelCandidateBump`. The default weight values were not recovered.

history-visit gate stands in for that and is accepted for now (above).
`joinNextMeeting` (case 5) needs a calendar integration and stays excluded.

## Native extension keyword scopes

Registered extension keywords now use the real originating Profile's Chromium
KeywordProvider/KeywordExtensionsDelegate. Tab or the actual profile's configured
Space entry starts an immutable offered scope; query edits retain that native
session and its request IDs. Suggestions carry exact extension action tokens,
separate from URL/POST navigation requests. The synthetic provider URL is neither
loaded nor offered for copying. Ordinary classified fallback also refuses such
a navigation token.

Return dispatches Chromium's actual `omnibox.onInputEntered` before cancelling
or dismissing its producer. Cmd-L requests the current tab; Cmd-T requests a new
foreground tab. Command–Option–Return requests a background tab and keeps the
panel; it acknowledges event dispatch, not an outcome the extension controls.
Option-Return split is unavailable for these actions because the extension API
has no split destination. Extension-supplied deletable suggestions use their
original content and provider deletion/republication, not their display label.

Eligibility retains the exact selected native page, original weak document,
physical window, Profile/OTR permission, enabled extension registration object
and delivered publication. Profile load, navigation, close, transfer, extension
disable and late suggestion callbacks cannot retarget a retained action. Actual
execution/deletion requires the original window or child panel to be key and
free of sheets/security reservations. The active extension scope is a static
native label; the website Remove/Change menu remains website-only. Escape and
empty Tab/Backspace preserve the existing query-restoration and native IME owner.
Explicitly highlighted expired extension actions remain unavailable rather than
becoming generic web input.

input-entered caller/event (`0x609ea3c→0x60a5b68`) and cancellation/request-ID owner
(`0x62983d4/0x6298400`) establish the native mechanism. Fresh REA of the event is
`ev_aa1a7997a73305c79a9b09f0718bbcd3217798861bf3dd602e40c809ff1a8603`,
corroborated by full-image instructions and event literals. The complete old
Swift extension result route is not claimed recovered merely from these native
functions. Starting current Chromium's extension session on empty scope entry,
using its present ranking, and correcting the copied deletion event's content
attributable extension keyword appearance in the bounded read-only inventory.

A blank tab, Note or Easel without an actual selected native page remains unsupported
for extension scopes; no dummy activeTab owner is created. Actual extension
execution, exact modern row/icon/pressed/motion/haptic appearance, all input
methods and full provider ranking remain distinct validation/polish limits.
Source compilation and native AppKit control checks do not claim browser runtime
acceptance; no functional browser tests or personal extension operations ran.


## Search-service load notification ordering

The reported command-bar startup abort was caused by installing the bundled site
catalog from `TemplateURLService`'s own change observer. `Add` sends another
notification, and pinned Chromium forbids reentering that observer list. The
catalog and its existing recorded-once/user-policy/private-profile rules remain
unchanged.

Search readiness now coalesces a non-nestable task on the original UI sequence.
Both the newly loaded and already-loaded paths prepare the catalog outside the
service notification stack, then post waiting clients asynchronously. A nested UI
loop cannot run preparation inside an observer. Notifications produced by
preparation still revoke revisions immediately, but cannot recursively prepare
or enqueue duplicate work. Original Profile/service shutdown cancels queued
preparation and asynchronously settles pending clients once; their existing weak
Profile and originating-window checks report unavailability. No search callback
retains a request context or revives a closed profile.

This is a current-Chromium callback-ordering correction, not a change to the
component is checked with Chromium's actual task executor and
`ObserverList<TemplateURLServiceObserver>`: the former synchronous ordering aborts
at the real non-reentrancy check in an isolated negative control, while deferred
preparation, nested-loop exclusion and shutdown/drain cases pass. The native
search translation unit is separately compiler-checked. This component does not
load a browser or personal Profile, and does not claim packaged browser behavior.

## Typing stability and ranking

**November 6 domain regression correction.** The November 2 unified-ranking change
(`b6000e1c`) discarded Chromium's default priority when its website result merged
with an open tab. A bare `google.com` or `youtube.com` only weakly matched that
tab's `www.` URL, letting a search for the domain (or a tab from an earlier such
search) take Return. Dedup now carries the default's admission and preferred
position to the surviving row, preserving the leading Type Travel rule and
original tab-switch dispatch. A genuine search default remains a search. The
ranking fixtures reproduce the failure before the fix for both domains, with
and without an earlier search tab; the production scope-resolver fixture also
fails before the tab-site-search correction. These are inert component checks,
plus full-module Swift compilation, not browser-runtime acceptance. No engine
change or app package is part of this source correction.

**November 6 broader navigation audit.** Josh confirmed that the old installed
build opens `google.com` with the homepage absent, and that `www.google.com`
selects the existing homepage correctly. Those are user observations, separate
from the isolated checks below; the exact pre-existing YouTube tab URL was not
captured.

drop Chromium's leading website request (for example a bookmark or personalized
navigation result), then renumber a search as the default; (2) identical
URL/title strings caused the open-bar cache to skip a new native publication,
leaving rows with previous request objects, so current-publication scope and
deletion identity checks no longer matched. The first published native result
now survives the display filter with its original request and native search
flag; when an extension action owns position zero, that action keeps priority
and later native rows retain the filter. The fingerprint now includes the
native snapshot revision. Each new publication replaces payloads and rebinds
row actions; the existing row diff still keeps unchanged views, and idle chrome
refreshes still skip rebuilding.

own `navigateWhatYouTyped` / `searchWhatYouTyped` archetypes, while Parc delegates
classification and complete requests to Chromium. Presentation must not erase
that leading request. No host allowlist, dot detector, reconstructed URL,
search template or substitute GET is added. Native generation checks, original
Profile/engine-revision validation and scoped keyword-mode navigation remain
unchanged.

`scripts/test-command-bar-navigation.sh` compiles the production native-row
filter, complete ordinary ranking, publication fingerprint, selected-scope
resolver, held-answer Return boundary and shell tab-eligibility filter against
inert native-publication objects. The initial audit reproduced 19 assertion
failures across filtering and publication identity before correction. The
finished matrix covers default result types with/without open tabs; bare,
`www`, scheme, mixed-case, path, port, IPv4/IPv6, international and escaped URLs;
zero/one/multiple matching tabs; another Space versus another Profile; current,
archived, closing and transferring tabs; previous accidental searches; separate
paths/query strings/fragments; true searches and dot-containing search terms;
no provider answer; Return while a reply is pending; explicit search selection;
ordinary/background/split submission; leading extension actions; and repeated
same-looking publications. This exercises app decisions given native requests,
not Chromium's live classification/network/history service or browser navigation.
The existing editing, hold, row-text, ranking, scope and Return suites plus the
full Swift module check also pass. No new app package or automated browser-runtime
acceptance is claimed.


The engine restarts Chromium's controller on each edit instead of clobbering it, as Chrome's omnibox does. Google's cached suggestions and the matches Chromium carries over from still-running providers therefore stay in each keystroke's first answer until the network replaces them. A new scope, engine change or empty input still starts fresh.





An offscreen harness (not kept in Git) driving the real diff, ranking, table, row and cell classes with Chromium's provider timing modelled showed that typing “new ea” cut visible row changes from 20 to 11, rows that vanished and returned from 2 to 0, rebuilt row views from 15 to 0, and site-search panel height changes from 11 to 1. `tests/CommandBar/RowDiffTests.swift`, `RankingTests.swift` and `NativeHoldTests.swift` cover the diff, the ranking and Return/Tab while an answer is pending; the native file compiles with its real build command. No functional browser test ran.

## Result viewport width

AppKit adds table-style margins outside the column: in an isolated AppKit probe,
a 300-point clip with a 300-point column produced a 332-point table, leaving
32 points of horizontal overflow even with the horizontal scroller hidden. Parc
now fits the complete table document to the final clip width, including the
style's actual extra width, clears any retained horizontal offset and disables
horizontal elasticity. It preserves the current vertical position and native
vertical scrolling; scope layout is applied before fitting the viewport. The
inert component check covers changing widths, row counts, native table styles,
legacy/overlay scrollers and vertical position. A live gesture comparison and
full command-bar appearance and interaction parity are not established by this
component check.

## Reported command dispatch failure — October 29

In the running v240 development package at source `043b253`, Cmd-T, typing
**New Easel**, and Return selected an enabled command row and dismissed the
panel without opening an Easel. The same sequence for **Add Split View**
dismissed the panel without showing a split placeholder. In a separate test
window, the direct Control–Shift–Equals split shortcut opened a placeholder;
submitting a URL produced an actual two-page split. Cmd-T → **Add Split View**
→ Return in that same two-pane window still dismissed the panel with no new
placeholder. These observations do not establish the failing guard or current
main's behavior.

A further v240 check in the active browser reproduced both selected-row
failures using Return. In that same session, Control–Shift–E opened an empty
Easel and Control–Shift–Equals opened the split's command panel; Escape
cancelled the split draft. This distinguishes the command-bar route from those
direct shortcut paths, but does not identify a failing guard. macOS denied a
debugger attach to the running process, so its post-dismissal key/main state and
the precise rejection remain unobserved. The empty Easel created by the direct
shortcut remains in the session.

The v240 and current source both route the selected menu item through
`CommandBar.submitResult`, panel dismissal, original-session revalidation and
`KeyboardShortcuts.performMenuCommand`. A disposable AppKit host using the
actual shortcut registry and the same basic child-panel dismissal sequence
restored the parent key window and dispatched its test menu item. That narrows
neither the browser's original-session validation nor the actual target's
availability. The next diagnostic must record the original-session result,
registry revision and exact original item/window validation, and whether the
Easel or Split target handler actually runs, in a current-source package with a
disposable profile. Preserve the original window, page and security gates;
do not change a guard based on these observations alone. The dedicated engine
owner owns the package handoff. Current source changes the Easel handler's
window ownership after v240; neither that change nor the unchanged shared
submission path establishes current runtime behavior.

while v240 Parc initially selected **Add Split View** before the web results.
its down-scroll moved the visible rows vertically. The corresponding Parc
right-scroll gesture also produced no settled movement; its down-scroll CUA
call timed out, so this is not a paired vertical-scroll result or post-fix
observation is a comparison point, not a complete ranking specification.

### Key restoration and command registry revisions

Source inspection found a shared rejection that can occur during the reported
post-dismissal dispatch. When restoring the browser's key window synchronously
delivers its activation callback, the callback rebuilds the Spaces menu. Each
registration increments the global shortcut registry revision, so the selected
command's retained revision no longer matches even when its original menu item
has not changed. This path exists in v240, but its actual key notification timing
was not observed; it is a supported explanation rather than a confirmed cause of
the reported failures.

The activation refresh is now held until the original command-bar dismissal and
any selected action have returned, including the split-insertion panel. This
also covers nested submission and cancellation; other registry changes continue
to invalidate stale commands. Dispatch still revalidates the original session,
window, registry revision, attached item and target. The deferred refresh reads
the then-current Space state and window owner. A current-package runtime check
is still needed to determine whether this resolves the observed failures.

## Commands that need a key browser — November 9

draws its bar inside the browser window, so the browser stays key and its
`MainWindowController` stays in the responder chain. Parc's bar is a key panel
of its own. Every menu validator that needs its browser to be key therefore
said no while the bar was open, and Return on the dimmed row only beeped. That
covers `browserInputCommandWindow` (Edit Theme…, New Space…, Back, Forward,
Refresh, Stop, Zoom, Toggle Sidebar, Pin, Share, Cast, History, Manage and Add
Extensions), the native window gate behind Reveal Current Tab, Next/Previous
Tab, Go to Sidebar Item and the recent-tab switcher, Reset Tab's key check, and
nil-targeted items such as Minimize and Paste and Match Style, which resolved
against the bar's own panel. The page-tool snapshot above fixed one instance of
this.

The bar now reads its command list as it opens, while the browser is still key
(`presentCommandBar` requires the native window gate first), and records which
commands could run (`MenuCommand.wasAvailable`). A row stays offered if it was
available then or is available now. Choosing it dismisses the panel and
`performMenuCommand` validates the original item again against the key
browser, so the open-time answer never runs anything by itself. The answer
isn't refreshed while the bar is open: a command that stops being available in
that time (Stop after the page finishes loading) stays offered, and choosing it
closes the bar and beeps. A command first registered while the bar is open has
no open-time answer and shows its live state. Shortcuts pressed while the bar
is open are unchanged. `MenuCommandAvailabilityTests` covers the rule.

## Search-suggestion privacy banner

When the centred bar has results and no website-search hint, an ⓘ accessory sits
at the trailing end of the input. Clicking it shows **We talk to your search
engine to help us suggest results.** under the results, with **Search Settings…**
and **Dismiss**, and the ⓘ goes away while the banner shows. Dismiss hides the
`commandBarSearchSuggestionsPrivacyHasBeenExplicitlyDismissed`, in Parc's defaults
domain, and after that neither the ⓘ nor the banner appears. The bar grows
downward for the banner and shrinks back without moving the input. Search
Settings… closes the bar, returning focus as Escape does, then opens Settings →
Profiles, where Parc keeps **Include search engine suggestions** beside the
search engine. Every new bar starts with the banner hidden. The ⓘ and the
banner's buttons never take focus from the command field, even with Full
Keyboard Access; VoiceOver hears the notice announced when it appears, and the
banner reads as one "Search suggestions privacy" group around its text.

`suggestions` array is non-empty (`SearchOutput` fields `query`,
`maxCountToDisplay`, `suggestions`), and those suggestions are the bar's rows,
so Parc checks its current result rows.


  returns `cancel` when `shouldDisplayCloseAccessory`; nothing for a
  `.contentPanel` entry point or an active scope; nothing without a search output
  holding suggestions; nothing once the notice is dismissed or while the banner
  shows; and `searchPrivacyInfo` otherwise. It never returns `tabToGoBack`.
  `bannerIsVisible` false, reads the dismissal from the user default (key 86 at
  dismissed true on Dismiss, persists the default, and turns Search Settings into
  `CommandBarDelegateAction.onDidRequestSearchSuggestionsPrivacySettings`
  `ev_0ca3153aead46613132462ca28339c6042af61317dded1158f68d73e387b5a72`).
  8-point-blur shadow in a container with a 12-point trailing inset

border and a 2-point lip in the neutral face/hover/pressed palette, and no hotkey
badge because the label isn't a `DialogButtonLabel`. Parc reuses the palette its
asset catalog because 1.122 references them only by name. A shown banner stays
under the results inside a website or Actions scope, since the view state copies
`bannerIsVisible` regardless of scope; the ⓘ itself never shows in a scope.

Parc adaptations and limits:

  leaves the line out and centres the title in the same 60-point row.
  from theme key paths; Parc draws `info.circle` in the command bar's accessory
  colour (`CommandBarPalette.accessoryForeground`). The banner's own title and
  defined through `CommandBarPalette.either`, so they follow the bar's
  Space-derived light or dark appearance.
  It shares the trailing slot and 22-point margin of Parc's website-search hint.
  The condensed layout switches when the single row doesn't fit, which stands in
  read).
- **Sidebar session.** The compact sidebar search panel shows neither the ⓘ nor
  the banner; it has no suggestions footer.
  `work/cursor-review-images/cb-extras/` are compared with the recovered values
  only.

## Sidebar background: window drag and double-click

the window; a double-click below the last row opens the command bar for a new tab,
exactly as the sidebar's New Tab does. A gap between rows, a single click or a
Control-click doesn't open it (Control keeps the Space menu), and an empty list
opens it anywhere in the list area. Library Space cards are excluded: their lists
belong to the Space manager, not to a window's sidebar. That exclusion is Parc's

Neither TablistView nor `WindowDraggableView` references `acceptsFirstMouse:`
views keep AppKit's default too, so a first click on an inactive Parc window
doesn't start a drag either.

the superclass; on the first click it posts `NSWindowWillMoveNotification` and
calls `performWindowDragWithEvent:`; later clicks do nothing until release. Its
and sends `WindowAction.onDidDoubleClickSidebarBackground`. The sidebar action
list's 120-point bottom inset or the clip view below it; `SidebarView` routes
recovered; Parc adds nothing there. The SpaceManager component check drives a real
rendered `SidebarView`: a second press waits, a double-click released under the
last row (directly or through the clip view) opens the bar once, and single,
Control, row and Library-card releases don't. A first press isn't sent there
because it would start a real window drag; `SidebarTablistBackground`'s checks
cover that choice.


- **⌥⌘G is excluded.** `keyboardShortcutCommandOptionG` (MainMenu handler
  `https://chat.openai.com/favicon-32x32.png`, "ChatGPT") and opens a new-tab bar
- **`addSearchEngine` isn't an accessory.** It is `CommandBar.Action` case 13
  Nothing in the recovered code ties it to pages offering an OpenSearch
  description, and its sender wasn't found. Parc's native keyword session reads
  the Profile's TemplateURLService directly, so an engine added to the Profile is
  already offered without a separate list.
- **The Cancel and "Tab to go back" accessories don't apply.** Cancel shows only
  "Title for action to go back to the previous search state").
- **Default-browser prompt in the bar: left out.** `DefaultBrowserPromptView`
  sits in SuggestionsView, fed by the `DefaultBrowserPrompts` feature: prompt types
  `afterOnboarding`, `day2` and `afterTrial`, buttons Maybe Later, Try for a Week,
  Set as Default, Not Ready to Switch, Keep as Default and Submit Feedback, and a
  persisted display history (`StorableDefaultBrowserPromptsState`,
  `StorableDefaultBrowserPrompts.json`). Its `newDefaultBrowserPromptsEnabled` gate
  `win_DefaultBrowserPromptOnCommandBar`), not a user setting, and Submit
  coordinator's decision while Josh is away).
