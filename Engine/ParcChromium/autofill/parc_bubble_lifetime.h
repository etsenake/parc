#ifndef CHROME_BROWSER_UI_AUTOFILL_PARC_BUBBLE_LIFETIME_H_
#define CHROME_BROWSER_UI_AUTOFILL_PARC_BUBBLE_LIFETIME_H_

#include <utility>

#include "base/functional/bind.h"
#include "base/functional/callback_helpers.h"
#include "base/memory/weak_ptr.h"

namespace autofill {
template <typename Owner>
base::ScopedClosureRunner MakeParcScopedFlag(base::WeakPtr<Owner> owner,
                                            bool Owner::*member) {
  const bool previous = std::exchange(owner.get()->*member, true);
  return base::ScopedClosureRunner(base::BindOnce(
      [](base::WeakPtr<Owner> owner, bool Owner::*member, bool previous) {
        if (owner) {
          owner.get()->*member = previous;
        }
      },
      owner, member, previous));
}
}

#endif
