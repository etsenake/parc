# Split pane navigation

Split focus selects an original page in the current window's ordered pane group.
It is separate from next/previous tab, the MRU switcher and Chromium's generic
pane-rotation hook. No page is recreated from a stored URL.

The View menu offers Add Split View, Close this Split Pane, Separate Page from
Split View and Expand Current Split. Control–Shift–1…4 and Control–Shift–]/[
select numbered/adjacent panes through the existing shortcut editor, command
search and native priority pipeline. Widen Current Split, Narrow Current Split
and Make All Split Panes Equal are hidden View commands with no default chord,
offered in command search and the shortcut editor. Hidden menu commands accept
shortcuts only when `allowsKeyEquivalentWhenHidden` is set explicitly.

## Interaction and ownership

| Action | Behavior |
|---|---|
| Numbered focus | Selects a one-based member; missing positions are unavailable. A single pane is position 1. |
| Adjacent focus | Wraps in current group order and preserves group membership. |
| Expand | Requires multiple panes. Gives the focused pane the room left after other panes' 220-point minimum, preserving orientation and membership. Each browser window applies it to its own focused split and saves changed weights. It is not a restore toggle; Make All Split Panes Equal evens the panes again. |
| Widen, Narrow and Make Equal | Require multiple panes, act on the command's own window and are disabled when they would change nothing. Widen and Narrow step the focused pane by a tenth of the split; Make Equal evens every pane. Each commits like a finished divider drag; see [keyboard and VoiceOver resizing](split-groups.md#keyboard-and-voiceover-resizing). |
| Separate | A separated focused pane remains displayed alone; separating another member preserves the surviving focus. Model/group selection changes atomically without closing pages. |
| Close | Retains the exact original pane and uses real close/beforeunload consent. Refusal preserves it. |
| Orientation | Uses the existing validated group/page layout transaction. |

`SplitCommandTarget` captures the physical window, Space/Profile, ordered
membership, focused tab, pane/wrapper identities and native page identifiers.
Execution revalidates after dismissing owned transient surfaces and checking the
native security gate, then consumes the target once. Changed ownership, group,
selection or retirement invalidates it; normal navigation within the same live
page does not replace tab identity.

Settings or another window cannot redirect an action to the last browser.
Active Peek, popup/native fullscreen, Library, sheets/security reservations,
transfers, close transactions and MRU prevent underlay split commands. Command
search can show prospective availability but must dismiss and revalidate before
execution. Native text editing, IME, custom bindings, key repeat and keyboard
lock keep their existing arbitration.

A local Easel pane focuses its canvas after native deselection; selecting an
already focused Easel preserves its title/text editor. A blank tab without a
content target leaves focus with the window.

## Source owners and checks

The app uses the existing native selection/layout and close transactions. Model
and compiler checks cover stale targets, original-page ownership and atomic
selection. See [split groups](split-groups.md) for full layout, command choreography and
accessibility contracts.

### Separate focus

Context and accessibility actions bind the original selection plus every page
and editor claim. Failed group/selection persistence leaves both unchanged.
Saved-parent relocation and animation are separate responsibilities from this
focus policy.
