// Copyright 2026 Parc contributors.
#ifndef PARC_HARNESS_PARC_NATIVE_HOST_H_
#define PARC_HARNESS_PARC_NATIVE_HOST_H_

class Browser;

namespace parc {

// Browser/UI thread only. Registers one browser-scoped native AppKit host and
// shows it in the existing visible Chrome window. The Browser, its Profile,
// TabStripModel, WebContents and native window retain their Chrome ownership.
// Called only by the explicit native harness opt-in, after the first real tab
// has been inserted. Not a general embedding API or a Parc production shell.
void InstallNativeHost(Browser* browser);

}  // namespace parc
#endif
