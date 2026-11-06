// A registered security widget can be invisible when AddSecurityDialog
// notifies. Match its actual native parent chain; never infer frontmost
// Browser/Profile.
#ifndef PARC_NATIVE_EXTENSION_SECURITY_CONTEXT_H_
#define PARC_NATIVE_EXTENSION_SECURITY_CONTEXT_H_
#import <AppKit/AppKit.h>

#include "ui/views/widget/widget.h"
namespace parc {
inline bool SecurityWidgetBelongsToWindow(const views::Widget* widget,
                                          NSWindow* window) {
  if (!window) {
    return false;
  }
  for (auto* current = widget; current; current = current->parent()) {
    NSWindow* native = current->GetNativeWindow().GetNativeNSWindow();
    for (NSWindow* parent = native; parent;
         parent = parent.parentWindow ?: parent.sheetParent) {
      if (parent == window) {
        return true;
      }
    }
  }
  return false;
}
}  // namespace parc
#endif
