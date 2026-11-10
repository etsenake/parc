# Native display handoffs

Run `python3 tests/PaneCompositorDisplay/run.py` on macOS with Xcode command-line
tools. The check compiles eight handoff methods extracted from the production
pane compositor, plus its real AppKit display view. It uses real CALayers, an
inert frame producer and a controlled presentation callback queue. It does not
start a browser or exercise the GPU process.

The producer models two pinned Chromium contracts: a remote picture updates
through an existing connection, and unchanged connection metadata is suppressed
for ten seconds. Expiration does not schedule a message; another frame must
arrive. The display-tree adapter models native child-layer ownership and removal.

The checks cover a fresh page on a reused display, metadata arriving while
drawing is suspended, a newer connection superseding a deferred one, an old
presentation callback after a handoff, an ancestor hiding the view before
presentation, and a capture lock keeping drawing alive across hide/show.
The previous picture remains concealed until the current presentation succeeds.

To test an earlier implementation, save its `pane_compositor.mm` in ignored
output and pass `--source path/to/pane_compositor.mm`. `--case reuse` exercises
the disconnected-tree regression; `--case suspended` exercises the discarded
connection update independently. Both fail against the preceding production
methods and pass with the correction. The real view's ancestor visibility and
resize behavior is covered by [NativePageHost](../NativePageHost/README.md).

The script writes its generated method include and executable under ignored
`build/tests/pane-compositor-display`. It links AppKit and QuartzCore only.
See [page compositing](../../docs/page-compositing.md) for ownership and behavior.
