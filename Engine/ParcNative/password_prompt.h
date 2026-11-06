// Copyright 2026 Parc contributors.
//
#ifndef PARC_NATIVE_PASSWORD_PROMPT_H_
#define PARC_NATIVE_PASSWORD_PROMPT_H_

namespace content {
class WebContents;
}

namespace parc {
bool UsesNativePasswordPrompt(content::WebContents* contents);
// Handles the real pending save/update state. No password is copied into
// AppKit or the shell. Returns false if no viable native request was created.
bool ShowNativePasswordPrompt(content::WebContents* contents, bool user_action);
void HideNativePasswordPrompt(content::WebContents* contents);
// Includes deferred attachment, so BubbleManager reserves the exact request
// before the native sheet acknowledges actual presentation.
bool HasNativePasswordPrompt(content::WebContents* contents);
bool IsNativePasswordPromptHovered(content::WebContents* contents);
}  // namespace parc
#endif
