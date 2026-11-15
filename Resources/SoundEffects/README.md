# Sound effects

`capture.wav` is Parc's own screenshot shutter, synthesized for this project
from seeded filtered noise and short metallic resonances: a light lead-in tick,
a two-part shutter clack, a second-curtain click and a soft geared whirr that
fades out by 0.43 seconds. It is a 0.6-second stereo 24-bit WAV at 48 kHz,
peaking at −8.3 dBFS. `InterfaceSoundEffects` plays it at 70% volume when a
capture completes, only while Parc is active and sound effects are enabled.
