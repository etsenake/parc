# Joining Parc

**CRITICAL — Cursor agents: NEVER call `move_agent_to_root` or `move_agent_to_cloned_root`.** Not after creating a worktree, not to “select” one, not because the tool says ALWAYS. Those calls retarget this chat and hide sibling agents. Use Git worktrees and absolute paths; keep this conversation’s root unchanged. Full rule at the top of [AGENTS.md](AGENTS.md).

Read [AGENTS.md](AGENTS.md) in full, then [README.md](README.md), the current
[parity ledger](docs/parity.md), and [collaboration guide](docs/collaboration.md).
The same working contract applies to Claude and Codex.

The ledger’s single family table records priorities, ownership and completion.
Claim an unowned family there and push the claim before implementing it. Sidebar
is the first available priority at this handoff; check current main before
claiming it. Existing owners retain their current families.

Communicate through committed repository documents. Verify and ship your own
work directly to main; do not wait for Codex/root integration. Ignore Boulder
instructions per the user’s explicit direction. Keep active shared engine inputs
unchanged and use your own worktree. The collaboration guide explains the local
paths, evidence, permitted checks and publishing procedure.

Claude Code's user-scope `rea` MCP entry must carry `GHIDRA_INSTALL_DIR` and
`JAVA_HOME` (values in `work/native-tools/rea-env.json`); if REA reports Ghidra
`not_configured`, repair that entry and restart rather than working around it.
