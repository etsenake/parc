#ifndef CONTENT_APP_SHIM_REMOTE_COCOA_PARC_COCOA_INPUT_DIAGNOSTICS_H_
#define CONTENT_APP_SHIM_REMOTE_COCOA_PARC_COCOA_INPUT_DIAGNOSTICS_H_

#import <AppKit/AppKit.h>

#include <stdint.h>

#include "base/command_line.h"
#include "base/logging.h"

namespace {

inline bool ParcInputDiagnosticsEnabled() {
  return base::CommandLine::InitializedForCurrentProcess() &&
         base::CommandLine::ForCurrentProcess()->HasSwitch(
             "parc-input-diagnostics");
}

inline void ParcTraceMouse(NSView* view,
                    NSEvent* event,
                    const char* phase,
                    bool hit_self = false,
                    bool open_mouse_down = false) {
  if (!ParcInputDiagnosticsEnabled() ||
      (event.type != NSEventTypeLeftMouseDown &&
       event.type != NSEventTypeLeftMouseUp)) {
    return;
  }
  NSWindow* window = view.window;
  LOG(ERROR) << "[ParcInput] phase=" << phase << " event=" << event.eventNumber
             << " time_us=" << static_cast<int64_t>(event.timestamp * 1000000)
             << " type=" << static_cast<int>(event.type)
             << " window=" << (window ? window.windowNumber : -1)
             << " native_hidden=" << view.isHiddenOrHasHiddenAncestor
             << " hit_self=" << hit_self
             << " open_mouse_down=" << open_mouse_down;
}

}

#endif
