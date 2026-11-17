# Native search checks

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

The shortcut fixture checks the production rule for when a command bar pick
teaches Chromium's shortcuts provider, with Chromium's real URL and registry
code: 2xx, 401 and 407 responses count; other codes, missing headers, uncommitted
loads and subframes don't; and a load that ends on the network's search page,
which the intranet redirect detector reports, counts only when it stays on the
requested site.

The catalog check compiles the production site catalog with the system compiler
and no Chromium. Every site has its own GUID and keyword and searches over HTTPS,
and a hand-added engine is never mistaken for a catalog site. It checks which
engines on a catalog keyword count as the user's own and which block a repair
(policy, built-in and hand-added engines block it; extension keywords and inactive
learned shortcuts, used or not, don't). A catalog site going with at most one
engine is a removal; a catalog site going while several engines are removed, as
Reset settings does, is a reset; engines going without a catalog site, a skipped
site and its later repair record nothing. `scripts/test.sh`
runs it; on its own:

```sh
xcrun clang++ -std=c++20 -Wall -Wextra -Werror tests/NativeSearch/CatalogTests.cc \
  -o build/tests/native-search-catalog && build/tests/native-search-catalog
```

Run the readiness and shortcut fixtures using the existing matching Chromium
build, with a private output directory:

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
