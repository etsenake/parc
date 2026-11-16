# Disk image install window

The disk image people download from GitHub opens as Parc's own install window
instead of Finder's plain folder: a big Parc icon, a squiggly arrow, the
Applications folder and "To install, drag Parc to Applications". Packaging
lays the window out by writing the volume's Finder files directly; nothing
opens or drives Finder.

## Artwork

`background.png` (640 × 400) and `background@2x.png` (1280 × 800) are the same
vector drawing rendered at 1× and 2×. Packaging joins them with
`tiffutil -cathidpicheck` into one TIFF, so Finder shows the sharp copy on
Retina screens.

The picture is original Parc artwork in the What's New page's language:

- Paper `#FFFCEC` with a warm centre glow and Parc's grain.
- "One little drag." in Cormorant Garamond SemiBold Italic, as on What's New,
  over the instruction line in Nunito Regular and Bold. Both fonts are under
  the SIL Open Font License ([Cormorant](../../Resources/WhatsNew/OFL.txt),
  [Nunito](../../Resources/NoteFonts/OFL.txt)), drawn into the picture.
- A squiggle arrow in `#3139FB`, the release-notes divider wave, with three
  red `#FC4C58` pop lines at its tip.
- A clay-red shore `#C64A42` under the icon labels, then a Parc-blue tide
  `#5860FF` with a wavy edge, two ripples and a paper boat.

Finder draws a background picture the same way in light and dark mode, but its
icon labels turn white in dark mode. White text on the paper would measure
about 1.1:1, so the labels sit on the shore instead, whose tone gives black and
white labels about 4.5:1 each. Both icons stay on the paper. Keep anything
important out of the bottom 30 points, since Finder may count the title bar
inside the window size.

The art lives here, not in `Resources/`, because the app build copies all of
`Resources/` into Parc.app.

## Layout

[`scripts/dmg_layout.py`](../../scripts/dmg_layout.py) owns the geometry and
the Finder file format:

- A 640 × 400 window at (200, 120) with the toolbar, sidebar, path bar, tab
  bar and status bar hidden.
- Icon view with 128-point icons and 13-point labels underneath, arranged by
  hand: Parc at (160, 204) and Applications at (480, 204), measured to icon
  centres.
- A picture background pointing at the hidden `/.background/background.tiff`
  through a version 2 alias record: volume name and creation date, the file's
  and folder's IDs, and its paths.

It writes `.DS_Store` with the standard library as a single-page record tree
holding the window (`bwsp`), icon view (`icvp`), view style (`vstl`) and icon
positions (`Iloc`), and reads it back for verification. The format was checked
once against dmgbuild's `ds_store` and `mac_alias` libraries: each reads the
other's file as the same records, and `mac_alias` re-encodes Parc's alias byte
for byte. Neither library is used by Parc.

Change a position, size or picture together with the art, and update the fixed
digests in [`test_dmg_layout.py`](../../tests/Packaging/test_dmg_layout.py).

## Building and checking the image

[`scripts/package-dmg.py`](../../scripts/package-dmg.py) builds the image
before signing:

1. Stage a copy of the notarized app, the Applications shortcut, the TIFF in
   a hidden `.background` folder and the app's own `Parc.icns` as
   `.VolumeIcon.icns`.
2. Create a read-write image from the stage and mount it with `-nobrowse` in a
   temporary folder beside the package.
3. Write `.DS_Store` from the mounted files' real IDs, set the volume's
   custom-icon flag and check the layout on the spot.
4. Unmount, retrying five times before forcing it. A failed step still
   unmounts and reports its own error; a volume that refuses to unmount is
   left in place rather than deleted from under its mount.
5. Compress to UDZO in the same temporary folder and hard-link the result into
   place, so an interrupted build never leaves a partial image and an existing
   one is never overwritten.

Signing, notarization, stapling and receipts then run exactly as before.

`verify_dmg` mounts the image read-only and refuses it unless:

- the layout file holds exactly the planned records;
- the alias points at this volume's picture;
- the TIFF holds both sizes and its folder is hidden;
- the volume icon matches the app's icon with the custom-icon flag set.

The check runs before submission to Apple and again on the downloaded release
asset. The DMG receipt records that the image has an install window, so a
resumed image from before it skips only the layout check, and
`publish-homebrew.py` does the same for a release whose source predates this
folder. Publishing checks against the current checkout's layout, so change the
layout between releases rather than while one is being published.
