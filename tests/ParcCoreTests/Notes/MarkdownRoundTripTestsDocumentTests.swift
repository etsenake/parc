import Foundation
import Testing
@testable import ParcCore

struct MarkdownRoundTripTestsDocumentTests {
    private let readme = """
    <p align="center">
      <img src="docs/logo.svg" width="120" alt="Parc logo">
    </p>

    # Parc

    [![Build](https://github.com/example/parc/actions/workflows/ci.yml/badge.svg)](https://github.com/example/parc/actions) [![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

    A calm browser for people who keep too many tabs open. Parc puts your tabs in a
    sidebar, sorts them into Spaces and lets old ones quietly archive themselves.

    > [!IMPORTANT]
    > Parc needs macOS 15 or later.

    ## Install

    ```sh
    brew install --cask parc
    ```

    Or grab the latest `.dmg` from the [releases page](https://github.com/example/parc/releases).

    ## Features

    - **Spaces** for work, home and side projects
    - Split view with up to *four* pages
    - A command bar (`⌘T`) that searches tabs, history and bookmarks
      - Fuzzy matching
      - Recent first
    - Notes stored as plain Markdown files

    ## Building from source

    1. Install Xcode 17.
    2. Clone the repository:

       ```sh
       git clone https://github.com/example/parc.git
       ```

    3. Run `scripts/build.sh` and wait. It's a big engine.

    | Script                | What it does            |
    | :-------------------- | :---------------------- |
    | `scripts/build.sh`    | Builds the app          |
    | `scripts/test.sh`     | Runs every test         |
    | `scripts/release.sh`  | Signs and notarizes     |

    <details>
    <summary>Troubleshooting</summary>

    If the build stalls, delete `build/` and try again. Still stuck? Open an
    [issue][issues].

    </details>

    ## License

    MIT © 2026 The Parc authors. See [LICENSE](LICENSE).

    [issues]: https://github.com/example/parc/issues

    """

    private let changelog = """
    # Changelog

    All notable changes to this project are documented here. The format follows
    [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project uses
    [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

    ## [Unreleased]

    ### Added

    - Notes are now plain Markdown files you can open anywhere.
    - Drag a tab onto a note to drop in a bookmark.

    ## [2.11.0] - 2026-11-18

    ### Fixed

    - The sidebar no longer flickers when you switch Spaces (#1234).
    - Downloads keep their names when the server sends `Content-Disposition`.

    ### Changed

    - Bumped the engine to Chromium 157.

    ## [2.10.2] - 2026-10-30

    ### Security

    - Patched a crash in the PDF viewer. Thanks to @sec-researcher for the report.

    [Unreleased]: https://github.com/example/parc/compare/v2.11.0...HEAD
    [2.11.0]: https://github.com/example/parc/compare/v2.10.2...v2.11.0
    [2.10.2]: https://github.com/example/parc/releases/tag/v2.10.2

    """

    private let meeting = """
    ---
    icon: 🗓️
    tags:
      - meetings
      - design
    attendees:
      - Ada
      - Grace
      - Linus
    date: 2026-11-20
    ---

    ## Design sync

    Present: [[Ada Lovelace]], [[Grace Hopper|Grace]] and Linus.

    ### Agenda

    1. Review the new toolbar
    2. Decide on the ==default font==
    3. Anything else

    ### Notes

    - Toolbar feels *much* lighter. Keep the springy hover.
    - Font: go with **Nunito** for body text, ~~Helvetica~~ is out.
    - Check contrast on dark Spaces <!-- parc color="orange" -->

    > [!TIP]
    > Record the next one so Linus can catch up.

    ### Action items

    - [ ] Ada: ship the toolbar behind a flag by <time datetime="2026-11-27">2026-11-27</time>
    - [x] Grace: share the font specimens
    - [ ] Linus: write up [the contrast rules](Design/Contrast.md)

    ---

    Next meeting: <time datetime="2026-11-27T10:00" data-remind>2026-11-27 10:00</time>

    """

    private let obsidian = """
    ---
    aliases:
      - Zettel 42
    created: 2026-11-19T21:14
    rating: 4
    ---

    # On writing things down

    Writing is thinking made visible. See also [[Zettelkasten]] and [[Reading list#Books|my books]].

    > [!quote] Seneca
    > While we are postponing, life speeds by.

    > [!info]- Collapsed by default
    > Hidden details live here.
    >
    > - Even lists

    The energy of a photon is $E = h\\nu$, and in general

    $$
    E^2 = (pc)^2 + (mc^2)^2
    $$

    A thought with a footnote.[^seneca]

    ![[diagram.png]]

    [^seneca]: *Letters from a Stoic*, letter 1.

    """

    private let docs = """
    # Configuration

    Parc reads its settings from `~/Library/Application Support/Parc/settings.json`.
    Most people never need to touch it.

    > [!WARNING]
    > Editing this file while Parc is running can lose your changes.

    ## Keys

    | Key | Type | Default |
    | --- | --- | --- |
    | `archiveAfter` | number | `12` |
    | `theme` | string | `"system"` |

    ### `archiveAfter`

    Hours before an idle tab archives itself. Set it to `0` to turn archiving off.

    ```json
    {
      "archiveAfter": 24
    }
    ```

    <details>
    <summary>Why hours, not days?</summary>

    Because a day is a long time on the internet.

    </details>

    :::: columns
    ::: column
    **Before**

    Tabs everywhere.
    :::
    ::: column
    **After**

    Calm.
    :::
    ::::

    """

    private var samples: [String: String] {
        ["readme": readme, "changelog": changelog, "meeting": meeting, "obsidian": obsidian, "docs": docs]
    }

    @Test(arguments: ["readme", "changelog", "meeting", "obsidian", "docs"])
    func aRealWorldNoteIsStableAfterOneSave(label: String) throws {
        let sample = try #require(samples[label])
        #expect(NoteMarkdownCheck.checkStable(sample, label))
    }

    @Test(arguments: ["readme", "changelog", "meeting", "obsidian", "docs"])
    func aRealWorldNoteModelSurvivesARoundTrip(label: String) throws {
        let sample = try #require(samples[label])
        #expect(NoteMarkdownCheck.checkModelRoundTrip(NoteMarkdown.parse(sample), label))
    }

    @Test(arguments: ["changelog", "meeting", "obsidian"])
    func aRealWorldNoteSavesBackExactly(label: String) throws {
        let sample = try #require(samples[label])
        #expect(NoteMarkdownCheck.checkExact(sample, label + " exact"))
    }

    @Test
    func aReadmeKeepsItsOpeningHTML() {
        let page = NoteMarkdown.parse(readme)
        #expect(page.blocks.first?.kind == .html)
    }

    @Test
    func aReadmeLoadsItsImportantCallout() {
        let page = NoteMarkdown.parse(readme)
        #expect(page.blocks.contains { $0.kind == .callout && $0.props.alert == "IMPORTANT" })
    }

    @Test
    func aReadmeLoadsItsDetailsAsAToggle() {
        let page = NoteMarkdown.parse(readme)
        #expect(page.blocks.contains { $0.kind == .toggle })
    }

    @Test
    func aReadmeLoadsItsTable() {
        let page = NoteMarkdown.parse(readme)
        #expect(page.blocks.contains { $0.kind == .table })
    }

    @Test
    func aMeetingNoteLoadsItsCalendarIcon() {
        let page = NoteMarkdown.parse(meeting)
        #expect(page.settings.icon == "🗓️")
    }

    @Test
    func aMeetingNoteLoadsItsThreeTodos() {
        let page = NoteMarkdown.parse(meeting)
        #expect(page.blocks.filter { $0.kind == .todo }.count == 3)
    }

    private func largeDocument() -> String {
        var document = ""
        while document.split(separator: "\n", omittingEmptySubsequences: false).count < 5000 {
            document += readme + "\n" + changelog + "\n" + docs + "\n"
        }
        return document
    }

    @Test
    func aLargeDocumentParsesItsBlocks() {
        let page = NoteMarkdown.parse(largeDocument())
        #expect(page.blocks.count > 500)
    }

    @Test
    func aLargeDocumentSerializesToNonemptyMarkdown() {
        let page = NoteMarkdown.parse(largeDocument())
        #expect(!NoteMarkdown.serialize(page).isEmpty)
    }
}
