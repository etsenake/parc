// Copyright 2026 Parc contributors.
#ifndef PARC_NATIVE_DOWNLOADS_H_
#define PARC_NATIVE_DOWNLOADS_H_

#include <map>
#include <optional>
#include <string>
#include <vector>

#include "base/files/file_path.h"
#include "base/functional/callback.h"
#include "base/memory/raw_ptr.h"
#include "base/memory/weak_ptr.h"
#include "base/supports_user_data.h"
#include "base/unguessable_token.h"
#include "components/download/public/common/download_item.h"
#include "content/public/browser/download_manager.h"
#include "content/public/browser/weak_document_ptr.h"

class Profile;
class DownloadPrefs;

namespace parc {

// A value, never a retained CefDownloadItem or a page-owned callback. GUID is
// resolved only within its actual Profile manager; integer IDs are not global.
struct NativeDownloadSnapshot {
  base::FilePath profile_path;
  std::string guid;
  std::string item_identity;
  double started_at = 0;
  base::FilePath path;
  std::string name;
  std::string url;
  std::string source_domain;
  std::string mime_type;
  // Negative means the original manager has no current estimate.
  double time_remaining_seconds = -1;
  download::DownloadItem::DownloadState state;
  int interrupt_reason = 0;
  int64_t received = 0;
  int64_t total = 0;
  bool paused = false;
  bool available = false;
  bool removed = false;
  bool requires_review = false;
  bool can_pause = false;
  bool can_resume = false;
  bool can_cancel = false;
  bool can_review = false;
  bool can_retry = false;
  bool can_open = false;
  bool can_reveal = false;
  bool can_remove = false;
  bool can_copy_file = false;
  bool can_toggle_open = false;
  bool open_when_complete = false;
  bool file_missing = false;
  std::u16string status_text;
};

enum class NativeDownloadReviewAction {
  kKeep, kDiscard, kScan, kBypassScan, kCancelScan
};
struct NativeDownloadReviewButton {
  NativeDownloadReviewAction action;
  std::u16string title;
  bool operator==(const NativeDownloadReviewButton&) const = default;
};
struct NativeDownloadReviewLink {
  std::u16string title;
  std::string url;
  bool operator==(const NativeDownloadReviewLink&) const = default;
};

// A copied review of one exact item incarnation. The native application also
// binds this to its weak Profile identity. Progress bytes are deliberately not
// part of the decision: a transfer can advance while its warning is open.
struct NativeDownloadReview {
  std::string guid;
  base::UnguessableToken item_identity;
  base::FilePath path;
  std::string url;
  int danger_type = 0;
  int insecure_status = 0;
  int state = 0;
  std::u16string name;
  std::u16string warning;
  std::u16string secondary;
  std::u16string keep_title;
  std::u16string discard_title;
  bool can_keep = false;
  bool can_discard = false;
  std::vector<NativeDownloadReviewButton> buttons;
  std::vector<NativeDownloadReviewLink> links;
  bool enterprise = false;
  bool needs_password = false;
  bool incorrect_password = false;
  bool scanning = false;
  bool needs_justification = false;
  std::u16string password_label;
  std::u16string password_error;
  std::u16string password_empty_error;
  std::u16string justification_label;
  bool operator==(const NativeDownloadReview&) const = default;
};

struct NativeDownloadPreferencesSnapshot {
  base::FilePath directory;
  bool prompt = false;
  bool directory_managed = false;
  bool prompt_managed = false;
};

// Operate on the real Profile and its real DownloadPrefs. The application
// boundary additionally validates its registered weak Profile identity.
NativeDownloadPreferencesSnapshot ReadNativeDownloadPreferences(
    Profile& profile,
    const DownloadPrefs& preferences);
bool SetNativeDownloadDirectory(Profile& profile,
                                DownloadPrefs& preferences,
                                const base::FilePath& directory);
bool SetNativeDownloadPrompt(Profile& profile, bool prompt);

enum class NativeDownloadAction { kPause, kResume, kCancel, kRetry, kOpen, kReveal, kRemove, kToggleOpen };

class NativeDownloads final : public base::SupportsUserData::Data,
                              public content::DownloadManager::Observer,
                              public download::DownloadItem::Observer {
 public:
  using Update = base::RepeatingCallback<void(NativeDownloadSnapshot)>;
  using Created = base::RepeatingCallback<void(NativeDownloadSnapshot,
                                               content::WeakDocumentPtr)>;
  static NativeDownloads& Install(Profile& profile, Update update,
                                  Created created = {});
  static NativeDownloads* From(Profile& profile);

  NativeDownloads(content::DownloadManager& manager,
                  base::FilePath profile_path,
                  Update update, Created created = {});
  ~NativeDownloads() override;
  NativeDownloads(const NativeDownloads&) = delete;
  NativeDownloads& operator=(const NativeDownloads&) = delete;

  // True means the real item accepted an eligible command, not that a state
  // transition or transfer completed. The manager remains authoritative.
  bool Perform(const std::string& guid, NativeDownloadAction action,
               const std::string& expected_identity = {});
  // File output is permitted only for the original safe completed item.
  std::optional<base::FilePath> FilePath(const std::string& guid,
                                       const std::string& identity) const;
  std::optional<NativeDownloadReview> Review(const std::string& guid) const;
  bool PerformReview(const NativeDownloadReview& review,
                     NativeDownloadReviewAction action,
                     const std::string& password = {},
                     const std::u16string& justification = {});
  std::optional<std::string> ReviewLink(const NativeDownloadReview& review,
                                        size_t index) const;
  std::vector<NativeDownloadSnapshot> Snapshots() const;
  // Completes after the genuine manager has loaded history and queued values.
  void Refresh(base::OnceCallback<void(bool)> completion);
  void OnManagerInitialized() override;
  void Shutdown();
  // Identity-only admission for a transient original-document arrival: the
  // same live item incarnation, whatever its state.
  bool CanPresentArrival(const std::string& guid,
                         const std::string& identity) const;

  void OnDownloadCreated(content::DownloadManager*,
                         download::DownloadItem*) override;
  void ManagerGoingDown(content::DownloadManager*) override;
  void OnDownloadUpdated(download::DownloadItem*) override;
  void OnDownloadRemoved(download::DownloadItem*) override;
  void OnDownloadDestroyed(download::DownloadItem*) override;

 private:
  NativeDownloadSnapshot Snapshot(download::DownloadItem&,
                                  bool include_controls = true) const;
  void Remove(download::DownloadItem&, bool destroying);
  download::DownloadItem* Find(const std::string& guid) const;
  void Publish(NativeDownloadSnapshot);
  void ObserveCreated(download::DownloadItem*, bool genuine_creation);
  raw_ptr<content::DownloadManager> manager_;
  const base::FilePath profile_path_;
  Update update_;
  Created created_;
  std::vector<base::OnceCallback<void(bool)>> refresh_waiters_;
  std::map<std::string, raw_ptr<download::DownloadItem>> items_;
  std::map<std::string, base::UnguessableToken> item_identities_;
  base::WeakPtrFactory<NativeDownloads> weak_factory_{this};
};

}  // namespace parc
#endif
