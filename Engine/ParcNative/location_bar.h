// Copyright 2026 Parc contributors.
#ifndef PARC_NATIVE_LOCATION_BAR_H_
#define PARC_NATIVE_LOCATION_BAR_H_

#include <memory>
#include <optional>

#include "base/memory/raw_ref.h"
#include "chrome/browser/ui/location_bar/location_bar.h"

namespace parc {

class NativeLocationBar final : public LocationBar, public LocationBarTesting {
 public:
  explicit NativeLocationBar(BrowserWindowInterface& browser);
  ~NativeLocationBar() override;
  NativeLocationBar(const NativeLocationBar&) = delete;
  NativeLocationBar& operator=(const NativeLocationBar&) = delete;

  void FocusLocation(bool is_user_initiated,
                     bool clear_focus_if_failed) override;
  void FocusSearch() override;
  void UpdateFocusBehavior(bool toolbar_visible) override;
  void UpdateContentSettingsIcons() override;
  void SaveStateToContents(content::WebContents* contents) override;
  void Revert() override;
  OmniboxView* GetOmniboxView() override;
  OmniboxPopupView* GetOmniboxPopupView() override;
  OmniboxController* GetOmniboxController() override;
  bool ShouldCloseOmniboxPopup(ui::MouseEvent* event) override;
  content::WebContents* GetWebContents() override;
  LocationBarModel* GetLocationBarModel() override;
  std::optional<bubble_anchor_util::AnchorConfiguration> GetChipAnchor()
      override;
  ChipController* GetChipController() override;
  void AnnounceAlert(const std::u16string& announcement) override;
  void OnChanged() override;
  void UpdateWithoutTabRestore() override;
  ui::TrackedElement* GetAnchorOrNull() override;
  BrowserWindowInterface* GetBrowser() override;
  Profile* GetProfile() override;
  bool IsInitialized() const override;
  bool IsVisible() const override;
  bool IsDrawn() const override;
  bool IsFullscreen() const override;
  bool IsEditingOrEmpty() const override;
  bool IsMouseHovered() const override;
  bool IsFocusWithin() const override;
  void InvalidateLayout() override;
  gfx::Rect Bounds() const override;
  gfx::Rect BoundsInScreen() const override;
  gfx::Size MinimumSize() const override;
  gfx::Size PreferredSize() const override;
  void Update(content::WebContents* contents) override;
  void ResetTabState(content::WebContents* contents) override;
  bool HasSecurityStateChanged() override;
  LocationBarTesting* GetLocationBarForTesting() override;

  bool TestContentSettingImagePressed(size_t index) override;
  bool IsContentSettingBubbleShowing(size_t index) override;
  views::Widget* GetContentSettingBubbleWidget(size_t index) override;
  bool IsContentSettingImageVisible(size_t index) override;

 private:
  const raw_ref<BrowserWindowInterface> browser_;
  // Chromium156 OmniboxView holds a non-owning controller pointer and clears
  // its model's view in its destructor. Reverse member destruction is required.
  std::unique_ptr<OmniboxController> controller_;
  std::unique_ptr<OmniboxView> view_;
};

}  // namespace parc
#endif  // PARC_NATIVE_LOCATION_BAR_H_
