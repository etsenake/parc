# Notes file format

Every Parc note is a plain Markdown file. You can open it in GitHub, Obsidian,
VS Code or any text editor and it reads the way you'd expect. This guide is for
people who edit those files by hand or want to know what Parc writes. The
editor itself is described in [Notes](notes.md).

The note's title is its file name without the extension, so the body never
repeats it. Files ending in `.txt` (or `.text`) open in plain-text mode: each
line is one paragraph, formatting is off, and the file is saved exactly as
typed.

## The core: CommonMark and GitHub Markdown

Parc reads [CommonMark](https://spec.commonmark.org) with the GitHub additions:
ATX (`#`) and underlined headings, paragraphs, bullet and numbered lists (any
marker, any start number, `.` or `)`), task items, quotes, fenced and indented
code, horizontal rules, pipe tables with alignment, HTML blocks, reference
links, footnotes, `~~strikethrough~~` and bare URLs that turn into links.

A few details worth knowing:

- **Line breaks.** A plain line break inside a paragraph stays a line break in
  your file and in the editor, but GitHub shows it as a space. A break that
  should show everywhere is written with a trailing backslash (`\`). Two
  trailing spaces work too, and Parc saves them as a backslash.
- **Blank lines.** One blank line separates blocks. Each extra blank line is an
  empty paragraph in Parc, so leaving visual space survives a round trip.
- **Lists.** Parc keeps your bullet character (`-`, `*` or `+`), the `)`
  delimiter, the start number and whether items are separated by blank lines.
  Numbers after the first item are rewritten in order. A numbered list that
  starts again right after another one is separated with `<!-- -->`, the usual
  CommonMark trick.
- **Code.** The info string after the fence gives the language. Anything after
  the first word (such as `title="app.js"`) is kept as is. Parc keeps tildes or
  backticks, and a longer fence if you used one.
- **Reference links and footnotes.** `[text][label]` links work. The
  `[label]: url` lines and `[^1]: ...` footnotes stay in your file word for word.
  Footnote markers like `[^1]` are kept too.

## Page settings (front matter)

Settings live in YAML front matter at the very top of the file:

```yaml
---
icon: 🍎
cover: Attachments/cover.jpg
cover-position: 0.3
font: serif
small-text: true
full-width: true
locked: true
tags:
  - work
status: draft
---
```

| Key | Meaning |
| --- | --- |
| `icon` | An emoji, or a path or URL to an image |
| `cover` | Cover image path or URL |
| `cover-position` | Vertical focus of the cover, from 0 (top) to 1 (bottom); 0.5 is left out |
| `font` | `serif`, `mono` or `wide`; leave it out for the default |
| `small-text`, `full-width`, `locked` | `true` to turn on; Parc leaves them out when off |

Any other simple key becomes a page property: text, numbers, `true`/`false`,
dates (`2026-11-20` or `2026-11-20T09:30`) and lists of words. Lists can be
written `[a, b]` or one item per line; Parc saves them one per line, the way
Obsidian does. Anything more complex (nested maps, multi-line text, anchors,
comments) is kept exactly as written. Parc writes settings first, then
properties, then the kept lines.

## Text styles

| Style | Written as |
| --- | --- |
| Bold, italic, strikethrough, code | `**bold**`, `*italic*`, `~~strike~~`, `` `code` `` |
| Underline | `<u>underlined</u>` |
| Text colour | `<span data-color="red">red text</span>` |
| Background colour | `<mark data-color="blue_background">highlighted</mark>` |
| Yellow highlight | `==highlighted==` |
| Link | `[text](https://example.com)`, or a bare URL |

The nine colours are `gray`, `brown`, `orange`, `yellow`, `green`, `blue`,
`purple`, `pink` and `red`. Add `_background` to colour the background
instead of the text. Parc also understands `<b>`, `<strong>`, `<i>`, `<em>`,
`<s>`, `<del>`, `<ins>`, `<code>`, a plain `<mark>` and `<a href="…">`, and
saves them in the Markdown form above. When text can't be written with
Markdown symbols (for example bold that starts with a space), Parc falls back
to the HTML tags instead of guessing.

## Block colours and other block settings

Settings that Markdown can't express go in a small HTML comment. GitHub,
Obsidian and VS Code hide it. For a text block it goes at the end of the
block's last line:

```markdown
Remember the milk <!-- parc color="yellow_background" -->

## Plans <!-- parc color="blue" -->

- An urgent item <!-- parc color="red" -->
```

For a block with no text line of its own (a divider, code, an equation, a
table, columns or the table of contents) the comment goes on the line right
after it:

```markdown
---
<!-- parc color="gray" -->
```

The comment always starts with `parc`, followed by words and `name="value"`
pairs. Parc writes `color`, `icon`, `width`, `align`, `caption`, `wrap` (code
that wraps), the table flags `no-header-row`, `header-column` and
`widths="120,,80"`, the bookmark fields, and a block kind (`paragraph`,
`image`, `video`, `audio`, `file`, `embed` or `bookmark`) when the file
wouldn't otherwise make the kind clear. An empty paragraph that has a colour is
written as `<!-- parc paragraph color="…" -->` on its own line.

## Callouts

Callouts are GitHub alerts, which Obsidian reads as callouts:

```markdown
> [!TIP]
> Press ⌘K to search everything. <!-- parc icon="💡" color="yellow_background" -->
>
> Callouts can hold more blocks underneath.
```

The text after the marker is the callout's own text. Any further blocks are
its children. `NOTE`, `TIP`, `IMPORTANT`, `WARNING` and `CAUTION` (in capitals)
follow GitHub's layout. Any other type, such as Obsidian's `> [!faq]- Title`,
keeps the text on the marker line as the title. A `+` or `-` after the marker
makes the callout fold open or closed. A plain callout from Parc is saved as
`[!NOTE]`. When the callout's text is empty but a paragraph follows, a bare
`<!-- parc -->` line keeps the place of the missing text.

## Toggles and toggle headings

Toggles use HTML disclosure, which GitHub renders as a working toggle:

```markdown
<details open>
<summary>Packing list</summary>

- Passport
- Charger

</details>
```

`open` means the toggle is expanded. A toggle heading wraps the heading level
in the summary: `<summary><h2>Section</h2></summary>`. Leave a blank line
after `<summary>` and before `</details>` so the blocks inside are read as
Markdown.

## Columns

Columns use directive fences, which Pandoc also understands:

```markdown
:::: columns
::: column
Left side
:::
::: {.column width="40%"}
Right side
:::
::::
```

A bare line of three or more colons closes the innermost column. Columns can
nest. Blocks placed directly inside `columns` get a column of their own.

## Equations

A block equation sits between `$$` lines. A fenced ```` ```math ```` block also
works and is kept as a fence. Inline equations are `$x^2$`. To keep prices
safe, the opening `$` must be followed by a non-space, and the closing `$`
must follow a non-space and not be followed by a digit. So "costs $5 and $10"
stays text. Use `\$` for a literal dollar sign where it would be ambiguous.

## Media, bookmarks and page links

A paragraph that holds a single image becomes a media block. The file
extension picks the kind: pictures are images; `mp4`, `mov` or `webm` are
video; `mp3`, `m4a` or `wav` are audio; anything else is a file. Links to
YouTube, Vimeo, Figma, Loom, Spotify and similar sites become embeds.

```markdown
![A sleepy cat](Attachments/cat.png "My *favourite* photo") <!-- parc width="320" align="left" -->

![](Attachments/demo.mov)

![report.pdf](Attachments/report.pdf)
```

The text in brackets is the alt text and the quoted title is the caption.
Pasted and dropped files live in an `Attachments` folder beside the note.

A **bookmark** is a link on its own line plus its cached preview:

```markdown
[The Verge](https://www.theverge.com) <!-- parc bookmark summary="Tech news" site="The Verge" thumbnail="https://…/og.png" favicon="https://…/icon.png" -->
```

A **page link** is a link to another note on its own line:
`[Project plan](Project%20plan.md)`. Paths are relative to the note.

## Mentions and inline extras

- **Page mentions** are `[[Note name]]` or `[[Folder/Note|Shown as]]` wiki
  links, or a relative link whose text is the note's name, such as
  `[Roadmap](Roadmap.md)`.
- **Date mentions** are `<time datetime="2026-11-20">2026-11-20</time>`. Add a
  time with `T09:30` and a reminder with `data-remind`.
- **Link mentions** are `<a href="https://…" data-mention>Page title</a>`.
- **Table of contents** is `<!-- toc -->` on its own line.

Inline things Parc can't edit as text are kept verbatim: an image in the
middle of a sentence, `<kbd>` and other unknown HTML, footnote markers,
Obsidian embeds like `![[diagram.png]]`, and inline `$$…$$`. A link wrapped
around an image (such as a README badge) keeps the link on the image. HTML
blocks, reference definitions and footnotes stay as you wrote them.

## What changes when Parc saves

Parc keeps the meaning of your file and as much of its style as it can track.
These normalizations are deliberate:

- Emphasis is written `*italic*` and `**bold**`. Underscore forms are read but
  not kept.
- Closing `#` marks on headings are dropped. Underlined headings stay underlined.
- Numbered items are renumbered in order from their start number.
- A link whose text is its own address is written as a bare URL when that's
  safe, otherwise as `<https://…>`.
- Tables are padded so the columns line up.
- Exactly one blank line separates blocks, plus one per empty paragraph.
- Only characters that would change the meaning are escaped. `snake_case`,
  `2 * 3` and `$5` stay as they are.
- A trailing empty paragraph inside a list item is dropped.

Everything else, including HTML and constructs Parc doesn't model, comes back
the way it was read.

## For developers

The codec lives in `Sources/ParcCore/NoteMarkdown*.swift`. A CommonMark block
parser and an inline parser using the spec's delimiter algorithm read the file
into a `NotePage`. The writer produces Markdown and checks each run of inline
text by parsing it back, switching to HTML tags and full escaping if the check
fails. Parsing a 5,000-line file stays well under 100 ms. The windowless tests
cover hand-written fixtures, real README, changelog and note samples, and
randomly generated pages that must survive a save and reload unchanged:

```sh
bash scripts/test-notes-editor.sh Markdown
```
