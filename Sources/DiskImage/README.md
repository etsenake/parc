# Disk image install window

The disk image people download from GitHub opens as Parc's own install window
instead of Finder's plain folder: a big Parc icon, a squiggly arrow, the
Applications folder and "To install, drag Parc to Applications". Packaging
lays the window out with dmgbuild, which writes the volume's Finder files
directly; nothing opens or drives Finder.

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
- A little wooden park sign `#9B6C3F` under each icon, with ink outlines and
  faint wood grain, its two posts planted in a grassy knoll of turf over soil
  with teal tufts, standing on the paper well clear of the water. Finder's
  label lands on the board.
- A Parc-blue tide `#5860FF` with a wavy edge, two ripples and a paper boat.

Finder labels are black in light mode and white in dark mode, with no colour
setting, so the signs' wood is toned to read both ways at about 4.5:1.

The geometry follows Finder as it really draws this window, measured from a
1:1 screenshot rather than the requested sizes. The 400-point window includes
the 32-point title bar, so only the top 368 points of the picture show. Icons
fill a box of about 90 points centred on their position, and labels are 15
points with their baseline 67 points below the icon centre. Each board spans
49 to 76 points below the icon centre, so the label sits centred on it with
the icon clear above. The knolls end about 12 points above the highest wave.

The art lives here, not in `Resources/`, because the app build copies all of
`Resources/` into Parc.app.

## Layout

[`scripts/dmg_layout.py`](../../scripts/dmg_layout.py) owns the window's
settings and hands them to [dmgbuild](https://github.com/dmgbuild/dmgbuild),
which builds the image and writes Finder's layout file:

- A 640 × 400 window at (200, 120) with the toolbar, sidebar, path bar, tab
  bar and status bar hidden.
- Icon view with 128-point icons and 13-point labels underneath, arranged by
  hand: Parc at (160, 190) and Applications at (480, 190), measured to icon
  centres.
- The 1× and 2× art joined into a hidden `/.background.tiff`, which the icon
  view points at through an alias, and Parc's icon as the volume icon.

Parc used to write `.DS_Store` itself, and Finder ignored that file
completely: its block allocator didn't list its own bookkeeping block as block
0, as every file from Finder or dmgbuild does, so Finder opened a plain folder
window. dmgbuild's file for the same settings opens as designed.

dmgbuild 1.6.7 runs with ds_store 1.3.1 and mac_alias 2.2.2, the versions the
window was checked with in Finder. Like Sparkle, the three wheels are
downloaded from PyPI by exact URL and SHA-256 into the ignored
`build/dmgbuild/` on first use; a mismatched download is refused and nothing
is cached. Version 1.6.7 points at the background with an alias alone, without
the bookmark 1.6.6 added.

Change a position, size or picture together with the art, and update the
settings test in [`test_dmg_layout.py`](../../tests/Packaging/test_dmg_layout.py).

## Building and checking the image

[`scripts/package-dmg.py`](../../scripts/package-dmg.py) builds the image
before signing. dmgbuild creates a read-write image in a hidden temporary
folder beside the package, mounts it with `-nobrowse`, copies the notarized
app, adds the Applications shortcut, the background and the volume icon,
writes `.DS_Store`, unmounts it and compresses it to UDZO, logging to
`dmg-notarization/dmgbuild.log`. The image is then hard-linked into place, so
an interrupted build never leaves a partial image and an existing one is never
overwritten. Signing, notarization, stapling and receipts run as before.

`verify_dmg` mounts the image read-only and refuses it unless:

- `.DS_Store` is byte for byte what dmgbuild's writer produces for these
  settings and the image's own background alias: the same records (`bwsp`,
  `icvp`, `icvl`, `vSrn` and an `Iloc` per icon), types and record tree;
- the alias names this volume and its picture: mac_alias reads the same volume
  name and creation date, file and folder IDs, dates and paths from the alias
  and from the mounted file;
- the TIFF holds both sizes;
- the volume icon matches the app's icon with the custom-icon flag set.

The alias is compared field by field rather than resolved, because macOS
resolves it to any mounted volume called Parc that holds a file with the same
ID. [`test_dmg_layout.py`](../../tests/Packaging/test_dmg_layout.py) builds a
small real image with the pinned dmgbuild and checks that it passes, and that
the layout file shipped in 2.7.0 and tampered images are refused.

The check runs before submission to Apple and again on the downloaded release
asset. The DMG receipt records that the image has an install window, so a
resumed image from before it skips only the layout check. A resumed image laid
out by Parc's earlier writer is refused; to rebuild it, move that image and its
`dmg-notarization` folder aside and package again. Whether dmgbuild succeeds,
fails or is stopped, including by the release's stop signal, packaging then
detaches any image still mounted from its temporary folder before deleting it.
`publish-homebrew.py` checks the layout only for a release whose source builds
the window with dmgbuild: older published images can't change, and Finder
never read the earlier writer's layout. Publishing checks against the current
checkout's layout, so change the layout between releases rather than while
one is being published.
