// Copyright 2026 Parc contributors.
#include "downloads.h"
#include "parc/native/native_internal_urls.h"

#include <algorithm>
#include <utility>

#include "base/check.h"
#include "base/functional/bind.h"
#include "base/functional/callback_helpers.h"
#include "base/strings/strcat.h"
#include "base/strings/string_number_conversions.h"
#include "base/strings/utf_string_conversions.h"
#include "base/task/single_thread_task_runner.h"
#include "chrome/browser/browser_process.h"
#include "chrome/browser/download/chrome_download_manager_delegate.h"
#include "chrome/browser/download/download_commands.h"
#include "chrome/browser/download/download_core_service.h"
#include "chrome/browser/download/download_core_service_factory.h"
#include "chrome/browser/download/download_item_model.h"
#include "chrome/browser/download/download_item_warning_data.h"
#include "chrome/browser/download/download_prefs.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/ui/download/download_bubble_row_view_info.h"
#include "chrome/browser/ui/download/download_bubble_security_view_info.h"
#include "chrome/common/pref_names.h"
#include "chrome/common/url_constants.h"
#include "chrome/common/webui_url_constants.h"
#include "chrome/grit/generated_resources.h"
#include "components/download/public/common/download_url_parameters.h"
#include "components/enterprise/buildflags/buildflags.h"
#include "components/google/core/common/google_util.h"
#include "components/prefs/pref_service.h"
#include "components/safe_browsing/buildflags.h"
#include "content/public/browser/browser_thread.h"
#include "content/public/browser/download_item_utils.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/web_contents.h"
#include "net/base/url_util.h"
#include "net/base/registry_controlled_domains/registry_controlled_domain.h"
#include "net/traffic_annotation/network_traffic_annotation.h"
#include "ui/base/l10n/l10n_util.h"
#include "url/gurl.h"

#if BUILDFLAG(SAFE_BROWSING_DOWNLOAD_PROTECTION)
#include "chrome/browser/safe_browsing/download_protection/download_protection_service.h"
#include "chrome/browser/safe_browsing/download_protection/download_protection_util.h"
#include "chrome/browser/safe_browsing/advanced_protection_status_manager.h"
#include "chrome/browser/safe_browsing/advanced_protection_status_manager_factory.h"
#include "chrome/browser/safe_browsing/safe_browsing_service.h"
#endif
#if BUILDFLAG(ENTERPRISE_CONTENT_ANALYSIS)
#include "chrome/browser/enterprise/connectors/analysis/content_analysis_downloads_delegate.h"
#include "chrome/browser/enterprise/connectors/common.h"
#include "chrome/browser/enterprise/connectors/connectors_service.h"
#endif

namespace parc {
namespace {
const char kDownloadsKey = 0;

// Chrome's download bubble skips CRX/webstore installs
// (`IsExtensionDownload`). CWS "Add to Chrome" can also land as a prompted
// `.crx` file whose mime is still `application/x-chrome-extension`; Chrome's
// helper then returns false because TARGET_DISPOSITION_PROMPT. Those are
// Site Control Center tiles, not Library downloads.
bool IsExtensionInstallTransfer(download::DownloadItem& item) {
  if (DownloadItemModel(&item).IsExtensionDownload()) {
    return true;
  }
  if (item.GetMimeType() == "application/x-chrome-extension" ||
      item.GetOriginalMimeType() == "application/x-chrome-extension") {
    return true;
  }
  return item.GetTargetFilePath().MatchesExtension(FILE_PATH_LITERAL(".crx")) ||
         item.GetFullPath().MatchesExtension(FILE_PATH_LITERAL(".crx"));
}

#if BUILDFLAG(SAFE_BROWSING_DOWNLOAD_PROTECTION)
safe_browsing::DownloadProtectionService* ProtectionService() {
  auto* service = g_browser_process->safe_browsing_service();
  return service ? service->download_protection_service() : nullptr;
}
#endif

// These are the same targets derived by DownloadCommands/DownloadUIModel and
// DownloadProtectionService::ShowDetailsForDownload. Return a value to the
// exact owning shell instead of GetBrowser(), which creates a Chrome window.
GURL ReviewHelpURL(DownloadUIModel& model, DownloadCommands::Command command) {
  auto locale_url = [](const char* value) {
    return google_util::AppendGoogleLocaleParam(
        GURL(value), g_browser_process->GetApplicationLocale());
  };
  switch (command) {
    case DownloadCommands::LEARN_MORE_INTERRUPTED:
      return DownloadCommands(model.GetWeakPtr())
          .GetLearnMoreURLForInterruptedDownload();
    case DownloadCommands::LEARN_MORE_INSECURE_DOWNLOAD:
      return GURL(chrome::kInsecureDownloadBlockingLearnMoreUrl);
    case DownloadCommands::LEARN_MORE_DOWNLOAD_BLOCKED:
      return locale_url(chrome::kDownloadBlockedLearnMoreURL);
    case DownloadCommands::LEARN_MORE_SCANNING:
#if BUILDFLAG(SAFE_BROWSING_DOWNLOAD_PROTECTION)
      if (safe_browsing::AdvancedProtectionStatusManagerFactory::GetForProfile(
              model.profile())->IsUnderAdvancedProtection() &&
          model.GetDangerType() == download::DOWNLOAD_DANGER_TYPE_UNCOMMON_CONTENT)
        return locale_url(chrome::kAdvancedProtectionDownloadLearnMoreURL);
#endif
      return net::AppendQueryParameter(
          locale_url(chrome::kDownloadScanningLearnMoreURL), "ctx",
          base::NumberToString(static_cast<int>(model.GetDangerType())));
    case DownloadCommands::OPEN_SAFE_BROWSING_SETTING:
      return GURL(base::StrCat({chrome::kChromeUISettingsURL,
                               chrome::kSafeBrowsingEnhancedProtectionSubPage}));
    default:
      return GURL();
  }
}

#if BUILDFLAG(ENTERPRISE_CONTENT_ANALYSIS)
std::unique_ptr<enterprise_connectors::ContentAnalysisDownloadsDelegate>
EnterpriseDelegate(download::DownloadItem& item, base::OnceClosure keep,
                   base::OnceClosure discard) {
  using namespace enterprise_connectors;
  auto* profile = Profile::FromBrowserContext(
      content::DownloadItemUtils::GetBrowserContext(&item));
  if (!profile || !ShouldPromptReviewForDownload(profile, &item)) return nullptr;
  const auto danger = item.GetDangerType();
  const char* tag = danger == download::DOWNLOAD_DANGER_TYPE_SENSITIVE_CONTENT_WARNING ||
                            danger == download::DOWNLOAD_DANGER_TYPE_SENSITIVE_CONTENT_BLOCK
                        ? kDlpTag : kMalwareTag;
  auto* service = ConnectorsServiceFactory::GetForBrowserContext(profile);
  const auto filename = item.GetFileNameToReportUser().LossyDisplayName();
  return std::make_unique<ContentAnalysisDownloadsDelegate>(
      filename,
      service->GetCustomMessage(AnalysisConnector::FILE_DOWNLOADED, tag).value_or(u""),
      service->GetLearnMoreUrl(AnalysisConnector::FILE_DOWNLOADED, tag).value_or(GURL()),
      service->GetBypassJustificationRequired(AnalysisConnector::FILE_DOWNLOADED, tag),
      std::move(keep), std::move(discard), &item,
      GetDownloadsCustomRuleMessage(&item, danger).value_or(
          ContentAnalysisResponse::Result::TriggeredRule::CustomRuleMessage()),
      l10n_util::GetStringFUTF16(
          IDS_DEEP_SCANNING_DIALOG_DOWNLOADS_SENSITIVE_DATA, filename));
}
#endif
}  // namespace

NativeDownloadPreferencesSnapshot ReadNativeDownloadPreferences(
    Profile& profile,
    const DownloadPrefs& preferences) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  return {preferences.DownloadPath(), preferences.PromptForDownload(),
          preferences.IsDownloadPathManaged(),
          profile.GetPrefs()->IsManagedPreference(prefs::kPromptForDownload)};
}

bool SetNativeDownloadDirectory(Profile& profile,
                                DownloadPrefs& preferences,
                                const base::FilePath& directory) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  if (profile.IsOffTheRecord() || directory.empty() ||
      !directory.IsAbsolute() || directory.ReferencesParent() ||
      preferences.IsDownloadPathManaged()) {
    return false;
  }
  auto weak_profile = profile.GetWeakPtr();
  // This is Chromium's setter, including its matching SaveFilePath update.
  // Target writability/reservation remains the actual download pipeline's job.
  preferences.SetDownloadPath(directory);
  return weak_profile && !preferences.IsDownloadPathManaged() &&
         preferences.DownloadPath() == directory;
}

bool SetNativeDownloadPrompt(Profile& profile, bool prompt) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  auto* values = profile.GetPrefs();
  if (profile.IsOffTheRecord() ||
      values->IsManagedPreference(prefs::kPromptForDownload) ||
      values->IsManagedPreference(prefs::kDownloadDefaultDirectory)) {
    return false;
  }
  auto weak_profile = profile.GetWeakPtr();
  values->SetBoolean(prefs::kPromptForDownload, prompt);
  return weak_profile &&
         !values->IsManagedPreference(prefs::kPromptForDownload) &&
         !values->IsManagedPreference(prefs::kDownloadDefaultDirectory) &&
         values->GetBoolean(prefs::kPromptForDownload) == prompt;
}

NativeDownloads& NativeDownloads::Install(Profile& profile, Update update,
                                           Created created) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  if (auto* existing = From(profile)) {
    return *existing;
  }
  auto service = std::make_unique<NativeDownloads>(
      *profile.GetDownloadManager(), profile.GetPath(), std::move(update),
      std::move(created));
  auto& result = *service;
  profile.SetUserData(&kDownloadsKey, std::move(service));
  return result;
}

NativeDownloads* NativeDownloads::From(Profile& profile) {
  return static_cast<NativeDownloads*>(profile.GetUserData(&kDownloadsKey));
}

NativeDownloads::NativeDownloads(content::DownloadManager& manager,
                                 base::FilePath path,
                                 Update update, Created created)
    : manager_(&manager),
      profile_path_(std::move(path)),
      update_(std::move(update)),
      created_(std::move(created)) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  CHECK(update_);
  manager_->AddObserver(this);
  content::DownloadManager::DownloadVector items;
  manager_->GetAllDownloads(&items);
  for (const auto& item : items) {
    ObserveCreated(item, false);
  }
}

NativeDownloads::~NativeDownloads() {
  Shutdown();
}

void NativeDownloads::Shutdown() {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  weak_factory_.InvalidateWeakPtrs();
  auto waiters = std::move(refresh_waiters_);
  for (auto& waiter : waiters) {
    base::SingleThreadTaskRunner::GetCurrentDefault()->PostNonNestableTask(
        FROM_HERE, base::BindOnce(std::move(waiter), false));
  }
  for (auto& [id, item] : items_) {
    item->RemoveObserver(this);
  }
  items_.clear();
  item_identities_.clear();
  if (manager_) {
    manager_->RemoveObserver(this);
    manager_ = nullptr;
  }
  update_.Reset();
  created_.Reset();
}

NativeDownloadSnapshot NativeDownloads::Snapshot(
    download::DownloadItem& item, bool include_controls) const {
  NativeDownloadSnapshot result;
  result.profile_path = profile_path_;
  result.guid = item.GetGuid();
  const auto identity = item_identities_.find(result.guid);
  if (identity != item_identities_.end()) result.item_identity = identity->second.ToString();
  if (!item.GetStartTime().is_null()) result.started_at = item.GetStartTime().InSecondsFSinceUnixEpoch();
  result.file_missing = item.GetFileExternallyRemoved();
  result.open_when_complete = item.GetOpenWhenComplete();
  result.path = item.GetTargetFilePath();
  result.name = item.GetFileNameToReportUser().value();
  const GURL source = PublicInternalURL(item.GetOriginalUrl());
  result.url = source.spec();
  result.source_domain = net::registry_controlled_domains::GetDomainAndRegistry(
      source, net::registry_controlled_domains::INCLUDE_PRIVATE_REGISTRIES);
  if (result.source_domain.empty()) result.source_domain = source.host();
  result.mime_type = item.GetMimeType();
  result.state = item.GetState();
  result.interrupt_reason = static_cast<int>(item.GetLastReason());
  result.received = item.GetReceivedBytes();
  result.total = item.GetTotalBytes();
  result.paused = item.IsPaused();
  result.available = manager_ != nullptr;
  result.requires_review = item.IsDangerous() || item.IsInsecure();
  // The dying-item observer path may copy terminal values, but must not add
  // model/security observers to an item whose destruction has begun.
  if (!include_controls) return result;
  base::TimeDelta remaining;
  if (item.TimeRemaining(&remaining) && remaining.is_positive())
    result.time_remaining_seconds = remaining.InSecondsF();
  const bool progressing = result.state == download::DownloadItem::IN_PROGRESS;
  // Pause/resume in TARGET_PENDING has not acquired a real transfer. Unlike
  // an asynchronous retry loop, expose unavailable until the manager updates.
  const bool transfer_ready = !item.GetFullPath().empty();
  result.can_pause = result.available && progressing && !result.paused &&
                     transfer_ready && !result.requires_review;
  result.can_resume = result.available && item.CanResume() &&
                      (!progressing || transfer_ready) &&
                      !result.requires_review;
  result.can_cancel =
      result.available &&
      (progressing || result.state == download::DownloadItem::INTERRUPTED);
  DownloadBubbleRowViewInfo row(DownloadItemModel::Wrap(
      &item, std::make_unique<DownloadUIModel::BubbleStatusTextBuilder>()));
  DownloadCommands commands(row.model()->GetWeakPtr());
  result.status_text = row.model()->GetStatusText();
  result.can_pause &= commands.IsCommandEnabled(DownloadCommands::PAUSE);
  result.can_resume &= commands.IsCommandEnabled(DownloadCommands::RESUME);
  result.can_cancel &= commands.IsCommandEnabled(DownloadCommands::CANCEL);
  result.can_retry = result.available && !result.requires_review &&
                     row.primary_button_command() == DownloadCommands::RETRY &&
                     commands.IsCommandEnabled(DownloadCommands::RETRY);
  result.can_review = result.available && Review(item.GetGuid()).has_value();
  const bool safe = result.available && !result.requires_review;
  const bool complete = result.state == download::DownloadItem::COMPLETE;
  result.can_open = safe && complete && !result.file_missing &&
      commands.IsCommandEnabled(DownloadCommands::OPEN_WHEN_COMPLETE);
  result.can_reveal = safe && complete && !result.file_missing &&
      commands.IsCommandEnabled(DownloadCommands::SHOW_IN_FOLDER);
  result.can_copy_file = result.can_open && !result.path.empty();
  result.can_toggle_open = safe && progressing &&
      commands.IsCommandEnabled(DownloadCommands::OPEN_WHEN_COMPLETE);
  result.can_remove = safe && !progressing;
  return result;
}

void NativeDownloads::Publish(NativeDownloadSnapshot value) {
  // Another item observer can spin a nestable loop while UpdateObservers still
  // forbids item destruction. Shell delivery must wait for that frame to
  // unwind.
  base::SingleThreadTaskRunner::GetCurrentDefault()->PostNonNestableTask(
      FROM_HERE, base::BindOnce(
                     [](base::WeakPtr<NativeDownloads> self,
                        NativeDownloadSnapshot snapshot) {
                       if (!self || !self->update_) {
                         return;
                       }
                       // Copy the callback and touch no service state after
                       // delivery.
                       auto update = self->update_;
                       update.Run(std::move(snapshot));
                     },
                     weak_factory_.GetWeakPtr(), std::move(value)));
}

void NativeDownloads::OnDownloadCreated(content::DownloadManager* manager,
                                        download::DownloadItem* item) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  CHECK_EQ(manager_, manager);
  ObserveCreated(item, true);
}

void NativeDownloads::ObserveCreated(download::DownloadItem* item,
                                      bool genuine_creation) {
  if (!item || item->GetGuid().empty()) {
    return;
  }
  if (IsExtensionInstallTransfer(*item)) {
    return;
  }
  auto [it, inserted] = items_.emplace(item->GetGuid(), item);
  CHECK(inserted || it->second == item);
  if (inserted) {
    item_identities_.emplace(item->GetGuid(), base::UnguessableToken::Create());
    item->AddObserver(this);
  }
  auto snapshot = Snapshot(*item);
  Publish(snapshot);
  if (!inserted || !genuine_creation || !created_) return;
  //
  // onDownloadsInitialized replay. This carrier belongs to the initiating
  // document: restored/imported history attaches no WebContents
  // (download_manager_impl.cc AttachInfo(nullptr)), and a tab that has
  // navigated since starting the download cannot supply it.
  auto* contents = content::DownloadItemUtils::GetWebContents(item);
  auto* frame = contents ? contents->GetPrimaryMainFrame() : nullptr;
  if (!frame || !frame->IsRenderFrameLive()) return;
  base::SingleThreadTaskRunner::GetCurrentDefault()->PostNonNestableTask(
      FROM_HERE, base::BindOnce(
          [](base::WeakPtr<NativeDownloads> self, NativeDownloadSnapshot value,
             content::WeakDocumentPtr document) {
            if (!self || !self->created_ || !document.AsRenderFrameHostIfValid() ||
                !self->CanPresentArrival(value.guid, value.item_identity)) return;
            auto created = self->created_;
            created.Run(std::move(value), std::move(document));
          }, weak_factory_.GetWeakPtr(), std::move(snapshot),
          frame->GetWeakDocumentPtr()));
}

bool NativeDownloads::CanPresentArrival(const std::string& guid,
                                         const std::string& identity) const {
  //
  // 3/4) leave a pending hover query in place, so state is not consulted.
  auto found = item_identities_.find(guid);
  return manager_ && Find(guid) && found != item_identities_.end() &&
      found->second.ToString() == identity;
}

void NativeDownloads::OnDownloadUpdated(download::DownloadItem* item) {
  auto it = items_.find(item->GetGuid());
  if (it != items_.end() && it->second == item) {
    if (IsExtensionInstallTransfer(*item)) {
      Remove(*item, false);
      return;
    }
    Publish(Snapshot(*item));
  }
}

void NativeDownloads::OnDownloadRemoved(download::DownloadItem* item) {
  Remove(*item, false);
}

void NativeDownloads::Remove(download::DownloadItem& value, bool destroying) {
  auto* item = &value;
  auto it = items_.find(item->GetGuid());
  if (it == items_.end() || it->second != item) {
    return;
  }
  auto snapshot = Snapshot(*item, !destroying);
  snapshot.removed = true;
  snapshot.available = snapshot.can_pause = snapshot.can_resume =
      snapshot.can_cancel = snapshot.can_review = snapshot.can_retry = false;
  snapshot.can_open = snapshot.can_reveal = snapshot.can_remove =
      snapshot.can_copy_file = snapshot.can_toggle_open = false;
  snapshot.item_identity.clear();
  item_identities_.erase(item->GetGuid());
  items_.erase(it);
  item->RemoveObserver(this);
  Publish(std::move(snapshot));
}

void NativeDownloads::OnDownloadDestroyed(download::DownloadItem* item) {
  Remove(*item, true);
}

void NativeDownloads::ManagerGoingDown(content::DownloadManager* manager) {
  CHECK_EQ(manager_, manager);
  auto snapshots = Snapshots();
  auto update = update_;
  Shutdown();
  // No callback contains service/item/manager pointers after teardown. Keep
  // actual terminal state; manager shutdown is not a fabricated failure. As
  // with Publish, a nested observer loop must not deliver these shell
  // callbacks.
  for (auto& snapshot : snapshots) {
    snapshot.available = snapshot.can_pause = snapshot.can_resume =
        snapshot.can_cancel = snapshot.can_review = snapshot.can_retry = false;
    snapshot.can_open = snapshot.can_reveal = snapshot.can_remove =
        snapshot.can_copy_file = snapshot.can_toggle_open = false;
    snapshot.item_identity.clear();
    base::SingleThreadTaskRunner::GetCurrentDefault()->PostNonNestableTask(
        FROM_HERE, base::BindOnce(update, std::move(snapshot)));
  }
}

std::vector<NativeDownloadSnapshot> NativeDownloads::Snapshots() const {
  std::vector<NativeDownloadSnapshot> snapshots;
  for (const auto& [id, item] : items_) {
    snapshots.push_back(Snapshot(*item));
  }
  return snapshots;
}

void NativeDownloads::Refresh(base::OnceCallback<void(bool)> completion) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  if (!manager_) {
    base::SingleThreadTaskRunner::GetCurrentDefault()->PostNonNestableTask(
        FROM_HERE, base::BindOnce(std::move(completion), false));
    return;
  }
  refresh_waiters_.push_back(std::move(completion));
  if (manager_->IsManagerInitialized()) OnManagerInitialized();
}

void NativeDownloads::OnManagerInitialized() {
  if (!manager_) return;
  // Constructor GetAllDownloads is empty when the manager has not finished
  // restoring history. Re-enumerate here so Refresh returns real GUIDs and
  // the shell does not wipe persisted rows against an empty set.
  content::DownloadManager::DownloadVector items;
  manager_->GetAllDownloads(&items);
  for (const auto& item : items) ObserveCreated(item, false);
  auto waiters = std::move(refresh_waiters_);
  for (auto& waiter : waiters) {
    base::SingleThreadTaskRunner::GetCurrentDefault()->PostNonNestableTask(
        FROM_HERE, base::BindOnce(
            [](base::WeakPtr<NativeDownloads> self,
               base::OnceCallback<void(bool)> waiter) {
              std::move(waiter).Run(self && self->manager_ &&
                                   self->manager_->IsManagerInitialized());
            }, weak_factory_.GetWeakPtr(), std::move(waiter)));
  }
}

bool NativeDownloads::Perform(const std::string& guid,
                              NativeDownloadAction action,
                              const std::string& expected_identity) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  auto* item = Find(guid);
  if (!item) {
    return false;
  }
  auto state = Snapshot(*item);
  if (!expected_identity.empty() && state.item_identity != expected_identity) return false;
  if (action == NativeDownloadAction::kRemove) {
    if (!state.can_remove) return false;
    item->Remove();
    return true;
  }
  DownloadItemModel model(item);
  DownloadCommands commands(model.GetWeakPtr());
  switch (action) {
    case NativeDownloadAction::kOpen:
      if (!state.can_open) return false;
      commands.ExecuteCommand(DownloadCommands::OPEN_WHEN_COMPLETE);
      return true;
    case NativeDownloadAction::kReveal:
      if (!state.can_reveal) return false;
      commands.ExecuteCommand(DownloadCommands::SHOW_IN_FOLDER);
      return true;
    case NativeDownloadAction::kToggleOpen:
      if (!state.can_toggle_open) return false;
      commands.ExecuteCommand(DownloadCommands::OPEN_WHEN_COMPLETE);
      return true;
    case NativeDownloadAction::kRemove:
      return false;  // Handled before constructing an item observer above.
    case NativeDownloadAction::kPause:
      if (!state.can_pause) return false;
      commands.ExecuteCommand(DownloadCommands::PAUSE);
      return true;
    case NativeDownloadAction::kResume:
      if (!state.can_resume) return false;
      commands.ExecuteCommand(DownloadCommands::RESUME);
      return true;
    case NativeDownloadAction::kCancel:
      if (!state.can_cancel) return false;
      commands.ExecuteCommand(DownloadCommands::CANCEL);
      return true;
    case NativeDownloadAction::kRetry: {
      if (!state.can_retry) return false;
      // RETRY is deliberately not implemented by DownloadCommands itself.
      // Match DownloadBubbleUIController::RetryDownload's real manager path,
      // using the last URL and a user-initiated request through all normal
      // target, policy and safety checks. No BrowserView is needed.
      constexpr auto annotation = net::DefineNetworkTrafficAnnotation(
          "parc_native_download_retry", R"(
            semantics {
              sender: "Parc downloads"
              description: "Retries a failed download selected by the user."
              trigger: "The user presses Retry in Downloads."
              data: "The final URL of the previous download."
              destination: WEBSITE
            }
            policy {
              cookies_allowed: YES
              cookies_store: "user"
              setting: "Only initiated by an explicit user action."
              policy_exception_justification: "Not implemented."
            })");
      auto parameters = std::make_unique<download::DownloadUrlParameters>(
          item->GetURL(), annotation);
      parameters->set_content_initiated(false);
      parameters->set_download_source(download::DownloadSource::RETRY_FROM_BUBBLE);
      manager_->DownloadUrl(std::move(parameters));
      return true;
    }
  }
}

std::optional<base::FilePath> NativeDownloads::FilePath(
    const std::string& guid, const std::string& identity) const {
  auto* item = Find(guid);
  if (!item || identity.empty()) return std::nullopt;
  const auto state = Snapshot(*item);
  if (state.item_identity != identity || !state.can_copy_file) return std::nullopt;
  return state.path;
}

download::DownloadItem* NativeDownloads::Find(const std::string& guid) const {
  auto it = items_.find(guid);
  if (!manager_ || it == items_.end() ||
      manager_->GetDownloadByGuid(guid) != it->second) {
    return nullptr;
  }
  return it->second.get();
}

std::optional<NativeDownloadReview> NativeDownloads::Review(
    const std::string& guid) const {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  auto* item = Find(guid);
  const auto identity = item_identities_.find(guid);
  if (!item || identity == item_identities_.end() ||
      item->GetState() == download::DownloadItem::CANCELLED) {
    return std::nullopt;
  }
  DownloadBubbleRowViewInfo row(DownloadItemModel::Wrap(
      item, std::make_unique<DownloadUIModel::BubbleStatusTextBuilder>()));
  auto& model = *row.model();
  DownloadCommands commands(model.GetWeakPtr());
  DownloadBubbleSecurityViewInfo security;
  security.InitializeForDownload(model);
  const bool enterprise_review =
      row.primary_button_command() == DownloadCommands::REVIEW &&
      commands.IsCommandEnabled(DownloadCommands::REVIEW);
  if (!security.HasSubpage() && !model.IsDangerous() && !model.IsInsecure() &&
      !enterprise_review) {
    return std::nullopt;
  }
  NativeDownloadReview review;
  review.guid = guid;
  review.item_identity = identity->second;
  review.path = item->GetTargetFilePath();
  review.url = PublicInternalURL(item->GetURL()).spec();
  review.name = item->GetFileNameToReportUser().LossyDisplayName();
  review.danger_type = static_cast<int>(item->GetDangerType());
  review.insecure_status = static_cast<int>(item->GetInsecureDownloadStatus());
  review.state = static_cast<int>(item->GetState());
  review.warning = security.warning_summary();
  if (review.warning.empty()) {
    size_t filename_offset = 0;
    review.warning = model.GetWarningText(review.name, &filename_offset);
  }
  if (review.warning.empty()) review.warning = model.GetStatusText();
  review.secondary = security.warning_secondary_text();
  auto add_link = [&](std::u16string title, const GURL& url) {
    if (url.is_valid()) review.links.push_back({std::move(title), PublicInternalURL(url).spec()});
  };
#if BUILDFLAG(ENTERPRISE_CONTENT_ANALYSIS)
  if (auto enterprise = enterprise_review
          ? EnterpriseDelegate(*item, base::DoNothing(), base::DoNothing()) : nullptr) {
    // This is the same delegate and WARNING/FAILURE decision used by
    // ShowDownloadReviewDialog. Native presentation keeps its callbacks and
    // required justification; a block never gains a proceed action.
    review.enterprise = true;
    review.can_keep = item->GetDangerType() ==
                      download::DOWNLOAD_DANGER_TYPE_SENSITIVE_CONTENT_WARNING;
    review.can_discard = true;
    review.warning = enterprise->GetCustomMessage().value_or(
        l10n_util::GetPluralStringFUTF16(
            review.can_keep ? IDS_DEEP_SCANNING_DIALOG_UPLOAD_WARNING_MESSAGE
                            : IDS_DEEP_SCANNING_DIALOG_UPLOAD_FAILURE_MESSAGE, 1));
    review.secondary.clear();
    review.keep_title = l10n_util::GetStringUTF16(IDS_DEEP_SCANNING_DIALOG_PROCEED_BUTTON);
    review.discard_title = enterprise->OverrideCancelButtonText().value();
    review.buttons.push_back({NativeDownloadReviewAction::kDiscard, review.discard_title});
    if (review.can_keep) review.buttons.push_back({NativeDownloadReviewAction::kKeep, review.keep_title});
    review.needs_justification = review.can_keep && enterprise->BypassRequiresJustification();
    review.justification_label = enterprise->GetBypassJustificationLabel();
    if (auto url = enterprise->GetCustomLearnMoreUrl())
      add_link(l10n_util::GetStringUTF16(
          IDS_DEEP_SCANNING_DIALOG_CUSTOM_MESSAGE_LEARN_MORE_LINK), *url);
    if (auto ranges = enterprise->GetCustomRuleMessageRanges()) {
      for (const auto& [range, url] : *ranges) {
        if (range.IsValid() && range.GetMax() <= review.warning.size())
          add_link(review.warning.substr(range.GetMin(), range.length()), url);
      }
    }
    return review;
  }
#endif
  review.scanning = security.has_progress_bar();
#if BUILDFLAG(SAFE_BROWSING_DOWNLOAD_PROTECTION)
  const auto danger = item->GetDangerType();
  review.needs_password = danger == download::DOWNLOAD_DANGER_TYPE_PROMPT_FOR_LOCAL_PASSWORD_SCANNING ||
      (danger == download::DOWNLOAD_DANGER_TYPE_PROMPT_FOR_SCANNING &&
       DownloadItemWarningData::IsTopLevelEncryptedArchive(item));
  review.incorrect_password = review.needs_password &&
      DownloadItemWarningData::HasIncorrectPassword(item);
#endif
  review.password_label = l10n_util::GetStringUTF16(IDS_DOWNLOAD_BUBBLE_PASSWORD_PROMPT);
  review.password_error = l10n_util::GetStringUTF16(IDS_DOWNLOAD_BUBBLE_PASSWORD_PROMPT_INVALID);
  review.password_empty_error = l10n_util::GetStringUTF16(IDS_DOWNLOAD_BUBBLE_PASSWORD_PROMPT_EMPTY);
  auto copy_button = [&](const auto& button) {
    if (!commands.IsCommandEnabled(button.command)) return;
    std::optional<NativeDownloadReviewAction> action;
    switch (button.command) {
      case DownloadCommands::KEEP:
        action = NativeDownloadReviewAction::kKeep;
        review.can_keep = true;
        review.keep_title = button.label;
        break;
      case DownloadCommands::DISCARD:
        action = NativeDownloadReviewAction::kDiscard;
        review.can_discard = true;
        review.discard_title = button.label;
        break;
#if BUILDFLAG(SAFE_BROWSING_DOWNLOAD_PROTECTION)
      case DownloadCommands::DEEP_SCAN:
        if (ProtectionService()) action = NativeDownloadReviewAction::kScan;
        break;
      case DownloadCommands::BYPASS_DEEP_SCANNING:
        if (ProtectionService()) action = NativeDownloadReviewAction::kBypassScan;
        break;
      case DownloadCommands::CANCEL_DEEP_SCAN:
        if (ProtectionService()) action = NativeDownloadReviewAction::kCancelScan;
        break;
      case DownloadCommands::CANCEL:
        if (danger == download::DOWNLOAD_DANGER_TYPE_ASYNC_LOCAL_PASSWORD_SCANNING &&
            ProtectionService()) action = NativeDownloadReviewAction::kCancelScan;
        break;
#endif
      case DownloadCommands::OPEN_SAFE_BROWSING_SETTING:
        add_link(button.label, ReviewHelpURL(model, button.command));
        break;
      default:
        break;
    }
    if (action) review.buttons.push_back({*action, button.label});
  };
  if (security.has_primary_button()) copy_button(security.primary_button());
  if (security.has_secondary_button()) copy_button(security.secondary_button());
  if (security.learn_more_link()) {
    const auto& link = *security.learn_more_link();
    if (commands.IsCommandEnabled(link.linked_range.command))
      add_link(link.label_and_link_text, ReviewHelpURL(model, link.linked_range.command));
  }
  // Keep Chromium's supplied order. Discard remains available when a scanning
  // or blocked page's supplied buttons have different meanings (e.g. Cancel
  // returns a local scan to its password prompt instead of deleting the file).
  if (!review.can_discard && commands.IsCommandEnabled(DownloadCommands::DISCARD)) {
    review.can_discard = true;
    review.discard_title = l10n_util::GetStringUTF16(
        IDS_DEEP_SCANNING_DIALOG_DOWNLOADS_DISCARD_FILE_BUTTON);
    review.buttons.push_back({NativeDownloadReviewAction::kDiscard, review.discard_title});
  }
  return review;
}

bool NativeDownloads::PerformReview(const NativeDownloadReview& expected,
                                    NativeDownloadReviewAction action,
                                    const std::string& password,
                                    const std::u16string& justification) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  auto current = Review(expected.guid);
  if (!current || *current != expected ||
      std::ranges::none_of(current->buttons, [action](const auto& button) {
        return button.action == action;
      })) return false;
  auto* item = Find(expected.guid);
  if (!item) return false;
#if BUILDFLAG(ENTERPRISE_CONTENT_ANALYSIS)
  if (current->enterprise) {
    if (action == NativeDownloadReviewAction::kKeep && current->needs_justification &&
        (justification.empty() || justification.size() > 280)) return false;
    // The real delegate stores the justification in ScanResult and owns the
    // one-shot Keep/Discard callback. Resolve the exact item again inside that
    // callback; no retained model or raw item crosses a presentation boundary.
    auto run = [](base::WeakPtr<NativeDownloads> service, NativeDownloadReview expected,
                  DownloadCommands::Command command) {
      if (!service) return;
      auto current = service->Review(expected.guid);
      if (!current || *current != expected) return;
      auto* item = service->Find(expected.guid);
      if (!item) return;
      DownloadItemModel model(item);
      DownloadCommands commands(model.GetWeakPtr());
      if (commands.IsCommandEnabled(command)) commands.ExecuteCommand(command);
    };
    auto delegate = EnterpriseDelegate(*item,
        base::BindOnce(run, weak_factory_.GetWeakPtr(), expected, DownloadCommands::KEEP),
        base::BindOnce(run, weak_factory_.GetWeakPtr(), expected, DownloadCommands::DISCARD));
    if (!delegate) return false;
    if (action == NativeDownloadReviewAction::kKeep) {
      if (!current->can_keep) return false;
      delegate->BypassWarnings(current->needs_justification
          ? std::make_optional(justification) : std::nullopt);
    } else if (action == NativeDownloadReviewAction::kDiscard) {
      delegate->Cancel(current->can_keep);
    } else return false;
    return true;
  }
#endif
  DownloadItemModel model(item);
  DownloadCommands commands(model.GetWeakPtr());
#if BUILDFLAG(SAFE_BROWSING_DOWNLOAD_PROTECTION)
  if (action == NativeDownloadReviewAction::kScan) {
    if (!ProtectionService() || (current->needs_password && password.empty())) return false;
    if (item->GetDangerType() == download::DOWNLOAD_DANGER_TYPE_PROMPT_FOR_LOCAL_PASSWORD_SCANNING) {
      safe_browsing::LogLocalDecryptionEvent(safe_browsing::DeepScanEvent::kPromptAccepted);
      safe_browsing::DownloadProtectionService::CheckDownloadWithLocalDecryption(item, password);
    } else if (item->GetDangerType() == download::DOWNLOAD_DANGER_TYPE_PROMPT_FOR_SCANNING) {
      safe_browsing::LogDeepScanEvent(item, safe_browsing::DeepScanEvent::kPromptAccepted);
      DownloadItemWarningData::AddWarningActionEvent(item,
          DownloadItemWarningData::WarningSurface::BUBBLE_SUBPAGE,
          DownloadItemWarningData::WarningAction::ACCEPT_DEEP_SCAN);
      safe_browsing::DownloadProtectionService::UploadForConsumerDeepScanning(item,
          current->needs_password
              ? DownloadItemWarningData::DeepScanTrigger::TRIGGER_ENCRYPTED_CONSUMER_PROMPT
              : DownloadItemWarningData::DeepScanTrigger::TRIGGER_CONSUMER_PROMPT,
          password);
    } else return false;
    return true;
  }
  if ((action == NativeDownloadReviewAction::kCancelScan ||
       action == NativeDownloadReviewAction::kBypassScan) &&
      item->GetDangerType() == download::DOWNLOAD_DANGER_TYPE_ASYNC_LOCAL_PASSWORD_SCANNING) {
    auto* protection = ProtectionService();
    if (!protection) return false;
    auto weak = weak_factory_.GetWeakPtr();
    protection->CancelChecksForDownload(item);
    if (!weak || weak->Find(expected.guid) != item) return true;
    auto* core = DownloadCoreServiceFactory::GetForBrowserContext(
        content::DownloadItemUtils::GetBrowserContext(item));
    auto* delegate = core ? core->GetDownloadManagerDelegate() : nullptr;
    if (!delegate) return false;
    const bool cancel = action == NativeDownloadReviewAction::kCancelScan;
    safe_browsing::LogLocalDecryptionEvent(cancel ? safe_browsing::DeepScanEvent::kScanCanceled
                                                : safe_browsing::DeepScanEvent::kPromptBypassed);
    if (!cancel) g_browser_process->safe_browsing_service()->SendDownloadReport(item,
        safe_browsing::ClientSafeBrowsingReportRequest::DANGEROUS_DOWNLOAD_RECOVERY,
        true, std::nullopt);
    delegate->CheckClientDownloadDone(item->GetId(), cancel
        ? safe_browsing::DownloadCheckResult::PROMPT_FOR_LOCAL_PASSWORD_SCANNING
        : safe_browsing::DownloadCheckResult::UNKNOWN);
    return true;
  }
#endif
  DownloadCommands::Command command;
  switch (action) {
    case NativeDownloadReviewAction::kKeep: command = DownloadCommands::KEEP; break;
    case NativeDownloadReviewAction::kDiscard: command = DownloadCommands::DISCARD; break;
    case NativeDownloadReviewAction::kBypassScan: command = DownloadCommands::BYPASS_DEEP_SCANNING; break;
    case NativeDownloadReviewAction::kCancelScan: command = DownloadCommands::CANCEL_DEEP_SCAN; break;
    case NativeDownloadReviewAction::kScan: return false;
  }
  if (!commands.IsCommandEnabled(command)) return false;
  if (command == DownloadCommands::KEEP || command == DownloadCommands::DISCARD ||
      command == DownloadCommands::BYPASS_DEEP_SCANNING) {
    DownloadItemWarningData::AddWarningActionEvent(item,
        DownloadItemWarningData::WarningSurface::BUBBLE_SUBPAGE,
        command == DownloadCommands::DISCARD ? DownloadItemWarningData::WarningAction::DISCARD :
        command == DownloadCommands::KEEP ? DownloadItemWarningData::WarningAction::PROCEED :
                                           DownloadItemWarningData::WarningAction::PROCEED_DEEP_SCAN);
  }
  commands.ExecuteCommand(command);
  return true;
}

std::optional<std::string> NativeDownloads::ReviewLink(
    const NativeDownloadReview& expected, size_t index) const {
  auto current = Review(expected.guid);
  if (!current || *current != expected || index >= current->links.size()) return std::nullopt;
  return current->links[index].url;
}

}  // namespace parc
