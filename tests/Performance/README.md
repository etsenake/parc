# Performance benchmarks

This folder measures Parc the way Ardia measures itself, so the two compare row for
row. The cross-browser harness runs Parc, Ardia, Helium and Google Chrome (and Dia)
on one Mac with the same pages, profile state, window size and run counts. It
interleaves them run by run so every browser sees the same machine. The harness,
its native probes and the test page are ported from Ardia's rig with their method
unchanged; [NOTICE](NOTICE) records the source and licence.

Running any of it launches browsers. That needs explicit authorization for the task,
a quiet Mac and no engine build in progress ([collaboration](../../docs/collaboration.md#checks-and-publication)).
The unit tests here are offline and safe to run at any time:

```sh
python3 -m unittest discover -s tests/Performance -p 'test_*.py'
```

## What it measures

| Row | How |
|---|---|
| Cold launch → page painted (link) | `open -a <copy> <url>` with the browser closed, to that page's first contentful paint |
| Cold launch → window on screen | the process's first on-screen window of at least 300×200 with alpha above zero |
| Cold launch → restored tab painted | `open -a <copy>`, to the restored test page's first contentful paint |
| New tab → first paint | `Target.createTarget(url)` to first contentful paint, median of 5 per session |
| Tab switch → shown | `Target.activateTarget` to visibility plus two animation frames, median of 16 among 20 tabs |
| New window → first paint | `Target.createTarget(url, newWindow)` to first contentful paint, only if a window opened |
| Memory at 1, 10 and 20 tabs, and back to 1 | physical footprint summed over every process of the browser |
| Idle CPU and wakeups at 1 and 20 tabs | resource-usage deltas over 60 s, plus a settled window 2 minutes after the last load |
| Download, on disk | the release disk image's size and the bundle's size (context only) |

Each figure is the median with min–max and n over runs. A row is a win only when
the ranges don't overlap; overlapping ranges are noise.

## Comparing with Ardia

Ardia's published numbers come from its owner's Mac. Numbers from another machine
don't compare directly, so the comparison is always made by running an Ardia copy
in the same run as Parc. `report --rivals-from <bench.json>` merges stored rivals
only when the machine model, chip and harness revision match, as in Ardia's harness.
The harness revision, rows, page bytes and bench.json schema match Ardia's, so a
bench.json from either project reads the same way.

## Running it

Copies live under `build/perf/xbench/apps`, never in `/Applications`:
`parc/Parc.app`, `ardia/Ardia.app`, `helium/Helium.app` and
`chrome/Google Chrome.app`. Make the Parc copy from a released Parc:

```sh
python3 tests/Performance/xbench.py prepare-parc --app parc=<path to a released Parc.app>
python3 tests/Performance/xbench.py check --out build/perf/xbench/out
python3 tests/Performance/xbench.py run --out build/perf/xbench/out
python3 tests/Performance/xbench.py report --out build/perf/xbench/out
python3 tests/Performance/xbench.py clean --out build/perf/xbench/out
```

`run` is resumable: finished items stay in `samples.jsonl` and a rerun continues.
By default every item waits until the owner is away (screen locked, or no input
for ten minutes) and is thrown away the moment input comes. `--gate off` runs on a
Mac in use. `--help` lists every flag; `--browsers`, `--rows`, `--rounds` and
`--idle` narrow a run. A full run of four browsers takes roughly one and a half
to two hours.

## How each browser runs

Every instance starts from its own clone of a template profile, made once per
browser by one launch that opens the test page, settles 90 s and quits. HOME and
`CFFIXED_USER_HOME` point into the run folder, so nothing reaches the real
`~/Library`. Chromium browsers get their own user data folder, the remote debugging
port, a mock keychain and the same window size and position. Chrome and Helium run
as shipped and come to the front like they do for users.

Parc runs as a clone with the bundle identifier `org.parc.Browser.bench`, signed ad
hoc without the hardened runtime. The separate identifier keeps links, AppleScript
and preference writes away from the installed Parc, because macOS's preferences
service ignores the redirected HOME. Ad hoc signing can make launch rows differ
slightly from the notarized release. Parc is launched with:

```text
--parc-profile <run>/profile --parc-test-instance --parc-perf-marks=<run>/perf-marks.jsonl
--remote-debugging-port=9461 --remote-allow-origins=* --use-mock-keychain
--mute-audio --disable-backgrounding-occluded-windows --window-size=1280,800 --window-position=40,80
```

`--use-mock-keychain` keeps the engine off the login keychain entirely; Parc Safe
Storage is never read or created. `--parc-test-instance` treats onboarding as
complete and turns off update checks, What's New, pending import resumes and the
quit warning for that run, and places the first window at the given frame. Without
these switches Parc behaves exactly as before. The harness waits for a Parc window
and a page target before creating tabs, and quits through `Browser.close`, then the
quit probe, then SIGTERM.

Parc's remote debugging server, `Target.createTarget`, `activateTarget`,
`closeTarget` and `Browser.getWindowForTarget` use Chromium's own handlers; created
pages are adopted into Parc's sidebar and selected. `Target.createBrowserContext` is
not supported, and the occluded-window switch does not yet reach Parc's own
occlusion handling.

## Parc's timing marks

`--parc-perf-marks=<file>` appends one JSON line per mark, `{"mark", "t", ...}` with
`t` in epoch milliseconds. The marks are written only when the switch is present:

| Mark | When |
|---|---|
| `main` | Swift `main` starts |
| `engine-started` | the engine reports ready |
| `window-on-screen` | the first browser window with its content becomes visible |
| `keydown` | every key down the application sees, with `keyCode` and `modifierFlags` |
| `command-bar-typeable` | after ⌘T or ⌘L, once the window has displayed a focused command bar |
| `tab-select` | a tab selection request, with `tab` and `source` (`click`, `shortcut` or `script`) |
| `tab-shown` | that tab's page view is attached and visible in its pane |

The cross-browser rows don't use them; they time Parc-only journeys from real input.

## Native tools

`native.py` builds each tool on demand into `build/perf-tools`, cached by source
hash. `app_copy.py` makes the signed APFS clone the injected tools need.

| Tool | What it does |
|---|---|
| `parcperf` | per-process resource usage and footprint, on-screen windows, display state, quit, window waits, input idle time, and real key, scroll and mouse events posted to one process |
| `xbench_probe` | the harness's away-and-focus probe |
| `parcsample` | injected main-thread sampler from before `main` (`PARC_SAMPLE_MS`) |
| `parcframes` | injected frame rig: display-link ticks and main-thread run-loop busy time |
| `parctabs` | injected in-process key, mouse and menu posting with event timing |
| `parcmark` | injected key log (`PARC_BENCH_KEYLOG`) |

The injected tools write into `PARC_BENCH_DIR`. Ardia's React Native counters,
JS-thread rows and UI-manager commit timing have no Parc counterpart.
