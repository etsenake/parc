// Copyright 2026 The Chromium Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
#ifndef CHROME_BROWSER_EXTERNAL_PROTOCOL_NATIVE_EXTERNAL_PROTOCOL_DIALOG_H_
#define CHROME_BROWSER_EXTERNAL_PROTOCOL_NATIVE_EXTERNAL_PROTOCOL_DIALOG_H_

#include <memory>
#include <optional>
#include <string>

#include "base/functional/callback.h"
#include "base/memory/weak_ptr.h"
#include "content/public/browser/weak_document_ptr.h"
#include "ui/base/page_transition_types.h"
#include "url/gurl.h"
#include "url/origin.h"
namespace content {
class WebContents;
}

// Created only at the already-policy-checked platform dialog boundary. The
// native shell presents this exact request; it must not create another URL load
// or call an OS launcher. Its once-only decision keeps Chrome's preferences,
// metrics, escaping and actual platform continuation.
class NativeExternalProtocolDialogRequest {
 public:
  NativeExternalProtocolDialogRequest(content::WebContents*,
                                      const GURL&,
                                      const std::u16string&,
                                      const std::optional<url::Origin>&,
                                      content::WeakDocumentPtr,
                                      ui::PageTransition,
                                      bool,
                                      bool);
  ~NativeExternalProtocolDialogRequest();
  NativeExternalProtocolDialogRequest(
      const NativeExternalProtocolDialogRequest&) = delete;
  NativeExternalProtocolDialogRequest& operator=(
      const NativeExternalProtocolDialogRequest&) = delete;
  const GURL url;
  const std::u16string program_name;
  const std::optional<url::Origin> initiating_origin;
  const content::WeakDocumentPtr initiator_document;
  const ui::PageTransition transition;
  const bool has_user_gesture;
  const bool is_in_fenced_frame_tree;
  bool MayRemember() const;
  std::u16string Title() const;
  std::u16string Message() const;
  std::u16string AcceptLabel() const;
  std::u16string CancelLabel() const;
  std::u16string RememberLabel() const;
  // Call after native presentation has ended. Revalidates before preferences
  // and after preference observers, immediately before the real OS launch.
  void Accept(bool remember, base::RepeatingCallback<bool()> can_authorize);
  void Cancel();

 private:
  const base::WeakPtr<content::WebContents> contents_;
  bool decided_ = false;
};
using NativeExternalProtocolDialogFactory = base::RepeatingCallback<void(
    content::WebContents*,
    std::unique_ptr<NativeExternalProtocolDialogRequest>)>;
void SetNativeExternalProtocolDialogFactory(
    content::WebContents&,
    NativeExternalProtocolDialogFactory);
#endif
