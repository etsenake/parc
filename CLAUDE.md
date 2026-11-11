# Joining Parc

Read [AGENTS.md](AGENTS.md), [README.md](README.md),
[product status](docs/parity.md) and [collaboration](docs/collaboration.md).
The same working contract applies to every contributor.

Work on the user's current assignment. Read the [backlog](docs/backlog.md) for
unresolved dependencies; historical owner names are not new work assignments.
Respect the authorized checkout and delegation scope, preserve concurrent edits,
and keep shared engine inputs unchanged during a build.

Never migrate this conversation using `move_agent_to_root` or
`move_agent_to_cloned_root`. Never launch apps or browsers or take app screenshots.
Use permitted source, compiler and model checks.

Engine work stays inside the [Chromium boundary](AGENTS.md#chromium-boundary):
extension points first, then Parc-owned code. Any new or larger Chromium patch,
hook, header or BUILD edit waits for Josh's approval of that change.

Maintain existing docs in place. Markdown guides are limited to **500 lines** (changelogs are exempt);
normal guides should be 150–300 lines and entry points shorter. Do not append
progress diaries, duplicate the backlog or create history archives. Run
`python3 scripts/check-docs.py` before publication. See the
[documentation policy](docs/documentation.md) for where information belongs.
