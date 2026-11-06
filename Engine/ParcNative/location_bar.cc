// Copyright 2026 Parc contributors.
#include "location_bar.h"

#include "base/check.h"
#include "base/check_op.h"
#include "base/feature_list.h"
#include "base/time/time.h"
#include "chrome/browser/ui/browser_command_controller.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/omnibox/chrome_omnibox_client.h"
#include "chrome/browser/ui/omnibox/omnibox_controller.h"
#include "chrome/browser/ui/omnibox/omnibox_view.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "chrome/browser/ui/views/bubble_anchor_util_views.h"
#include "components/history_embeddings/core/history_embeddings_features.h"
#include "components/omnibox/browser/location_bar_model.h"
#include "content/public/browser/browser_thread.h"
#include "ui/base/base_window.h"

namespace parc {
namespace {

CommandUpdater* RequireCommandUpdater(BrowserWindowInterface& browser) {
  auto* commands = chrome::BrowserCommandController::From(&browser);
  //
  // Bind the real owning Browser's updater rather than preserve that hazard.
  CHECK(commands);
  return commands;
}

//
// OmniboxView's inherited SetUserText/RevertAll/TextChanged implementations:
// these mutate the genuine edit model even though there is no text widget.
class NativeOmniboxView final : public OmniboxView {
 public:
  explicit NativeOmniboxView(OmniboxController* controller)
      : OmniboxView(controller) {}
  ~NativeOmniboxView() override = default;

  void Update() override {}
  std::u16string GetText() const override { return {}; }
  void SetWindowTextAndCaretPos(const std::u16string&,
                                size_t,
                                bool,
                                bool) override {}
  void SetCaretPos(size_t) override {}
  void SetAdditionalText(const std::u16string&) override {}
  void EnterKeywordModeForDefaultSearchProvider() override {}
  bool IsSelectAll() const override { return false; }
  gfx::Range GetSelectionBounds() const override { return gfx::Range(0); }
  void SetSelectionBounds(gfx::Range) override {}
  bool HasSelection() const override { return false; }
  void SelectAll(bool) override {}
  void UpdatePopup() override {}
  void SetFocus(bool) override {}
  // Also false in the recovered142 view; Parc has no AI control.
  bool AimButtonVisible() const override { return false; }
  void ApplyCaretVisibility() override {}
  void OnTemporaryTextMaybeChanged(const std::u16string&,
                                   const AutocompleteMatch&,
                                   bool,
                                   bool) override {}
  void OnInlineAutocompleteTextMaybeChanged(const std::u16string&,
                                            const std::u16string&) override {}
  void OnInlineAutocompleteTextCleared() override {}
  void OnRevertTemporaryText(const std::u16string&,
                             const AutocompleteMatch&) override {}
  void OnBeforePossibleChange() override {}
  bool OnAfterPossibleChange(bool) override { return false; }

 protected:
  int GetOmniboxTextLength() const override { return 0; }
  void EmphasizeURLComponents() override {}
  void SetEmphasis(bool, const gfx::Range&) override {}
  void UpdateSchemeStyle(const gfx::Range&) override {}
};

}  // namespace

NativeLocationBar::NativeLocationBar(BrowserWindowInterface& browser)
    : LocationBar(RequireCommandUpdater(browser)), browser_(browser) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  CHECK(browser_->GetProfile());
  CHECK(LocationBarModel::From(&browser));
  // Use upstream's supported startup feature policy, not a testing setter or
  // replacement autocomplete model. Upstream includes a history-embedding
  // provider even with its feature off; its Start() returns before querying the
  // service when that feature is off.
  // This bounded guard is not whole-engine AI exclusion evidence.
  // Explicit override is required: without one, Chrome may use the separate
  // LaunchedHistoryEmbeddings country/locale rollout despite this flag's
  // disabled default (history_embeddings_utils.cc).
  CHECK(base::FeatureList::GetStateIfOverridden(
            history_embeddings::kHistoryEmbeddings)
            .has_value());
  CHECK(!base::FeatureList::IsEnabled(history_embeddings::kHistoryEmbeddings))
      << "Parc startup must disable HistoryEmbeddings";
  //
  // Upstream156 moved controller ownership out of OmniboxView; retain the same
  // model chain with current typed APIs, not the old binary layout.
  controller_ = std::make_unique<OmniboxController>(
      std::make_unique<ChromeOmniboxClient>(this, &browser, GetProfile()),
      base::Milliseconds(1500));
  view_ = std::make_unique<NativeOmniboxView>(controller_.get());
}

NativeLocationBar::~NativeLocationBar() {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
}

//
void NativeLocationBar::FocusLocation(bool, bool) {}
void NativeLocationBar::FocusSearch() {}
void NativeLocationBar::UpdateContentSettingsIcons() {}
void NativeLocationBar::SaveStateToContents(content::WebContents*) {}
void NativeLocationBar::Revert() {}
void NativeLocationBar::OnChanged() {}
void NativeLocationBar::UpdateWithoutTabRestore() {}

OmniboxView* NativeLocationBar::GetOmniboxView() {
  return view_.get();
}
OmniboxController* NativeLocationBar::GetOmniboxController() {
  return controller_.get();
}
content::WebContents* NativeLocationBar::GetWebContents() {
  //
  // frontmost-window lookup can substitute for this profile-bound identity.
  return browser_->GetTabStripModel()->GetActiveWebContents();
}
LocationBarModel* NativeLocationBar::GetLocationBarModel() {
  return LocationBarModel::From(&*browser_);
}
BrowserWindowInterface* NativeLocationBar::GetBrowser() {
  return &*browser_;
}
Profile* NativeLocationBar::GetProfile() {
  return browser_->GetProfile();
}
bool NativeLocationBar::IsFullscreen() const {
  auto* window = browser_->GetWindow();
  return window && window->IsFullscreen();
}
bool NativeLocationBar::IsEditingOrEmpty() const {
  return view_->IsEditingOrEmpty();
}
bool NativeLocationBar::IsInitialized() const {
  return view_ && controller_;
}

// Chromium156 visual-interface additions. There is no native location-bar
// widget, popup, chip, anchor, painted security icon, or per-tab text state.
// Permission presentation and the accessible command bar belong to the shell;
// these absence values must not be interpreted as a permission decision.
OmniboxPopupView* NativeLocationBar::GetOmniboxPopupView() {
  return nullptr;
}
bool NativeLocationBar::ShouldCloseOmniboxPopup(ui::MouseEvent*) {
  return false;
}
std::optional<bubble_anchor_util::AnchorConfiguration>
NativeLocationBar::GetChipAnchor() {
  return std::nullopt;
}
ChipController* NativeLocationBar::GetChipController() {
  return nullptr;
}
ui::TrackedElement* NativeLocationBar::GetAnchorOrNull() {
  return nullptr;
}
void NativeLocationBar::AnnounceAlert(const std::u16string&) {}
void NativeLocationBar::UpdateFocusBehavior(bool) {}
bool NativeLocationBar::IsVisible() const {
  return false;
}
bool NativeLocationBar::IsDrawn() const {
  return false;
}
bool NativeLocationBar::IsMouseHovered() const {
  return false;
}
bool NativeLocationBar::IsFocusWithin() const {
  return false;
}
void NativeLocationBar::InvalidateLayout() {}
gfx::Rect NativeLocationBar::Bounds() const {
  return {};
}
gfx::Rect NativeLocationBar::BoundsInScreen() const {
  return {};
}
gfx::Size NativeLocationBar::MinimumSize() const {
  return {};
}
gfx::Size NativeLocationBar::PreferredSize() const {
  return {};
}
void NativeLocationBar::Update(content::WebContents*) {}
void NativeLocationBar::ResetTabState(content::WebContents*) {}
bool NativeLocationBar::HasSecurityStateChanged() {
  return false;
}

LocationBarTesting* NativeLocationBar::GetLocationBarForTesting() {
  return this;
}
bool NativeLocationBar::TestContentSettingImagePressed(size_t) {
  return false;
}
bool NativeLocationBar::IsContentSettingBubbleShowing(size_t) {
  return false;
}
views::Widget* NativeLocationBar::GetContentSettingBubbleWidget(size_t) {
  return nullptr;
}
bool NativeLocationBar::IsContentSettingImageVisible(size_t) {
  return false;
}

}  // namespace parc
