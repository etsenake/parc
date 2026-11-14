# Easel fonts

Easel text styles load these bundled fonts by PostScript name; see
[Easels](../../docs/easels.md#object-wide-text-styles).

- **Mono**: `SpaceMono-Regular.ttf` and `SpaceMono-Bold.ttf`, Space Mono from
  google/fonts. License: `OFL-SpaceMono.txt`.
- **Fancy**: `EBGaramond-VariableFont_wght.ttf`, EB Garamond from google/fonts.
  License: `OFL-EBGaramond.txt`.
- **Hip**: `ParcWide-Regular.ttf` (body), `ParcWide-SemiBold.ttf` (H2) and
  `ParcWide-Black.ttf` (display) are static cuts of Mona Sans
  (`MonaSans[wdth,wght].ttf` from google/fonts) at width 125 and weights 394,
  663 and 900. Mona Sans reserves the font name "Mona" under its SIL Open Font
  License, so these modified versions carry the family name Parc Wide; their
  copyright notice and license are unchanged. License: `OFL-MonaSans.txt`.

The SemiBold cut is styled Bold so AppKit's bold conversion within the Parc Wide
family lands on it. Recreate the cuts with fontTools:

```sh
python3 -m fontTools.varLib.instancer 'MonaSans[wdth,wght].ttf' wdth=125 wght=394 -o ParcWide-Regular.ttf
```

then rename the instance (name IDs 1, 2, 3, 4, 6, 16 and 17) to the Parc Wide
names above and set `usWeightClass` 400, 700 and 900.
