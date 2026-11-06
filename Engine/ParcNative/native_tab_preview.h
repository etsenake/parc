// Copyright 2026 Parc contributors.
#ifndef PARC_NATIVE_NATIVE_TAB_PREVIEW_H_
#define PARC_NATIVE_NATIVE_TAB_PREVIEW_H_
class Profile;
namespace parc {
// Called by the real TabFeatures constructor before Browser attachment. Only
// an already registered native route (including its private profile) qualifies.
bool NeedsNativeTabThumbnails(Profile& profile);
}  // namespace parc
#endif
