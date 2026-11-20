# Notes emoji data

`emoji.json` feeds the Notes emoji picker, page and callout icons and the `:`
emoji suggestions. It is generated once from three sources and committed as
data; the generator is not part of the repository.

| Source | Version | License |
| --- | --- | --- |
| [`emoji-test.txt`](https://unicode.org/Public/emoji/latest/emoji-test.txt) | Emoji 18.0 (2026-04-30) | Unicode License V3, below |
| CLDR English [annotations](https://github.com/unicode-org/cldr-json/tree/49.0.0/cldr-json/cldr-annotations-full) and [derived annotations](https://github.com/unicode-org/cldr-json/tree/49.0.0/cldr-json/cldr-annotations-derived-full) | CLDR 49.0.0 | Unicode License V3, below |
| [github/gemoji](https://github.com/github/gemoji) `db/emoji.json` aliases | 4.1.0 | MIT, in [LICENSE-gemoji.txt](../CustomInfoPicker/LICENSE-gemoji.txt) |

## Shape

The file holds `unicode`, `cldr` and `gemoji` version strings and `groups`, the
Unicode groups in file order without `Component`. Each group has a `name` and
its fully-qualified emoji in Unicode order. An emoji is an object with:

- `e`, the fully-qualified character sequence;
- `n`, the Unicode short name;
- `k`, CLDR keywords, lowercased, without the full name or single words
  already in it; regional-indicator flags also get their two-letter region code;
- `c`, gemoji shortcodes, when gemoji has the emoji;
- `s`, the five single-tone variants from light to dark, when the emoji takes
  skin tones; multi-person emoji list the variant with both people in the same
  tone;
- `v`, the Emoji version that introduced it, so Parc can hide emoji the
  system font can't draw yet.

Toned and mixed-tone sequences are folded into their base entry. The file has
1,923 emoji, 332 of them with skin tones and 1,870 with shortcodes.

## Unicode License V3

COPYRIGHT AND PERMISSION NOTICE

Copyright © 2015-2026 Unicode, Inc.

NOTICE TO USER: Carefully read the following legal agreement. BY
DOWNLOADING, INSTALLING, COPYING OR OTHERWISE USING DATA FILES, AND/OR
SOFTWARE, YOU UNEQUIVOCALLY ACCEPT, AND AGREE TO BE BOUND BY, ALL OF THE
TERMS AND CONDITIONS OF THIS AGREEMENT. IF YOU DO NOT AGREE, DO NOT
DOWNLOAD, INSTALL, COPY, DISTRIBUTE OR USE THE DATA FILES OR SOFTWARE.

Permission is hereby granted, free of charge, to any person obtaining a
copy of data files and any associated documentation (the "Data Files") or
software and any associated documentation (the "Software") to deal in the
Data Files or Software without restriction, including without limitation
the rights to use, copy, modify, merge, publish, distribute, and/or sell
copies of the Data Files or Software, and to permit persons to whom the
Data Files or Software are furnished to do so, provided that either (a)
this copyright and permission notice appear with all copies of the Data
Files or Software, or (b) this copyright and permission notice appear in
associated Documentation.

THE DATA FILES AND SOFTWARE ARE PROVIDED "AS IS", WITHOUT WARRANTY OF ANY
KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT OF
THIRD PARTY RIGHTS.

IN NO EVENT SHALL THE COPYRIGHT HOLDER OR HOLDERS INCLUDED IN THIS NOTICE
BE LIABLE FOR ANY CLAIM, OR ANY SPECIAL INDIRECT OR CONSEQUENTIAL DAMAGES,
OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS,
WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION,
ARISING OUT OF OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THE DATA
FILES OR SOFTWARE.

Except as contained in this notice, the name of a copyright holder shall
not be used in advertising or otherwise to promote the sale, use or other
dealings in these Data Files or Software without prior written
authorization of the copyright holder.

SPDX-License-Identifier: Unicode-3.0
