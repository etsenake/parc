# Interface review

Review Parc's interface for clarity, consistent Space themes, correct behavior,
keyboard access, readable text and smooth motion. Preserve working features and
explicit Parc additions. A comparison image is not permission to remove a control.

## Current boundary

[AGENTS.md](../AGENTS.md) forbids launching, opening or driving any app or browser,
including test/headless copies, and taking app screenshots. Use supplied images,
retained artifacts, source inspection, compiler checks and model/unit tests.
This guide does not authorize a render harness that launches an app or window.
The website videos come from [scripts/site-film](../scripts/site-film/README.md),
which compiles Parc's interface code and draws it offscreen without an app,
window or screen recording; it serves only those videos, as the
[website guide](website.md#product-scenes) describes.
Live appearance and interaction checks need explicit renewed user authorization.
For slow or blank transitions, follow
[collaboration](collaboration.md#runtime-investigations) to connect what the user
sees with the work that produced the picture.

## When the user supplies an image

1. Establish which app, view and state it shows. Resolve ambiguous labels from
   the context before comparing anything.
2. Describe the visible problem in plain words and trace the production code
   responsible for it, including state, theme and owner lifetime.
3. Fix the whole affected interaction within scope: normal/hover/pressed states,
   light/dark appearance, keyboard focus and disabled behavior where relevant.
4. Check real source and applicable models, then close the completed fix.
   Do not leave it waiting for user confirmation or another browser test.

For authorized parallel work, assign exact file boundaries and share the same
reference/state description. Read results as they arrive and integrate them;
finished work should not wait on an unrelated build or unanswered optional
preference. Keep screenshots and temporary receipts outside Git.

## Review criteria

- Text and icons remain readable in every supported theme and hover state.
- Dynamic colors follow the owning Space and window appearance.
- Clickable controls, including native buttons, expose the correct pointer and
  preserve keyboard and accessibility interaction.
- Focus, selection, press and cancellation states follow actual ownership.
- Page content, floating sidebar, menus and overlays retain correct layering.
- Motion follows lifecycle and reduced-motion settings without stale completions.
- Replay onboarding and other Parc additions remain reachable and functional.

A missing user reply does not block independent authorized work. Make reasonable
reversible decisions and report them; do not infer permission for prohibited
runtime checks. Keep known product gaps in the [backlog](backlog.md), and disclose
them to the user. A failed test setup is not evidence of a product defect.

Implementation review and publication follow [collaboration](collaboration.md).
Update the relevant guide in place; do not append a session-by-session review log.
