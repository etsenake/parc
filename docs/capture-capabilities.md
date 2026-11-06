# Capture and recording capability contract

Parc produces page screenshots. Its camera, microphone and sharing indicators
describe live website streams. Existing OS recordings belong to the Library's
separately owned media-discovery scope, whose implementation remains CAP23.
None of those capabilities establishes a standalone browser video recorder.

CAP22 reconciles the original CAP-06 requirement, “Establish a real shipped
recording producer, if present.” The later fixed row's wording had presumed a
establishes the distinct owners below; it does not establish a shipped standalone
recording entry, recording session, video encoder or video-output transaction.
Consequently CAP22 closes the capability investigation without adding an
unsupported recorder, recording command or permission prompt. Its fixed ID and
the family's denominator remain unchanged. This conclusion is not a proof that
uninspected dynamic code or another version could never contain such a feature.

## Reference evidence

`4e452201e483b5480c0403a9ef8566e10515cdcb78828622ff9032b202e29547`.
Existing contracts were located with `components.py`; `arctypes.py`, `arcidx.py`
and `arcfn.py` resolved the remaining questions. No new decompilation or
other-version trace was needed. Negative keyword searches alone are not the
basis for this contract.

| Surface | Recovered owner and values | Capability established |
|---|---|---|
| Capture commands | The retained complete MainMenu inventory has 219 non-separator records. File records 263, 914 and 1242 target `capturePage:`, `capturePrettyScreenshot:` and `captureFullPage:`. Record 263's search aliases are Capture, Screenshot, Snapshot and Cut Out. The programmatic hidden-command and 92-case main-action inventory is reconciled in [keyboard navigation](keyboard-navigation.md#complete-command-inventory-reconciliation--kb03). | Screenshot entry. There is no standalone recording entry in this recovered inventory. |

The filesystem media source is positively identified. Source-folder resolver
`com.apple.metadata:kMDItemIsScreenCapture` attribute. Movie helper
`com.apple.metadata:kMDItemWhereFroms`, and URL type conformance to `UTType.movie`.
created it or that it is certainly an OS screen recording. CAP23 owns this
discovery/permission/consumer implementation; CAP22 does not credit its delivery.

The remaining recording-named candidates have separate diagnostic ownership:

- MainMenu records 276 and 75 are **Help → Troubleshooting → Record Trace**
  Chromium diagnostic trace path, not the screenshot/session owner.
- `onToggleRecordingWebContentSnapshotJourney` is case 50 of the internal
  This establishes a developer diagnostic entry, not a user recording command
  or a movie-output contract. Its internal snapshot encoding is not attributed.
  reducer actions with store name, description, time, reducer duration and
  state-change flag. `startRecordingImmediately` belongs to
  replay recorder is `Sentry.SentryReplayRecording`. Neither provides a local
  capture feature, and the telemetry exclusion remains in force.

The earlier bounded Core method audit and Record Trace dispatch evidence are
retained in `work/native-capture-element-targeting-completion/EVIDENCE.md`.
The fresh field/menu/annotated-function receipts and audited Parc source hashes
are under `work/capture-coordination/cap22/`. These are recovered observations

## Production ownership and permissions

`PageCaptureController.Mode` and `SavedCapture.Kind` contain region, viewport,
full-page and Portrait image paths. The native surface/protocol capture produces
PNG, `CaptureLibraryStore` validates PNG before committing an immutable revision,
and the capture Save sheet offers PNG. Existing screenshot lifetimes and exact
pixels remain owned by the [page capture contract](page-capture.md).

`PCNativeCaptureState` snapshots Chromium's genuine
`MediaStreamCaptureIndicator` state for the original WebContents, primary
document and window. It captures exact current-stream Stop callbacks; the
window menu offers Stop sharing/camera/microphone only when that callback exists.
These controls do not start a standalone recorder or promise a saved file.
Website capture retains the existing native permission/source-picker path.

External files belong to CAP23's [Library discovery contract](capture-library.md),
including actual file-access outcomes and original-URL actions. Files are not
converted into saved screenshot revisions or falsely attributed to a browser
recording session. Discovery does not warrant requesting Screen Recording
permission on behalf of a recorder that Parc does not provide.

No production source change was needed for this reconciliation. No recording
UI, encoder, new engine API or permission request was added. The delivery checks
are the retained evidence/source audit, document/link/diff validation and
independent review. No compiler rerun, functional browser test, recording
experiment, real-profile mutation or runtime acceptance claim accompanies it.
