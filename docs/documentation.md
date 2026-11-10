# Documentation policy

Documentation should explain Parc as it works now and help the next person make
a change safely. The project has outgrown a running account of parity work.

Write for human readers. Explain what works, why a decision matters and how to
change or check it. Omit commit SHAs, binary/compiler addresses, raw checksum
values and evidence-ID dumps. Prefer readable source links and feature names;
exact machine records belong in source manifests, Git and ignored check output.
Do not replace deleted hex strings with equally unhelpful receipt inventories.

## Size and structure

- **Hard maximum: 500 lines per Markdown guide**, including `.mdc` rules,
  READMEs, agent instructions, test guides and technical references.
- **Changelogs are exempt.** Preserve their complete history and generation;
  do not trim or reorganize them as part of documentation cleanup.
- Aim for **150–300 lines** for a focused guide and **100–200 or fewer** for
  entry points. A useful 40-line guide does not need padding.
- Remove duplication and obsolete history before considering a split. Split
  genuinely separate topics with clear names and an index link; do not create
  numbered overflow parts, archive dumps or giant lines to evade the limit.
- A new document needs a distinct reader and purpose. Prefer updating the
  existing guide and linking related material.

## Where information belongs

| Information | Authoritative home |
|---|---|
| Product introduction and install/build entry points | [README](../README.md) |
| Current capability inventory, delivery state and product scope | [Product status](parity.md) |
| Concrete unfinished work, deferrals and current handoffs | [Backlog](backlog.md) |
| Behavior, architecture, important decisions and commands | Focused subsystem guide |
| Cross-cutting agent requirements | [AGENTS.md](../AGENTS.md) |
| Collaboration mechanics | [Collaboration](collaboration.md) |
| Release history | Git, release notes and [CHANGELOG](../CHANGELOG.md) |
| Raw check output, temporary plans and diagnostics | Ignored `build/` or `work/` |

Keep one home for each fact. Link to it instead of copying it into README,
the status page, agent instructions and a subsystem guide. Existing
`docs/parity.md` is the product-status entry point for compatibility, not an
invitation to rebuild the old percentage ledger.

## Updating a feature

1. Read the current code and relevant guide. Check old pending-build and missing
   feature claims before repeating them.
2. Edit the existing behavior description in the same change as the implementation.
   Keep commands executable and links pointing to their actual owner.
3. Update the capability inventory only for a meaningful product change. Resolve
   or update its backlog item; do not add a completed-work paragraph.
4. State validation accurately: source checked, artifact published, runtime
   tested or explicitly user confirmed. Do not treat one as another.
5. Tell Josh about any newly recorded or retained gap in the same turn. Keep
   unperformed validation separate from known missing behavior.

Do not append dated implementation diaries, agent transcripts, build-by-build
receipts, old ownership tables or duplicated lists of completed requirements.
Replace superseded rules instead of layering corrections over them. History is
recoverable with `git log -- path` and `git show <commit>:path`; it does not need
another tracked archive.

## Verification and enforcement

Enable repository hooks once per clone:

```sh
git config core.hooksPath .githooks
```

Before publishing documentation:

```sh
python3 scripts/check-docs.py
python3 scripts/check-docs.py --ref HEAD
python3 -m unittest discover -s tests/Documentation -v
git diff --check
```

The default size check includes tracked and unignored new Markdown documents;
ignored build/dependency output is outside its scope. `--ref` reads a committed
Git tree. The pre-push hook validates each pushed tip, so a clean working copy
cannot hide an oversized document in the commit being published. Exactly 500
lines pass; 501 fail. Files named `CHANGELOG.md` or `CHANGELOG.markdown`
(case-insensitive, in any directory) are exempt; other old files are not.
Fix the document rather than bypassing hooks.

Also inspect changed relative links and heading anchors. The size checker does
not establish content accuracy or link correctness. When removing a heading,
update its callers or retain a useful compatibility anchor. Preserve provenance,
product requirements, explicit exclusions and meaningful validation boundaries
while removing historical narrative.
