#!/usr/bin/env python3
"""P1-AD behavior lock: refreshLivePageChrome and updateNavigation skip
republishing shareable + audio into applyLivePageMetadata only when the live
fingerprint matches the last apply (shareable ids + lease identity +
audible/muted). Everyday chrome ticks still walk/probe; real shareable and
audible/mute flips still hand off. No dirty-bit early out that can miss flips.
"""
from pathlib import Path
import re

root = Path(__file__).resolve().parents[2]
controller = (root / "Sources/ParcApp/BrowserWindowController.swift").read_text()
sidebar = (root / "Sources/ParcApp/SidebarView.swift").read_text()

assert "shareableAudioDirty" not in controller, \
    "dirty-bit early out can miss audible/mute/shareable flips; skip must compare live fingerprint"
assert "private var lastShareableAudioFingerprint: String?" in controller, \
    "missing last-applied shareable/audio fingerprint"
assert "private var lastAppliedShareable = Set<UUID>()" in controller, \
    "missing last-applied shareable set"
assert "private var lastAppliedAudio: [UUID: SidebarTabAudio] = [:]" in controller, \
    "missing last-applied audio map"

build = re.search(
    r"private func liveShareableTabs\(\) -> Set<UUID> \{(?P<body>.*?)\n    \}\n\n    /// Live tab-audio map",
    controller, re.S)
assert build, "liveShareableTabs not found"
assert "canShareThisTabInstead" in build.group("body"), \
    "liveShareableTabs must still probe canShareThisTabInstead"

audio_build = re.search(
    r"private func liveTabAudio\(\) -> \[UUID: SidebarTabAudio\] \{(?P<body>.*?)\n    \}\n\n    /// Stable fingerprint of shareable",
    controller, re.S)
assert audio_build, "liveTabAudio not found"
audio_body = audio_build.group("body")
for needle in (
    "page.tabAudioState",
    "tabAudioIsAudible",
    "tabAudioIsMuted",
    "toggleTabAudioMuted",
):
    assert needle in audio_body, f"liveTabAudio no longer probes {needle}"

fp = re.search(
    r"private func shareableAudioFingerprint\(shareable: Set<UUID>,\s*"
    r"audio: \[UUID: SidebarTabAudio\]\) -> String \{(?P<body>.*?)\n    \}\n\n    /// Walk live shareable",
    controller, re.S)
assert fp, "shareableAudioFingerprint not found"
fp_body = fp.group("body")
for needle in (
    "uuidString",
    "ObjectIdentifier(entry.lease)",
    "entry.audible",
    "entry.muted",
):
    assert needle in fp_body, f"fingerprint no longer includes {needle}"

published = re.search(
    r"private func publishedShareableAndAudio\(\)\s*"
    r"-> \(shareable: Set<UUID>, audio: \[UUID: SidebarTabAudio\], changed: Bool\) \{(?P<body>.*?)\n    \}\n\n    /// Record maps only after",
    controller, re.S)
assert published, "publishedShareableAndAudio not found"
pub_body = published.group("body")
assert "liveShareableTabs()" in pub_body, "must still build live shareable before skip"
assert "liveTabAudio()" in pub_body, "must still build live audio before skip"
assert "shareableAudioFingerprint(shareable: shareable, audio: audio)" in pub_body, \
    "must fingerprint live maps before skip"
assert "if fingerprint == lastShareableAudioFingerprint" in pub_body, \
    "identical fingerprint must skip republish"
assert "return (lastAppliedShareable, lastAppliedAudio, false)" in pub_body, \
    "identical fingerprint must reuse last-applied maps with changed=false"
assert "lastShareableAudioFingerprint = fingerprint" not in pub_body, \
    "publish must not cache before rows receive the maps"
assert "lastAppliedShareable = shareable" not in pub_body, \
    "publish must not cache applied maps before handoff"
assert pub_body.index("liveShareableTabs()") < pub_body.index(
    "if fingerprint == lastShareableAudioFingerprint"), \
    "live walk must precede the identical-fingerprint skip"
assert pub_body.index("liveTabAudio()") < pub_body.index(
    "if fingerprint == lastShareableAudioFingerprint"), \
    "live audio probe must precede the identical-fingerprint skip"

remember = re.search(
    r"private func rememberAppliedShareableAudio\(shareable: Set<UUID>,\s*"
    r"audio: \[UUID: SidebarTabAudio\]\) \{(?P<body>.*?)\n    \}\n\n    /// Stable fingerprint of the capture-indicator",
    controller, re.S)
assert remember, "rememberAppliedShareableAudio not found"
rem_body = remember.group("body")
assert "lastShareableAudioFingerprint = shareableAudioFingerprint" in rem_body, \
    "remember must record fingerprint only after handoff"
assert "lastAppliedShareable = shareable" in rem_body and "lastAppliedAudio = audio" in rem_body, \
    "remember must cache applied maps"

live = re.search(
    r"private func refreshLivePageChrome\(\) -> Bool \{(?P<body>.*?)\n    \}\n\n",
    controller, re.S)
assert live, "refreshLivePageChrome not found"
live_body = live.group("body")
assert "publishedShareableAndAudio()" in live_body, \
    "refreshLivePageChrome must publish through the fingerprint gate"
assert "applyShareableAudio: published.changed" in live_body, \
    "live path must skip shareable/audio handoff when fingerprint matches"
assert "rememberAppliedShareableAudio(shareable: published.shareable, audio: published.audio)" in live_body, \
    "live path must remember only after successful apply"
assert live_body.index("applyLivePageMetadata") < live_body.index(
    "rememberAppliedShareableAudio"), \
    "fingerprint commit must follow successful apply, not precede it"
assert "browsers.compactMap" not in live_body, \
    "live path must not inline a second shareable rebuild"
assert "tabAudioState" not in live_body, \
    "live path must not inline a second audio rebuild"

nav = re.search(
    r"private func updateNavigation\(\) \{(?P<body>.*?)\n    \}\n\n    /// the per-pane scrim loaders",
    controller, re.S)
assert nav, "updateNavigation not found"
nav_body = nav.group("body")
assert "publishedShareableAndAudio()" in nav_body, \
    "updateNavigation must publish through the same fingerprint gate"
assert "applyShareableAudio: published.changed" in nav_body, \
    "updateNavigation must skip shareable/audio handoff when fingerprint matches"
assert "rememberAppliedShareableAudio(shareable: published.shareable, audio: published.audio)" in nav_body, \
    "updateNavigation must remember after apply or reconstruct"
assert "sidebar.render(" in nav_body, \
    "full-render fallback must still receive shareable/audio maps"
assert nav_body.index("sidebar.render(") < nav_body.index(
    "rememberAppliedShareableAudio"), \
    "fingerprint commit must follow apply/render, not precede it"
assert "shareable: published.shareable" in nav_body and "audio: published.audio" in nav_body, \
    "changed or reconstruct paths must still pass published maps"

assert "applyShareableAudio: Bool = true" in sidebar, \
    "SidebarView.applyLivePageMetadata must accept applyShareableAudio"
assert "if applyShareableAudio { tabAudio = audio }" in sidebar, \
    "identical ticks must not replace tabAudio"
assert "if applyShareableAudio {\n                row.shareable = shareable.contains(tab.id)\n                row.audio = tabAudio[tab.id]\n            }" in sidebar, \
    "identical ticks must not republish row shareable/audio"
assert "let effectiveAudio = applyShareableAudio ? audio : tabAudio" in sidebar, \
    "speaker-host gate must use retained audio when handoff is skipped"
assert sidebar.count("row.shareable = shareable.contains(row.tabID)") >= 2, \
    "title/split-title edit early returns must still hand off shareable/audio flips"

# Sibling gates from origin/main must remain across rebase.
assert "lastCapturePresentationFingerprint" in controller, \
    "capture-indicators skip gate missing after rebase"
assert "lastExtensionControlsSignature" in controller, \
    "extension-controls skip gate missing after rebase"
assert "lastPushedWebsiteTheme" in controller, \
    "website-theme skip gate missing after rebase"

print("ShareableAudioSkip: live walk + fingerprint compare only; "
      "real shareable/audio flips still hand off; sibling skip gates kept")
