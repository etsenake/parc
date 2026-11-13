#ifndef CHROME_BROWSER_UI_AUTOFILL_PARC_BUBBLE_PRESENTATION_H_
#define CHROME_BROWSER_UI_AUTOFILL_PARC_BUBBLE_PRESENTATION_H_

#include <utility>

#include "base/functional/bind.h"
#include "base/functional/callback.h"
#include "base/memory/weak_ptr.h"
#include "components/autofill/core/browser/payments/payments_autofill_client.h"

namespace content {
class WebContents;
}

namespace autofill {
class AutofillBubbleBase;
class AutofillBubbleControllerBase;

class ParcBubblePresentation {
 public:
  static bool SupportsCardOffer(
      content::WebContents* contents,
      const payments::PaymentsAutofillClient::SaveCreditCardOptions& options,
      bool upload);

  static void Adopt(AutofillBubbleControllerBase& controller,
                    AutofillBubbleBase* view,
                    base::OnceClosure shown,
                    base::OnceClosure unavailable);

  template <typename Controller, typename Shown, typename Unavailable>
  static void Adopt(AutofillBubbleControllerBase& controller,
                    AutofillBubbleBase* view,
                    base::WeakPtr<Controller> lifetime,
                    Shown shown,
                    Unavailable unavailable) {
    if (!view) {
      if (lifetime) {
        (lifetime.get()->*unavailable)();
      }
      return;
    }
    Adopt(controller, view, base::BindOnce(shown, lifetime),
          base::BindOnce(unavailable, lifetime));
  }

  template <typename Controller, typename Unavailable>
  static void Adopt(AutofillBubbleControllerBase& controller,
                    AutofillBubbleBase* view,
                    base::WeakPtr<Controller> lifetime,
                    Unavailable unavailable) {
    if (!view) {
      unavailable(lifetime);
      return;
    }
    Adopt(controller, view, {}, base::BindOnce(unavailable, lifetime));
  }
};
}

#endif
