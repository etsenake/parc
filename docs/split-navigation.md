# Split pane navigation

Split focus is an application selection command over the current window's ordered panes. It is separate from next/previous tab, held MRU and Chromium's generic `RotatePaneFocus` compatibility hook. Parc uses its existing original-page native selection and layout transaction after changing the focused member; no page is recreated or navigated from a stored URL.


## Interaction and ownership

| Interaction | Production path and states | Reference boundary |
|---|---|---|
| Numbered focus | One-based position in the original ordered group; absent positions are unavailable. The selected original page becomes native selection. A single pane remains a valid position 1. | Original numbered reducer bounds-checks the content count and subtracts one; it does not manufacture a missing pane. |
| Adjacent focus | Next/previous wrap in group order and keep the group intact. Each invocation resolves a fresh command; a stale menu target cannot advance a different group. | Recovered reducer finds focused identity, calls the wrapping collection helper with +1/-1 and writes focused content before an original-window focus effect. |
| Separate | The focused original remains displayed alone; another displayed child leaves focus on the surviving group. Background targets preserve the current selection. The original saved group and selection commit atomically without closing pages. | Actual WindowContents mutation tests the removed set against its focused identity, preserving that focused content when included. The historical saved-parent relocation remains a separate attribution boundary. |
| Close | View menu, page menu and pane header carry the original pane target. Existing page close/beforeunload decides whether removal commits; refusal keeps the original page. | Original action resolves focused content and dispatches the genuine close helper. No replacement close transaction is introduced. |

A `SplitCommandTarget` snapshots the original physical window, Space/profile, ordered membership, focused tab, expansion state, pane objects, browser wrappers and native page identifiers. Main-menu tracking preserves that target. Execution checks it again after dismissing owned command/history/hover surfaces, checks the real native security gate, then consumes it once. A changed Space, selected group, focused pane, page wrapper, ownership, retirement or window makes the command unavailable. Normal navigation within the same live page does not replace its tab identity.

Settings or another application window cannot cause these actions to fall back to the last browser. Active Peek, popup/native fullscreen, library, sheet/security reservation, transfers, close transactions and MRU exclude the split-underlay commands. Command search may display prospective availability for its owned browser panel, but actual execution closes that panel and revalidates the native owner. Existing renderer versus browser shortcut arbitration, native text editing/IME, custom bindings, repeat policy and keyboard lock remain authoritative.


## Reference evidence



The new REA record uses exact `LC_FUNCTION_STARTS` boundaries, original section/file-offset mapping and hashed bytes. Original full-image assembly and the decoded relative jump-table entries support cross-function attribution. Raw-slice decompiler signatures and external/global references are incomplete; pseudocode is generated evidence, not original source or observed execution.


## Delivery boundary

This slice changes existing app source only and needs no new native API, engine overlay or registration. Read-only source review covers original target invalidation, page ownership, expanded-pane selection, retained geometry and genuine close transactions. The combined 51-file Swift compiler check passes with zero diagnostics. No functional browser sequence was performed. Space continuity, accepted Peek and the generic native pane-rotation hook remain unchanged.

### Separate focus correction

Separate now uses the original focused-item branch recovered from
while separating another child preserves current focus. Context/AX actions bind
the original selection and every page/editor claim as well as the saved group.
The group/selection save is atomic and failure leaves both unchanged. See
[the complete Separate contract](split-groups.md#separate-page-and-original-focus).
Saved-parent relocation and exact animation remain separate from this recovered
focus policy.
