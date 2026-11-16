// Copyright 2026 Parc contributors.
#ifndef PARC_NATIVE_CONSTRAINED_DIALOG_H_
#define PARC_NATIVE_CONSTRAINED_DIALOG_H_

#include "ui/gfx/native_ui_types.h"

namespace content {
class WebContents;
}
namespace views {
class DialogDelegate;
class Widget;
class WidgetDelegate;
}

namespace parc {
views::Widget* PresentNativeWebModal(views::WidgetDelegate* dialog,
                                     content::WebContents* contents);
views::Widget* CreateNativeBrowserModal(views::DialogDelegate* dialog,
                                        gfx::NativeWindow parent);
}

#endif
