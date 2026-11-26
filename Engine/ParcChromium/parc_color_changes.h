#ifndef UI_COLOR_PARC_COLOR_CHANGES_H_
#define UI_COLOR_PARC_COLOR_CHANGES_H_

#include "base/component_export.h"

namespace ui {
class ColorProviderManager;
}

namespace parc_hooks {
enum class ColorChange { kInvalidate, kRetire };
using ColorChangeNotifier = void (*)(ui::ColorProviderManager&, ColorChange);
COMPONENT_EXPORT(COLOR) void SetColorChangeNotifier(ColorChangeNotifier notifier);
COMPONENT_EXPORT(COLOR) void NotifyColorChange(ui::ColorProviderManager& manager,
                                               ColorChange change);
}

#endif
