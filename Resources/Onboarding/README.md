# Welcome resources

Parc bundles the welcome audio, typeface, background and setup icons described
`Resources/AppIcons/Original.png`. See [onboarding](../../docs/onboarding.md)
for playback and ownership.

## Welcome audio

`intro-music.mp3` comes from `ARC_AuthFeature.bundle`, with the same audio as
21.3 seconds long. `scripts/build.py` copies the complete Resources tree and
links AVFoundation for playback.

## Typeface and background

- `Sniglet-ExtraBold.ttf` sets the "A browser for you." headline at 59 points.
  It is Sniglet ExtraBold from google/fonts under the SIL Open Font License in
  `OFL.txt`.
- Setup card titles (35 points) and the Essential Keyboard Shortcuts title
  (20 points) use Nunito ExtraBold from `Resources/NoteFonts`.
  silent and 100 × 100 pixels, lasting 6 and 8 seconds respectively.
- `orb-poster.png` and `background-poster.png` are native AVFoundation exports
  of each video's first frame.
- `grain-1.png` through `grain-4.png` are native catalog exports at 2100 × 1500.
- `orb-mask.png` is a 630 × 630 raster of the `animatingOrbBlob1` vector asset.

from its own bundle; Swift uses CoreText for the font and AVFoundation for media.

## Favorites artwork

The setup icons use the BaseAssets resource names `twitter`, `gmail`, `gcal`,
`spotify`, `youtube`, `notion`, `slack`, `figma` and `outlook`. Their bundled
filenames are `favorite-<name>.png`, with `favorite-twitter-dark.png` for the
dark variant. Twitter's current source artwork depicts X; the other icons
share one image across appearances.

AppKit exported these images under explicit Aqua and Dark Aqua appearances.
Setup displays them at 40 points. Twitter, Gmail, Google Calendar, Slack, Figma
and Outlook are 120 × 120 drawings of the catalog's vector renditions across
their full logical frame: 24 points for Twitter and 32 for the others. They
use Display P3 because the Slack, Gmail and Google Calendar vectors specify
that color space. The exports support a 3× display without enlarging the
catalog's smaller bitmaps.

Spotify, YouTube and Notion are 240 × 240 PNGs. Notion's source is a 120-pixel
bitmap with no vector rendition. These setup resources are loaded only from
Parc's bundle.
