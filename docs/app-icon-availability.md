# App icon availability and discovery

Every approved Parc icon is available immediately and offline in **Settings →
Icon**. Original is the default. Account age, referrals, release channels,
Profiles and Spaces do not change availability or own the selection.

## Parc availability contract

The picker order is Original, Candy, Neon, Fluted Glass, Schoolbook, Colorful,
Hologram, Early Birds, Canary and Dev. The last four names carry no eligibility
or build-channel requirement. Every choice supports preview, current-icon state,
atomic local selection, restoration and native identity application.

Parc has no referral counters, account gates, locked/loading reward rows or
unlock banner. The permanent Icon settings pane is the discovery surface.

## Native artwork integration and checks

`AppIconController.Variant.image` loads `AppIcons/<id>.icns` when present. The
picker and native app/Dock/Finder consumer receive the same image and its size
representations; the non-running Dock plugin reads that ICNS too. Source-only
previews may use PNG when ICNS is absent. An unreadable existing ICNS reports
an artwork failure instead of silently falling back.

The controller owns persistence and native identity; the [picker](app-icon-picker.md)
owns interaction. `scripts/test-app-icon-controller.sh` exercises the production
controller with disposable catalogs and an injected identity applier. It covers
choice/order/defaults, restoration, invalid IDs, native sizes, missing-ICNS
fallback and corrupt-ICNS refusal without changing the system icon or Dock.
Component checks do not establish live browser or Finder acceptance.
