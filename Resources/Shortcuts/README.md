# Shortcut keycap face

`smiley.json` is the winking face on the second keycap of the shortcuts
introduction. Parc drew it for this project as a 100 × 100 Lottie timeline at
30 frames per second and 150 frames long: two round eyes and a smile, all white
strokes with round caps that `ShortcutSmileyView` masks to the accent color.

The face rests until frame 18, then snaps up and left with a tilt and a blink,
swings right, blinks again, squashes and pops into a wink, each move landing
with a small overshoot. The right eye closes like a blink
and opens again as an arc while the smile lifts toward it and the face tilts.
At frame 99 the eye blinks back open, and the face settles at frame 122 with a
slightly wider smile than it started with. Reduce Motion shows the first frame.

`ShortcutSmileyArtwork` reads the subset this file uses: one layer with
position, anchor, scale and rotation keyframes, and stroked groups with their own
transforms, path keyframes and animated widths. The shortcut detail and timer
idle checks cover the timeline, the resting and settled poses and the rendered
strokes. See [keyboard navigation](../../docs/keyboard-navigation.md).
