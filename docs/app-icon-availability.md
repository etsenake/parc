# App icon availability and discovery

Every approved Parc icon is available immediately and offline in **Settings →
Icon**. Original is the default. Account age, referrals, release channels,
Profiles and Spaces do not change availability or own the selection.

## Parc availability contract

The picker order is Original, Sorbet, After Hours, Rain Glass, Recess, Twilight,
Opal, Tracing Paper, Grapefruit and Terminal. No choice carries an eligibility
or build-channel requirement. Every choice supports preview, current-icon state,
atomic local selection, restoration and native identity application. A choice
saved under an icon's earlier name restores as its current name, and the saved
preference is rewritten so the Dock plugin shows it while Parc is closed.

Parc has no referral counters, account gates, locked/loading reward rows or
unlock banner. The permanent Icon settings pane is the discovery surface.

## Native artwork integration and checks

`AppIconController.Variant.image` loads `AppIcons/<id>.icns` when present. The
picker and native app/Dock/Finder consumer receive the same image and its size
representations; the non-running Dock plugin reads that ICNS too. Source-only
previews may use PNG when ICNS is absent. An unreadable existing ICNS reports
an artwork failure instead of silently falling back.

The controller owns persistence and native identity; the [picker](app-icon-picker.md)
owns interaction. `AppIconControllerTests` exercises the production
controller with disposable catalogs and an injected identity applier. It covers
choice/order/defaults, restoration, earlier-name migration, invalid IDs, native
sizes, missing-ICNS fallback and corrupt-ICNS refusal without changing the
system icon or Dock.
