#!/usr/bin/env python3
"""P1-AD behavior lock: refreshLivePageChrome and updateNavigation skip
republishing shareable + audio into applyLivePageMetadata only when the live
fingerprint matches the last apply (shareable ids + lease identity +
audible/muted). Everyday chrome ticks still walk/probe; real shareable and
audible/mute flips still hand off. No dirty-bit early out that can miss flips.
"""
from pathlib import Path

root = Path(__file__).resolve().parents[2]
controller = (root / "Sources/ParcApp/BrowserWindowController.swift").read_text()
sidebar = (root / "Sources/ParcApp/SidebarView.swift").read_text()


def body(source, signature):
    """The declaration at `signature`, through its body's closing brace."""
    assert source.count(signature) == 1, f"{signature} not found once"
    start = source.index(signature)
    depth = 0
    for end in range(source.index("{", start), len(source)):
        depth += {"{": 1, "}": -1}.get(source[end], 0)
        if depth == 0:
            return source[start:end + 1]
    raise AssertionError(f"unterminated {signature}")


assert "shareableAudioDirty" not in controller, \
    "dirty-bit early out can miss audible/mute/shareable flips; skip must compare live fingerprint"
assert "private var lastShareableAudioFingerprint: String?" in controller, \
    "missing last-applied shareable/audio fingerprint"
assert "private var lastAppliedShareable = Set<UUID>()" in controller, \
    "missing last-applied shareable set"
assert "private var lastAppliedAudio: [UUID: SidebarTabAudio] = [:]" in controller, \
    "missing last-applied audio map"

assert "canShareThisTabInstead" in body(controller, "private func liveShareableTabs() -> Set<UUID>"), \
    "liveShareableTabs must still probe canShareThisTabInstead"

audio_body = body(controller, "private func liveTabAudio() -> [UUID: SidebarTabAudio]")
for needle in (
    "page.tabAudioState",
    "tabAudioIsAudible",
    "tabAudioIsMuted",
    "toggleTabAudioMuted",
):
    assert needle in audio_body, f"liveTabAudio no longer probes {needle}"

fp_body = body(controller, "private func shareableAudioFingerprint(shareable: Set<UUID>,")
for needle in (
    "uuidString",
    "ObjectIdentifier(entry.lease)",
    "entry.audible",
    "entry.muted",
):
    assert needle in fp_body, f"fingerprint no longer includes {needle}"

pub_body = body(controller, "private func publishedShareableAndAudio()")
assert "-> (shareable: Set<UUID>, audio: [UUID: SidebarTabAudio], changed: Bool)" in pub_body, \
    "publishedShareableAndAudio must report whether the maps changed"
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

rem_body = body(controller, "private func rememberAppliedShareableAudio(shareable: Set<UUID>,")
assert "lastShareableAudioFingerprint = shareableAudioFingerprint" in rem_body, \
    "remember must record fingerprint only after handoff"
assert "lastAppliedShareable = shareable" in rem_body and "lastAppliedAudio = audio" in rem_body, \
    "remember must cache applied maps"

live_body = body(controller, "private func refreshLivePageChrome() -> Bool")
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

nav_body = body(controller, "private func updateNavigation()")
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
