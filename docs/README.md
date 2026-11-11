# Parc documentation

Start with the [project overview](../README.md), [product status](parity.md) and
[backlog](backlog.md). These describe the current product and unfinished work;
Git and release notes retain history.

## Development and delivery

- [Working contract](../AGENTS.md), [collaboration](collaboration.md),
  [documentation policy](documentation.md), [interface review](visual-review.md).
- [Developer onboarding](developer-onboarding.md),
  [development setup](development-setup.md), [engine artifacts](engine-artifacts.md).
- [Engine architecture](../Engine/README.md), [Chromium seams plan](chromium-seams.md), [engine flags](engine-flags.md),
  [packaging](../tests/Packaging/README.md).
- [Production release](master-release.md), [Homebrew delivery](homebrew-release.md),
  [software updates and What's New](software-update.md).

## Everyday browsing

- [Navigation](navigation.md), [command bar](command-bar.md),
  [keyboard navigation](keyboard-navigation.md), [tab switcher](tab-switcher.md).
- [Saved tabs and Favorites](saved-tabs.md), [closed-tab restoration](reopen-closed-tabs.md),
  [folder commands](folder-commands.md), [folder moves](folder-moves.md).
- [Split groups](split-groups.md), [split navigation](split-navigation.md),
  [Peek](peek.md), [web interactions](web-interactions.md).
- [Automatic archive](archive.md), [archive previews](archive-preview.md),
  [archived documents](archive-preview-documents.md), [downloads](download-library.md).
- [Routing](routing-interaction.md), [private routing](private-route-lifecycle.md),
  [internal addresses](internal-addresses.md).

## Windows, sidebar and appearance

- [Window lifecycle](windows-lifecycle.md), [activation](window-activation.md),
  [window appearance](window-appearance.md), [page composition](page-compositing.md).
- [Sidebar motion](sidebar-motion.md), [resizing](sidebar-resize.md),
  [selection](sidebar-selection.md), [previews](sidebar-previews.md),
  [accessibility](sidebar-accessibility.md).
- [Space management](space-management.md), [Space navigation](space-navigation.md),
  [theme editor](space-theme-editor.md), [theme appearance](space-theme-appearance.md),
  [rendering](space-theme-rendering.md), [input](space-theme-input.md),
  [undo](space-theme-undo.md), [haptics](space-theme-haptics.md).
- [Tooltips](tooltips.md), [toasts](toasts.md), [dialogs](dialogs.md), [top-band colors](top-band-color.md).
- [App icon picker](app-icon-picker.md), [availability](app-icon-availability.md),
  [marks](app-icon-marks.md), [optical sizing](app-icon-optical.md).

## Setup, settings and local data

- [Onboarding and replay](onboarding.md), [browser import](browser-import.md).
- [Settings](settings.md), [settings presentation](settings-presentation.md),
  [motion](settings-motion.md), [profile removal](settings-profile-removal.md),
  [membership card](settings-membership-card.md).
- [Notes](notes.md), [automation and scripting](scripting.md),
  [performance](performance-navigation.md).

## Capture, Library and Easels

- [Page capture](page-capture.md), [capabilities](capture-capabilities.md),
  [editing](capture-editing.md), [destinations](capture-destinations.md).
- [Capture presentation](capture-presentation.md), [motion](capture-motion.md),
  [portrait framing](portrait-capture-fidelity.md), [Library](capture-library.md),
  [document grid](documents-library-grid.md).
- [Easels](easels.md), [appearance](easel-appearance.md), [motion](easel-motion.md),
  [live captures](easel-live-captures.md), [embedded pages](easel-embedded-pages.md).

## Extensions and developer tools

- [Extensions](extensions.md), [interaction](extensions-interaction.md),
  [layout](extensions-geometry.md), [lifecycle](extensions-lifecycle.md),
  [side panel](extensions-side-panel-adaptation.md).
- [Developer Mode](developer-mode.md).

## Media

- [Interaction](media-interactions.md), [accessibility](media-accessibility.md),
  [mini-player](media-mini-player.md), [presentation](media-mini-player-presentation.md),
  [casting](media-casting.md).
- [Page events](media12-chromium-events.md), [media state](media12-producer-contract.md),
  [PiP and history](media12-pip-history-contract.md),
  [PiP capabilities](media12-pip-seam-assessment.md).
- [FairPlay identity](fairplay-identity.md), [Safari API surface](fairplay-safari-surface.md),
  [media lifecycle](safari-media-edges.md), [hidden video](safari-hidden-video.md),
  [AV1](media/av1-hardware.md).
- [Native FairPlay](../Engine/ParcNative/fairplay/README.md),
  [Chromium integration](../Engine/ParcNative/fairplay_chromium/README.md),
  [native HLS](../Engine/ParcNative/fairplay_chromium/NATIVE_HLS.md),
  [composition](../Engine/ParcNative/fairplay_chromium/COMPOSITING.md),
  [waiting for keys](../Engine/ParcNative/fairplay_chromium/WAITING_FOR_KEY.md).

Keep guides focused and update their current descriptions in place. Every
Markdown guide is limited to **500 lines**; normal guides should be 150–300 lines.
Changelogs retain their full history and are exempt.
