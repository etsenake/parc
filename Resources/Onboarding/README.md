# Welcome resources

Parc bundles the welcome audio, typefaces, background and setup icons described
below. Parc's P artwork comes from
`Resources/AppIcons/Original.png`. See [onboarding](../../docs/onboarding.md)
for playback and ownership.

## Welcome audio

`intro-music.mp3` is Parc's own welcome music, made for Parc by its author with
a tool whose terms permit commercial use. It is a 21-second stereo MP3 at
44.1 kHz and 192 kbps, mastered to peak at −1.2 dBFS with its body near
−13.5 dBFS. Onboarding plays it once at 30% volume. `scripts/build.py` copies
the complete Resources tree and links AVFoundation for playback.

## Typeface and background

- `Sniglet-ExtraBold.ttf` sets the "A browser for you." headline at 59 points.
  It is Sniglet ExtraBold from google/fonts under the SIL Open Font License in
  `OFL.txt`.
- Setup card titles (35 points) and the Essential Keyboard Shortcuts title
  (20 points) use Nunito ExtraBold from `Resources/NoteFonts`.
- `orb.mp4` and `background.mp4` are Parc's own silent H.264 loops at
  100 × 100 pixels and 30 frames per second, lasting 6 and 8 seconds. The orb
  grows from plain blue into a turning cluster of translucent blue petals with
  three pale highlights; the background drifts translucent blue blobs on a
  seamless 8-second cycle. Onboarding blurs both heavily, so only their color
  and motion read on screen.
- `orb-poster.png` and `background-poster.png` are each video's first frame.
- `grain-1.png` through `grain-4.png` are seeded colour noise frames at
  2100 × 1500 with constant 66/255 alpha: every pixel's red, green and blue
  are drawn independently with a bright-leaning spread, so the moving film
  grain reads as soft colour speckle rather than harsh grey static.
- `orb-mask.png` is a 630 × 630 smooth twelve-point blob that shapes the orb.

Parc resolves every file from its own bundle; Swift uses CoreText for the font and AVFoundation for media.

## Favorites artwork

The setup icons are the services' own logos, rendered from their published
SVGs (as mirrored on Wikimedia Commons) for the matching favorites: Twitter
(today's X mark, with a white `favorite-twitter-dark.png`), Gmail, Google
Calendar, Spotify, YouTube, Notion, Slack, Figma and Outlook. Each mark belongs
to its company and appears only beside a link to that service.

Setup displays them at 40 points. Twitter, Gmail, Google Calendar, Slack, Figma
and Outlook are 120 × 120 sRGB PNGs; Spotify, YouTube and Notion are
240 × 240. These setup resources are loaded only from Parc's bundle.
