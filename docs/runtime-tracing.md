# Runtime tracing

Use an instrumented reproduction when a visible delay cannot be explained by
source inspection, especially when a page is loaded but still looks blank,
switching tabs pauses, or focus changes when a picture appears. A recording
shows the symptom; a trace places navigation, drawing and display delivery on
one timeline. Neither alone proves that a finished frame reached the window.

This workflow is for the agent investigating the issue and the Codex agent
operating the browser. It also supports the user recording the trace themselves.
Keep raw recordings and analysis in ignored output, not in this guide or Git.

## Permission and executor

Before any app interaction, describe the exact reproduction, the app/window,
temporary tabs, local trace capture and any screenshots or video needed. Ask
one plain question and wait for approval, for example:

> May I use your running Parc window to record a few switches between already
> loaded tabs, save the trace locally and capture the visible transition? I will
> close only my temporary tabs and release control before analyzing the file.

An explicit request to perform that capture, or approval already given for the
same scope, is sufficient; do not ask repeatedly. A general request to fix a bug
or release Parc is not permission for computer use. Request new approval before
expanding the scope to restarting the app, another profile, or other apps.
Engine apply/build, packaging and installation retain their separate approval
boundaries in [AGENTS.md](../AGENTS.md).

Codex is this workspace's computer-use executor. A Codex agent with the native
computer-use tools performs the approved capture directly. An agent using
another provider delegates only the capture to Codex through the available
cross-provider delegation tool. Verify provider/tool availability first; a
model name alone does not prove access. Do not create a new top-level thread or
worktree for a capture. If Codex access is unavailable, report that limitation
and prepare a user-operated recording rather than substituting another driver.

The delegation brief must include the user's approval and its scope, target
app/version, starting tab, exact actions, hypotheses, trace configuration,
output directory and cleanup. Give one agent ownership of the computer. The
capture agent returns the trace path, timestamps, visual observations, relevant
app identity and cleanup result. The parent owns analysis and any source fix.

## Prepare before taking control

Read the relevant production path and choose one question the capture can
answer. For tab switching, separate an already loaded tab from a newly created
or not-yet-loaded restored tab. For focus-related delays, record whether Parc
is focused, unfocused but visible, covered, minimized or hidden; those are
different states. Do not combine unrelated changes into one reproduction.

Record the installed app's version/build and executable identity separately
from the checkout commit. A source fix in Git is not evidence about the running
binary. Verify the executable path/version of the process actually being tested.
Do not build or install a different engine merely to collect an initial trace.

Prepare an ignored directory such as `build/runtime-tracing/tab-switch/` for
the configuration, action timestamps, screenshots, raw trace and analysis.
Traces can include URLs and page titles. Keep them local and out of commits;
external uploading needs separate authorization. Record the recorder's privacy
filter setting because filtering can remove arguments needed for attribution.

The [page-display configuration](../scripts/tracing/page-display.textproto)
captures browser tasks, navigation, rendering, compositing and display delivery.
Its event buffer is 256 MiB with a separate metadata buffer and a 90-second
limit. Stop after the useful reproduction; broad debugging categories add
overhead, so trace timing is not an uninstrumented performance benchmark.

From the repository root, encode the configuration with the existing compiler
in the pinned engine workspace. These commands do not build or launch Parc:

```sh
export PARC_TRACE_SRC=/path/to/engine/chromium/src
mkdir -p build/runtime-tracing/tab-switch
"$PARC_TRACE_SRC/out/ParcDistribution_GN_arm64/protoc" \
  --proto_path="$PARC_TRACE_SRC/third_party/perfetto" \
  --encode=perfetto.protos.TraceConfig \
  protos/perfetto/config/trace_config.proto \
  < scripts/tracing/page-display.textproto \
  > build/runtime-tracing/tab-switch/config.pb
python3 - <<'PY'
import base64
from pathlib import Path
from urllib.parse import urlencode
out = Path('build/runtime-tracing/tab-switch')
encoded = base64.b64encode((out / 'config.pb').read_bytes()).decode('ascii')
url = 'chrome://traces/recorder?' + urlencode({'trace_config': encoded})
(out / 'recorder-url.txt').write_text(url + '\n')
PY
```

Use the actual engine workspace/compiler location. If the compiler is absent,
configure the recorder through its interface or use an existing verified
configuration; this does not authorize an engine build. Keep the readable
configuration alongside the trace so the selection can be reproduced.

## Capture, then release control

Use the current computer-use tool instructions. A web preview that cannot open
`chrome://` or operate Parc's native tab controls cannot reproduce this path;
after the supported fallback, use Codex's native app controls. Do not replace
them with shell-generated clicks, another browser, or a different test profile.

Open a temporary Parc tab with the generated recorder address. Verify that the
configuration loaded and the recorder is idle. Start with **Start Tracing** and
check that it reports recording. Warm up the target tabs before the measured
switches, record their order, and switch between them using the reported entry
point. A sidebar click and the keyboard switcher may take different shell paths.

Record the start/end time of each automation action as an interval; tool latency
is not browser latency. Capture the visible result and note when the old page,
blank backing and incoming picture are observed. A screenshot after an action
only bounds the transition time; do not invent an exact duration between
samples. Use video or suitable frame-by-frame instrumentation when that gap
matters. Do not claim an accessibility text tree proves that pixels appeared.

Keep input deliberate. Hovering, clicking, focusing, resizing or opening the
recorder can trigger drawing and change the bug. Log those interventions and
capture the quiet interval first. Fetch fresh accessibility state before using
element references, and respect user activity instead of competing for control.

Return to the recorder, select **Stop Tracing**, and wait for its downloaded
`.gz` trace. Verify the download completed and copy that exact file into the
capture directory. Close only the temporary tabs created for this task and
restore the original tab when practical. Immediately end the computer-use
phase with its completion summary. Tell the user control is released before
doing lengthy trace parsing, code inspection or documentation work.

If the user stops computer use, stop immediately and follow the tool's handoff
instructions. Do not retry through another agent, browser or input mechanism to
get around the stop. Renewed user permission and tool availability are separate:
if a later authorized attempt still reports stopped, report that exact failure.
Do not invent an Allow button or promise another chat message will reset it.
Offer the prepared recorder address for the user to operate; analyze the saved
file offline. A failed capture setup is not evidence of a Parc defect.

## Analyze the whole picture path

Use the pinned workspace's Perfetto Trace Processor, the local tool that reads
Chromium's trace format. Its launcher obtains and checks its official binary
when needed. Inspect its help before relying on options. For example:

```sh
"$PARC_TRACE_SRC/third_party/perfetto/tools/trace_processor" query \
  build/runtime-tracing/tab-switch/capture.gz \
  'SELECT name, COUNT(*) AS n FROM slice GROUP BY name ORDER BY n DESC LIMIT 30'
"$PARC_TRACE_SRC/third_party/perfetto/tools/trace_processor" export sqlite \
  -o build/runtime-tracing/tab-switch/capture.sqlite \
  build/runtime-tracing/tab-switch/capture.gz
```

Confirm the expected browser, renderer and graphics processes are present and
the recording covers the actions. Inspect data-loss/error statistics before
interpreting an absent event. Attribute events to their process, thread, page
and display connection; several tabs can paint concurrently.

Follow the chain from selection or navigation to page visibility and layout,
renderer frame production, browser composition, graphics-process presentation,
native connection delivery and observed pixels. For tab switching, also locate
the outgoing-page hold and its release. If that boundary has no trace event,
state what cannot be measured directly and consider focused instrumentation;
do not label a generic graphics event as the shell's hold-release callback.

Useful pinned-engine landmarks include `NavigationTotal`, `firstContentfulPaint`,
`PipelineReporter`, `CommitPresentedFrameToCA`, `DisplayClient`, and
`DisplayCALayerTree::GotCAContextFrame`. Check their producers in the current
engine source before interpreting them. First paint means content was produced;
presentation feedback can succeed while the app's local display connection is
missing. Connection metadata can be intentionally deduplicated, and some events
only describe a context change, so their absence alone does not mean no drawing.

Use trace clock metadata to align external observations; wall-clock timestamps
and monotonic trace timestamps are not interchangeable. Keep raw timestamps
and derivations in the capture directory. Distinguish a measured interval from
an upper/lower bound and a source-based explanation from a reproduced cause.

## Turn evidence into a fix

Explain what happened in plain language, with the visible symptom first. State
which stage was late, what the trace rules out, and what remains uncertain.
Do not generalize one successful local-file capture to every website, restored
tab, window, split or focus state. Audit shared paths in source and choose
additional captures only for unresolved questions.

Fix the demonstrated mechanism and add a meaningful regression check where
possible. Run it against the preceding code as well as the correction; a test
that only repeats the new implementation is not evidence of the old failure.
Use the permitted compiler/model checks for changed inputs. A before/after
runtime comparison requires the matching built binary and authorization for
any build/install/runtime steps not already covered.

Keep one small local receipt with app/source identity, configuration, action
order, trace/visual paths, analysis commands, findings and cleanup. Update the
owning feature guide only for enduring behavior or a concrete unresolved gap.
Do not turn trace receipts into a permanent progress ledger. See
[page compositing](page-compositing.md) and
[display regression checks](../tests/PaneCompositorDisplay/README.md).
