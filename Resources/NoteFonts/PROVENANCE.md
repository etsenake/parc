# Notes fonts

Nunito is by the Nunito Project Authors (Vernon Adams) under the SIL Open Font
License 1.1, with no reserved font name. Its copyright notice and complete
license are in [OFL.txt](OFL.txt), and each font embeds its name, copyright and
license metadata.

`Nunito-ExtraBold.ttf` (version 3.602) is the weight-800 instance of
google/fonts' `ofl/nunito/Nunito[wght].ttf`:

```sh
python3 -m fontTools.varLib.instancer 'Nunito[wght].ttf' wght=800 --update-name-table -o Nunito-ExtraBold.ttf
```

Parc registers it locally for 34-point Notes titles, setup card titles and the
Essential Keyboard Shortcuts title.

`Nunito-Regular.ttf`, `Nunito-Bold.ttf`, `Nunito-Italic.ttf` and
`Nunito-BoldItalic.ttf` support the 18-point body and native emphasis/round-trip
operations in the same registered family. They retain their embedded SIL OFL
notices and use the same bundled license. Native components inspect that
metadata. No installed browser is required.

The upstream license source is the
[Nunito project](https://raw.githubusercontent.com/googlefonts/nunito/main/OFL.txt).
