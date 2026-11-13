// Copyright 2026 Parc contributors.
#ifndef PARC_NATIVE_NATIVE_BROWSER_WINDOW_H_
#define PARC_NATIVE_NATIVE_BROWSER_WINDOW_H_

#include <memory>

#include "base/functional/callback.h"
#include "native_window_state.h"
#include "chrome/browser/ui/browser_window.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/exclusive_access/exclusive_access_bubble_hide_callback.h"
#include "chrome/browser/ui/exclusive_access/exclusive_access_bubble_type.h"
#include "chrome/browser/ui/exclusive_access/fullscreen_tab_params.h"
#include "ui/color/color_provider_source.h"
#include "ui/gfx/geometry/rect.h"
#include "ui/gfx/geometry/size.h"

namespace ui {
class Accelerator;
}

namespace parc {
class NativeExtensionActionHost;

class NativeBrowserWindowHost {
 public:
  virtual ~NativeBrowserWindowHost() = default;

  virtual void DidAttachWindow(gfx::NativeWindow window) = 0;
  virtual void DidDetachWindow(gfx::NativeWindow window) = 0;
  virtual void DidChangeSelectedBrowser(bool selected) = 0;
  virtual void BrowserCloseApproved() = 0;
  virtual void BrowserCloseCancelled(
      BrowserWindowInterface::ClosingStatus status) = 0;
  virtual void BeginTeardown() = 0;
  virtual gfx::Rect GetWindowBounds(gfx::NativeWindow window) const = 0;
  virtual void SetWindowBounds(gfx::NativeWindow window,
                               const gfx::Rect& bounds) = 0;
  virtual void FlashWindow(gfx::NativeWindow window, bool flash) = 0;

  virtual NativeExtensionActionHost& GetExtensionActionHost() = 0;

  virtual autofill::AutofillBubbleHandler& GetAutofillBubbleHandler() = 0;
  virtual ui::AcceleratorProvider& GetAcceleratorProvider() = 0;
  virtual std::unique_ptr<FindBar> CreateFindBar() = 0;
  virtual bool DispatchExtensionActionAccelerator(
      const ui::Accelerator& accelerator) = 0;

  virtual bool IsToolbarAvailable() const = 0;
  virtual void ShowIntentPicker(
      std::vector<apps::IntentPickerAppInfo> apps,
      bool show_stay,
      bool show_remember,
      apps::IntentPickerBubbleType type,
      const std::optional<url::Origin>& initiating_origin,
      IntentPickerResponse callback) = 0;
  virtual void ShowBookmarkEditor(const GURL& url, bool already_bookmarked) = 0;
  virtual void ConfirmCloseWithDownloads(
      int count,
      DownloadCloseType type,
      base::OnceCallback<void(bool)> callback) = 0;
  virtual void ShowProfilePicker(bool from_accelerator) = 0;
  virtual std::unique_ptr<content::EyeDropper> OpenEyeDropper(
      content::RenderFrameHost* frame,
      content::EyeDropperListener* listener) = 0;
  virtual void ShowCaretBrowsingDialog() = 0;
  virtual void ShowTabSearch() = 0;
  virtual void CloseTabSearch() = 0;
  virtual void ShowIncognitoClearBrowsingDataDialog() = 0;
  virtual void ShowIncognitoHistoryDisclaimerDialog() = 0;
  virtual void HandleDragEnded() = 0;

  enum class FullscreenRequestResult { kAccepted, kRejected };
  virtual void RequestFullscreen(
      bool enter,
      FullscreenTabParams tab_params,
      base::OnceCallback<void(FullscreenRequestResult)> result) = 0;
  virtual void UpdateUIForTabFullscreen() = 0;
  virtual bool CanUserEnterFullscreen() const = 0;
  virtual bool CanUserExitFullscreen() const = 0;
};

class NativeBrowserWindow final : public BrowserWindow,
                                  public ui::ColorProviderSource {
 public:
  NativeBrowserWindow(BrowserWindowInterface& browser,
                      std::unique_ptr<NativeBrowserWindowHost> host);
  ~NativeBrowserWindow() override;
  NativeBrowserWindow(const NativeBrowserWindow&) = delete;
  NativeBrowserWindow& operator=(const NativeBrowserWindow&) = delete;
  friend std::optional<std::string> PrepareNativeWindowStateUpdate(
      BrowserWindowInterface&, ui::mojom::WindowShowState, const gfx::Rect*);

  bool AttachToNativeWindow(gfx::NativeWindow window);
  void SetSelectedForNativeWindow(bool selected);
  void NotifyActiveHostGeometryChanged();
  ui::RendererColorMap GetRendererColorMap(
      ui::ColorProviderKey::ColorMode color_mode,
      ui::ColorProviderKey::ForcedColors forced_colors) const override;

  bool IsActive() const override;
  bool IsMaximized() const override;
  bool IsMinimized() const override;
  bool IsFullscreen() const override;
  gfx::NativeWindow GetNativeWindow() const override;
  gfx::Rect GetRestoredBounds() const override;
  ui::mojom::WindowShowState GetRestoredState() const override;
  gfx::Rect GetBounds() const override;
  void Show() override;
  void Hide() override;
  bool IsVisible() const override;
  void ShowInactive() override;
  void Close() override;
  void Activate() override;
  void Deactivate() override;
  void Maximize() override;
  void Minimize() override;
  void Restore() override;
  void SetBounds(const gfx::Rect& bounds) override;
  void FlashFrame(bool flash) override;
  ui::ZOrderLevel GetZOrderLevel() const override;
  void SetZOrderLevel(ui::ZOrderLevel order) override;
  bool IsOnCurrentWorkspace() const override;
  bool IsVisibleOnScreen() const override;
  void SetTopControlsShownRatio(content::WebContents* web_contents,
                                float ratio) override;
  bool DoBrowserControlsShrinkRendererSize(
      const content::WebContents* contents) const override;
  ui::NativeTheme* GetNativeTheme() override;
  const ui::ThemeProvider* GetThemeProvider() const override;
  const ui::ColorProvider* GetColorProvider() const override;
  int GetTopControlsHeight() const override;
  void SetTopControlsGestureScrollInProgress(bool in_progress) override;
  std::vector<StatusBubble*> GetStatusBubbles() override;
  void UpdateTitleBar() override;
  void UpdateLoadingAnimations(bool is_visible) override;
  void OnActiveTabChanged(content::WebContents* old_contents,
                          content::WebContents* new_contents,
                          int index,
                          int reason) override;
  void OnTabDetached(content::WebContents* contents, bool was_active) override;
  gfx::Size GetContentsSize() const override;
  void SetContentsSize(const gfx::Size& size) override;
  autofill::AutofillBubbleHandler* GetAutofillBubbleHandler() override;
  LocationBar* GetLocationBar() const override;
  ui::AcceleratorProvider* GetAcceleratorProvider() override;
  PinnedToolbarActions* GetPinnedToolbarActions() override;
  void SetFocusToLocationBar(bool is_user_initiated) override;
  void UpdateReloadStopState(bool is_loading, bool force) override;
  void UpdateToolbar(content::WebContents* contents) override;
  bool UpdateToolbarSecurityState() override;
  void UpdateCustomTabBarVisibility(bool visible, bool animate) override;
  void ResetToolbarTabState(content::WebContents* contents) override;
  void FocusToolbar() override;
  void ToolbarSizeChanged(bool is_animating) override;
  void TabDraggingStatusChanged(bool is_dragging) override;
  void LinkOpeningFromGesture(WindowOpenDisposition disposition) override;
  void FocusAppMenu() override;
  bool IsTabStripEditable() const override;
  void DisableTabStripEditingForTesting() override;
  bool IsToolbarVisible() const override;
  bool IsToolbarShowing() const override;
  bool IsLocationBarVisible() const override;
  void ShowUpdateChromeDialog() override;
  void ShowIntentPickerBubble(
      std::vector<apps::IntentPickerAppInfo> app_info,
      bool show_stay_in_chrome,
      bool show_remember_selection,
      apps::IntentPickerBubbleType bubble_type,
      const std::optional<url::Origin>& initiating_origin,
      IntentPickerResponse callback) override;
  void ShowBookmarkBubble(const GURL& url, bool already_bookmarked) override;
  ShowTranslateBubbleResult ShowTranslateBubble(
      content::WebContents* contents,
      translate::TranslateStep step,
      const std::string& source_language,
      const std::string& target_language,
      translate::TranslateErrors error_type,
      bool is_user_gesture) override;
  DownloadBubbleUIController* GetDownloadBubbleUIController() override;
  void ConfirmBrowserCloseWithPendingDownloads(
      int download_count,
      DownloadCloseType dialog_type,
      base::OnceCallback<void(bool)> callback) override;
  void ShowAppMenu() override;
  void PreHandleDragUpdate(const content::DropData& drop_data,
                           const gfx::PointF& point) override;
  void PreHandleDragExit() override;
  void HandleDragEnded() override;
  content::KeyboardEventProcessingResult PreHandleKeyboardEvent(
      const input::NativeWebKeyboardEvent& event) override;
  bool HandleKeyboardEvent(const input::NativeWebKeyboardEvent& event) override;
  std::unique_ptr<FindBar> CreateFindBar() override;
  web_modal::WebContentsModalDialogHost* GetWebContentsModalDialogHost()
      override;
  web_modal::WebContentsModalDialogHost* GetWebContentsModalDialogHostFor(
      content::WebContents* web_contents) override;
  void ShowAvatarBubbleFromAvatarButton(bool is_source_accelerator) override;
  void ShowHatsDialog(
      const std::string& site_id,
      const std::optional<std::string>& hats_histogram_name,
      const std::optional<uint64_t> hats_survey_ukm_id,
      base::OnceClosure success_callback,
      base::OnceClosure failure_callback,
      const SurveyBitsData& product_specific_bits_data,
      const SurveyStringData& product_specific_string_data) override;
  ExclusiveAccessContext* GetExclusiveAccessContext() override;
  std::string GetWorkspace() const override;
  bool IsVisibleOnAllWorkspaces() const override;
  void ShowEmojiPanel() override;
  std::unique_ptr<content::EyeDropper> OpenEyeDropper(
      content::RenderFrameHost* frame,
      content::EyeDropperListener* listener) override;
  void ShowCaretBrowsingDialog() override;
  void CreateTabSearchBubble() override;
  void CloseTabSearchBubble() override;
  void ShowIncognitoClearBrowsingDataDialog() override;
  void ShowIncognitoHistoryDisclaimerDialog() override;
  bool IsUnframedModeEnabled() const override;
  bool GetCanResize() override;
  ui::mojom::WindowShowState GetWindowShowState() const override;
  void ShowChromeLabs() override;
  BrowserView* AsBrowserView() override;

 protected:
  void DeleteBrowserWindow() override;
  ui::ColorProviderKey GetColorProviderKey() const override;

 private:
  class Impl;
  std::unique_ptr<Impl> impl_;
};

}
#endif
