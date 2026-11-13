#ifndef PARC_NATIVE_ADDRESS_EDITOR_H_
#define PARC_NATIVE_ADDRESS_EDITOR_H_

#include <memory>

namespace autofill {
class AutofillBubbleBase;
class EditAddressProfileDialogController;
class EditAddressProfileView;
}
namespace content {
class WebContents;
}
namespace parc {
std::unique_ptr<autofill::AutofillBubbleBase> ShowNativeAddressEditor(
    content::WebContents* contents,
    autofill::EditAddressProfileDialogController* controller,
    autofill::EditAddressProfileView* dialog);
}

#endif
