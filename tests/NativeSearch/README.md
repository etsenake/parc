# Native search readiness

This isolated component uses the production `NativeSearchReadiness` owner and
actual pinned Chromium task-executor, weak-callback and non-reentrant
`ObserverList<TemplateURLServiceObserver>` implementations. The notification
fixture represents only `TemplateURLService::Scoper`'s observer iteration; it does
not instantiate a browser, a Profile, a search database or an autocomplete
provider. The full production `native_search.mm` is checked separately with its
real compile command.

The negative control performs the original synchronous observer → Add → observer
ordering and must abort at Chromium's actual reentrancy check. The passing path
covers readiness before load, already-loaded asynchronous delivery, coalescing,
notifications generated during catalog preparation, nested UI loop exclusion,
queued preparation canceled by shutdown/destruction, once-only completion and
client reentry. Preparation-owner destruction verifies the queue's continuation;
it does not simulate destruction inside `TemplateURLService::Add` itself.

Run using the existing matching Chromium build, with a private output directory:

```sh
python3 tests/NativeSearch/run_readiness.py \
  --parc-root /absolute/path/to/Parc \
  --chromium-source /absolute/path/to/chromium/src \
  --engine-output /absolute/path/to/chromium/src/out/Release_GN_arm64 \
  --ninja /absolute/path/to/depot_tools/ninja \
  --output /absolute/path/to/private-check-output
```

The runner reads the actual search-unit compiler flags, records exact production,
fixture and linked-library hashes, and writes logs/receipt only to the specified
private directory. It performs no GN generation, browser launch, source-profile
access or network operation. The deliberate negative control disables core dumps.
