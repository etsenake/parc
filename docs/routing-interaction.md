# Air Traffic Control interaction evidence

`4e452201e483b5480c0403a9ef8566e10515cdcb78828622ff9032b202e29547`.
The address observations below are recovered from its Swift metadata and
annotated functions, not original source.

- `LinkRoutingEditor.State` stores `focusedRuleID`; its actions include
  `onUpdateFocusedRuleId` and component `submit`. `LinkMatchingRuleView` and
  `LinkMatchingRuleComponentView` carry the same focus binding. Component body
  not itself add a condition or close the dialog.
  `focusable` and `focusEffectDisabled`. This does not establish a complete
  keyboard traversal or VoiceOver sequence.
  rule identifier to the top. This establishes a scroll transition, not an
  editor-wide fade or a generic animation for every mutation.
- `Toasts.ToastType` includes the specific `meetLinkAutoRouted` case, and its
  presentation includes “Meet links now open in your current Space!” at
  routed link. Generic routing feedback should not be invented from it.
  Modifier-explained hovered-link feedback is already owned by
  [Web interactions](web-interactions.md#hovered-link-status); the presence of
  `LinkExplainedOutcome` does not by itself make that a rule-routing toast.

The AppKit clip-view scroll and Reduce Motion handling in
`LinkRoutingInteraction` adapt the recovered scroll to the native editor.
Its rule-and-condition-ID selection snapshot, explicit key-view ordering, error
announcement and selectable error-details sheet adapt Parc's rebuilt AppKit
A snapshot cannot preserve marked input-method composition, so destination
refresh waits for active editing and menu tracking to end. The inline editor
retains a condition's focus and selection, restores surviving controls by
identity with a safe fallback, provides numbered accessibility labels and keeps
long errors selectable in a nested Details sheet. It applies the recovered
scroll after inserting a new inline rule. These are Parc adaptations except
Source checks do not establish keyboard or accessibility runtime acceptance;
functional input and VoiceOver checks remain unauthorized.
