# Notes file format

Every Parc note is a plain Markdown file that reads as you'd expect in GitHub,
Obsidian, VS Code or any text editor. This guide is for people who edit those
files by hand; the editor itself is described in [Notes](notes.md).

The note's title is its file name without the extension, so the body never
repeats it. `.txt` (or `.text`) files open in plain-text mode: each line is one
paragraph, formatting is off, and the file is saved exactly as typed.

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
- **Code.** The fence's first word is the language; the rest (such as
  `title="app.js"`) is kept, as are tildes, backticks and a longer fence.
- **Reference links and footnotes.** `[text][label]` links work; `[label]: url`
  lines, `[^1]: ...` footnotes and `[^1]` markers stay word for word.

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
| `cover-credit`, `cover-credit-url` | Who took the cover photo and a link to them |
| `font` | `serif`, `mono` or `wide`; leave it out for the default |
| `small-text`, `full-width`, `locked` | `true` to turn on; Parc leaves them out when off |
| `backlinks` | `expanded` or `off`; left out for the default popup |

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
pairs. Parc writes `color`, `icon`, `width`, `height` (an embed's or Easel's height),
`align`, `crop` and `mask` (an image's framing), `caption`, `wrap` (code that wraps), `view` (`code` or `split` for a Mermaid block; Preview writes nothing), the table flags `no-header-row`, `header-column` and
`widths="120,,80"`, the table's `merge` and `colors` (see below), the bookmark and capture fields, and a block kind (`paragraph`,
`image`, `video`, `audio`, `file`, `pdf`, `embed`, `easel` or `bookmark`) when the file
wouldn't otherwise make the kind clear. An empty paragraph that has a colour is
written as `<!-- parc paragraph color="…" -->` on its own line.

### Merged cells and cell colours

A pipe table can't merge cells, so Parc keeps the table readable and lists the
merges in its comment with spreadsheet references. A merged-away cell is
written empty, and the merged cell's text sits in its top-left cell:

```markdown
| Name | Q1  |     |
| ---- | --- | --- |
| Ada  | 3   | 4   |
<!-- parc merge="B1:C1" colors="A:A=gray_background,B2:C2=red" -->
```

`colors` gives each cell's colour, using the same names as `color`: `A:B` is
whole columns, `2:3` whole rows and `B2:C2` a block of cells. If text turns up
in a merged-away cell (say, typed in another editor), the merge is dropped so
nothing is hidden. Exports write merges as `colspan` and `rowspan`, and HTML
tables pasted from elsewhere bring theirs along.

### Block links

Copy Link to Block gives a block a short, stable `id` the first time you copy
its link, and saves it in the same comment:

```markdown
Ship the beta on Friday. <!-- parc id="k3x9qa" -->
```

The link is the note's `file://` URL with `#k3x9qa` on the end. Opening it
scrolls to that block. Headings also answer to their GitHub-style slug, so
`Plans.md#next-steps` and `Plans.md#Next%20Steps` both find `## Next steps`,
and an `id` on a heading doesn't change its slug. Copies of a block don't keep
its `id`, except a [synced block](#synced-blocks)'s original, so cutting and
pasting moves it.

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
makes the callout fold open or closed.

A plain callout from Parc is saved as `[!NOTE]` and always carries a Parc
comment, a bare `<!-- parc -->` when it has no icon or colour. A `[!NOTE]`
without one is GitHub's note, shown blue with ℹ️. Give a GitHub note your own
icon or colour and its comment gets an `alert` flag, as in
`<!-- parc alert icon="🌳" -->`, so it stays a note. When the callout's text
is empty but a paragraph follows, the comment goes on its own line to keep the
place of the missing text.

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

## Buttons

A button is a `<details>` block whose summary carries the `button` flag, so
GitHub shows its name and, when opened, the blocks it inserts:

```markdown
<details>
<summary>✅ Add a task <!-- parc button icon="✅" --></summary>

- [ ] New task

</details>
```

The summary is the icon and the name; `icon` keeps the emoji apart from the
name, and `color` and `id` work as for any block. When the button only inserts
blocks below itself, the blocks simply sit inside. Anything else spells out each
action, in order, as its own comment line, and an insert's blocks follow its
line:

```markdown
<details>
<summary>🚀 Launch <!-- parc button icon="🚀" --></summary>

<!-- parc confirm="Ready to launch?" -->

<!-- parc insert="top" -->

## Launch log

<!-- parc open="Release%20plan.md" -->

</details>
```

`insert` takes `below`, `above`, `top` or `bottom`; `confirm` holds the message
(empty for the plain "Are you sure?"); `open` holds a web address or a relative
link to a note. A button with no actions closes its `<details>` right after the
summary, and `open` on `<details>` is kept as you wrote it. Blocks written before
the first action line count as inserted below.

## Synced blocks

A synced block's original sits between two comments and carries its `id`. A
copy names it with `from`, a link relative to the copy's note (just `#k3x9qa`
in the same note), and keeps a snapshot of the content, so other apps show
plain Markdown:

```markdown
<!-- parc synced id="k3x9qa" -->

Weekly goals

<!-- parc /synced -->

<!-- parc synced from="Plans.md#k3x9qa" -->

Weekly goals

<!-- parc /synced -->
```

Parc refreshes a copy's snapshot whenever the original changes and rewrites
`from` when the original's note moves or is renamed. An opener without a closer
stays as written.

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
nest, and outer fences grow a colon per level inside. Blocks placed directly
inside `columns` get a column of their own.

## Nested blocks under text

Lists, quotes, callouts and toggles nest the usual Markdown way. A paragraph or
plain heading has no Markdown container of its own, so its children go in an
`indent` directive fence right after it:

```markdown
Plans for the weekend

::: indent
Saturday is for the market.

- Apples
- Bread
:::

## Packing

:::: indent
Clothes

::: indent
Socks, lots of socks.
:::
::::
```

The fence belongs to the block just before it. An outer fence is one colon
longer than any fence inside it (columns follow the same rule), though any line
of three or more colons closes the innermost one, as in Pandoc. A fence with no
block before it gets an empty line as its parent, and one after a list item,
quote, callout or toggle nests inside that block. GitHub and Obsidian show the
fence lines as plain text with the nested blocks between them.

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
YouTube, Vimeo, Figma, Loom, Spotify and similar sites become embeds, and
`![](https://…) <!-- parc embed -->` makes any web address one. An embed shows the live page
in the note, `height="640"` sets its height, and the default height writes
nothing ([embedded pages](embedded-pages.md#live-embeds-in-notes)).

```markdown
![A sleepy cat](Attachments/cat.png "My *favourite* photo") <!-- parc width="320" align="left" -->

![](Attachments/demo.mov)

![report.pdf](Attachments/report.pdf)
```

The text in brackets is the alt text, which screen readers announce and the
exports use, and the quoted title is the caption. Pasted and dropped files live
in an `Attachments` folder beside the note. A photo credit, such as one from
Unsplash, goes in the comment as
`credit="Jane Doe" credit-url="https://unsplash.com/@jane"`.

Cropping and shapes never touch the picture itself. They're saved in the
comment, so other apps simply show the whole image:

```markdown
![Our team](Attachments/team.jpg) <!-- parc crop="0.1,0.05,0.8,0.9" mask="rounded" -->
```

`crop` lists the left edge, top edge, width and height of the part to show, as
fractions of the whole picture with up to four decimals; a crop that spills over
the edge is pulled back inside. `mask` is `rounded`, `circle`, `squircle`,
`arch`, `diamond`, `hexagon`, `star` or `heart`. HTML exports draw both with CSS,
and PDF exports match the editor.

An **inline PDF** is the same image-style line with a `pdf` flag. Without the
flag a PDF stays a file row, so older notes keep their look:

```markdown
![report.pdf](Attachments/report.pdf "Q3 numbers") <!-- parc pdf width="0.6" align="left" -->
```

`width` is a fraction of the column (or points, when above 1) and is left out
at full width. A hand-written link, `[Report](report.pdf) <!-- parc pdf -->`,
reads as a PDF too and is saved in the image form. Plain-text notes keep only
the file's path on its own line. HTML export shows the PDF in an `<object>`
(embedded in the file when it's under 25 MB) with a link to the original.

A **capture** is an image sent from Parc's capture tool, flagged with its page:
`![Story](Attachments/Story.png) <!-- parc capture="https://…" captured="2026-11-20T15:04:05Z" viewport="1280,800" scroll="0,1200" region="10,20,400,300" -->`.
`viewport`, `scroll`, `region` (CSS pixels) and, inside a scrolled panel, `scrollers` let it go
live; `fullpage` makes it go live as a scrollable page, not a framed region; `live` marks it live. Exports show the image with a "Captured from" link.

A **bookmark** is a link on its own line plus its cached preview:

```markdown
[The Verge](https://www.theverge.com) <!-- parc bookmark summary="Tech news" site="The Verge" thumbnail="https://…/og.png" favicon="https://…/icon.png" -->
```

A **page link** is a link to another note on its own line:
`[Project plan](Project%20plan.md)`. Paths are relative to the note.

An **Easel** is a link to its `parc://easel/<id>` address, the one Easel tabs
use, flagged `easel`. Easels live in the Profile, so the note points at one:
`[Moodboard](parc://easel/6f1c2a4e-…) <!-- parc easel width="0.6" height="560" -->`.
The link text is the Easel's title when it was added; Parc shows the current one.
`width` and `align` work as for a PDF and `height` as for an embed; defaults
write nothing. An unflagged Easel link stays a link. Markdown exports write the
link, HTML exports a picture of the canvas above it, `.txt` notes the address.

## Mentions and inline extras

- **Page mentions** are `[[Note name]]` or `[[Folder/Note|Shown as]]` wiki
  links, or a relative link whose text is the note's name, such as
  `[Roadmap](Roadmap.md)`. When a note is renamed or moved, in Parc or Finder, Parc rewrites these,
  and plain links to the file, in place, keeping wiki links as wiki links.
- **Date mentions** are `<time datetime="2026-11-20">2026-11-20</time>`. Add a
  time with `T09:30` and a reminder with `data-remind`. More settings are
  attributes, written in this order, and left out when they're the default:

  ```markdown
  <time datetime="2027-01-03T09:00" data-end="2027-01-05T17:30" data-timezone="America/New_York" data-remind="30m" data-format="full" data-clock="24h">2027-01-03 09:00 → 2027-01-05 17:30</time>
  ```

  `data-end` makes a range. `data-remind="30m"` rings that long before the
  start (`m`, `h`, `d` or `w`; a bare `data-remind` rings at the start, or at
  9 AM for a whole day). `data-timezone` pins the time to an IANA zone.
  `data-format` is `full`, `short`, `mdy`, `dmy` or `ymd` instead of the
  default, which says Today, Tomorrow or Yesterday when it can, and
  `data-clock` is `12h` or `24h`. The text between the tags is a fallback for
  other apps. A `<time>` tag with anything Parc doesn't recognise is kept as
  written.
- **Link mentions** are `<a href="https://…" data-mention>Page title</a>`.
- **Custom emoji** are `:name:`; see [custom emoji](#custom-emoji).
- **Table of contents** is `<!-- toc -->` on its own line.
- **Breadcrumb** is `<!-- parc breadcrumb -->` on its own line. The path itself
  isn't saved, since it follows wherever the file lives; a colour or block link
  goes in the same comment, as in `<!-- parc breadcrumb color="gray" -->`.

Inline things Parc can't edit as text are kept verbatim: a mid-sentence image,
`<kbd>` and other unknown HTML, footnote markers, Obsidian embeds like
`![[diagram.png]]` and inline `$$…$$`. A link around an image (such as a README
badge) stays on the image. HTML blocks, reference definitions and footnotes stay
as written.

## Custom emoji

A note's custom emoji library is the `.parc/emoji` folder in the nearest
folder above the note that has one, up to the Space's Notes folder; without one
it's the Notes folder holding the note, or the note's own folder. Each emoji is
an image named after it, such as `.parc/emoji/party-parrot.png`, and
`emoji.json` beside them lists the names and any old names:

```json
{
  "emoji" : [
    { "aliases" : [ "parrot" ], "file" : "party-parrot.png", "name" : "party-parrot" }
  ],
  "version" : 1
}
```

Names are lowercase letters, digits, `-`, `_` and `+`. An image dropped into the
folder by hand joins the library under its file name. In text, `:party-parrot:`
shows the image when the library has that name (or had it before a rename) and
stays plain text otherwise, so `:tada:` in a README is left alone. When the
library does have the name, text that should stay text is saved as
`\:party-parrot:`. Icons use the same shortcode: `icon: ":party-parrot:"` in
front matter and `<!-- parc icon=":party-parrot:" -->` on a callout. HTML and
PDF exports embed the images. Move or copy the folder with its `.parc` folder
and the emoji come along.

## What changes when Parc saves

Parc keeps your file's meaning and as much style as it can. Deliberate changes:

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
- A note that opens with a divider gets one space before that `---` when a
  later `---` or `...` line would otherwise turn the top into front matter.
- Indented code that carries a colour, caption or other setting is saved as a
  fenced block, and so is indented code right after a list.
- Reference definitions followed by an indented line that can't start a
  paragraph on its own, such as `<details>`, stay together as one raw block,
  because Markdown has no way to write that paragraph by itself.
- Any other text that would open such a block when it starts a line (for
  example `<div>` left behind by an empty tag) gets an empty `<b></b>` in
  front, so it stays text.

Everything else, including HTML Parc doesn't model, comes back as it was read.

## For developers

The codec in `Sources/ParcCore/NoteMarkdown*.swift` reads a file into a
`NotePage` with CommonMark block and inline parsers; the writer checks each run
of inline text by parsing it back. Windowless tests cover fixtures, real
samples and random pages that must survive a save and reload unchanged:

```sh
swift test --filter Markdown
```
