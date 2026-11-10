# Native external-protocol confirmation


The typed upstream seam preserves the checked URL, default application name, initiating origin/document, page transition, gesture and fenced-frame state. Chrome still performs scheme/enterprise/gesture/default-application policy and actual platform launch. Remembering uses the real origin/scheme preference and its managed checkbox policy. Acceptance revalidates exact page, document, Browser, Profile, native window and sole security lease before and after release; preference observers are followed by another validation before OS launch. Navigation, detach, replacement and destruction cancel the original request.

Current Chromium adaptations use the real `InputEventActivationProtector` utility with AppKit activation/movement notifications, plus a narrow native-rectangle query/subscription on the actual PiP occlusion tracker. Opening is blocked during activation protection or PiP overlap; becoming unoccluded re-arms protection. Cancel is the default Return action. These protections do not require a surrogate Views widget. Genuine WebContentsModalDialogManager registration keeps renderer blocking, fullscreen exit and native-dialog lifetime connected.

## Verification


`dialog_unittest.mm` contains 17 Chromium-connected cases: 14 use real Browser/Profile/Tab/WebContents, modal manager, preferences and the upstream launch test delegate; three cover the genuine floating-widget occlusion tracker and activation protector. They cover cancellation, remembered policy, stale documents, navigation/detach and queued acceptance across reattachment, replacement, competing release-time reservations, preference-observer navigation and callback-driven page destruction. Only the OS effect is intercepted in controller tests. The tests begin at the checked platform-dialog boundary; they do not establish the earlier default-application lookup/network path. The protection utility cases run without the test bypass; lifecycle tests use Chromium's explicit testing switch.


## Remaining acceptance gates


ARM64 reference SHA-256: Core
`97df76204405d2046261e9f8efeb0cb84f74bf9c223b81f3567e6087b52967a8`;
main `4e452201e483b5480c0403a9ef8566e10515cdcb78828622ff9032b202e29547`.
