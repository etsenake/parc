# Automatic archive education component checks

Run from the repository root with an output directory outside Git:

```sh
bash tests/AutoArchiveEducation/check.sh /absolute/path/to/check-output
```

The script compiles the production `SidebarBannerHost` and exercises it
in an inert AppKit process. It never launches Parc, loads an engine, creates a
browser profile, activates a real browser window or synthesizes input. The
native component windows remain off screen.

The checks cover original responder preservation, actual SwiftUI-to-AppKit card
attachment, focus relinquishment when disabling the card, repeated updates,
hidden controls, superseded dismissal, detach/reattach, reset cancellation and
final removal. The behavior contract is in [Archive](../../docs/archive.md).
