// Copyright 2026 Parc contributors.
// Exercises the production observer/service against genuine DownloadItemImpl
// state transitions. Only the manager lookup/ownership boundary is a test
// double.
#include "parc/native/downloads.h"

#include "base/functional/bind.h"
#include "base/run_loop.h"
#include "base/task/single_thread_task_runner.h"
#include "base/test/bind.h"
#include "base/time/time.h"
#include "base/uuid.h"
#include "chrome/browser/download/download_prefs.h"
#include "chrome/common/pref_names.h"
#include "chrome/test/base/testing_profile.h"
#include "components/download/public/common/download_create_info.h"
#include "components/download/public/common/download_item_impl.h"
#include "components/download/public/common/download_item_impl_delegate.h"
#include "components/download/public/common/download_save_info.h"
#include "components/download/public/common/download_url_parameters.h"
#include "components/prefs/pref_change_registrar.h"
#include "components/prefs/pref_service.h"
#include "components/sync_preferences/testing_pref_service_syncable.h"
#include "content/public/test/browser_task_environment.h"
#include "content/public/test/mock_download_manager.h"
#include "testing/gmock/include/gmock/gmock.h"
#include "testing/gtest/include/gtest/gtest.h"
#include "url/gurl.h"

namespace parc {
namespace {
class ResumeDelegate final : public download::DownloadItemImplDelegate {
 public:
  void ResumeInterruptedDownload(
      std::unique_ptr<download::DownloadUrlParameters>,
      const std::string&) override {
    ++resumptions;
  }
  int resumptions = 0;
};
// Registered after the service to exercise a later observer entering a nested
// run loop while the genuine item's UpdateObservers frame is still active.
class CallbackObserver final : public download::DownloadItem::Observer {
 public:
  CallbackObserver(download::DownloadItem& item, base::RepeatingClosure updated)
      : item_(&item), updated_(std::move(updated)) {
    item_->AddObserver(this);
  }
  ~CallbackObserver() override {
    if (item_) {
      item_->RemoveObserver(this);
    }
  }
  void OnDownloadUpdated(download::DownloadItem*) override { updated_.Run(); }
  void OnDownloadDestroyed(download::DownloadItem*) override {
    item_ = nullptr;
  }

 private:
  raw_ptr<download::DownloadItem> item_;
  base::RepeatingClosure updated_;
};
class NativeDownloadsTest : public testing::Test {
 protected:
  void Create(download::DownloadItem::DownloadState state =
                  download::DownloadItem::INTERRUPTED,
              download::DownloadDangerType danger =
                  download::DOWNLOAD_DANGER_TYPE_NOT_DANGEROUS) {
    item = MakeItem(state, danger);
    ON_CALL(manager, GetAllDownloads).WillByDefault([this](auto* items) {
      items->push_back(item.get());
    });
    ON_CALL(manager, GetDownloadByGuid)
        .WillByDefault([this](const std::string& id) {
          return item && id == item->GetGuid() ? item.get() : nullptr;
        });
    service = std::make_unique<NativeDownloads>(
        manager, base::FilePath("/profiles/work"),
        base::BindLambdaForTesting([this](NativeDownloadSnapshot snapshot) {
          updates.push_back(std::move(snapshot));
          if (destroy_on_update) {
            service.reset();
          }
          if (destroy_item_on_update) {
            item.reset();
          }
        }),
        base::BindLambdaForTesting(
            [this](NativeDownloadSnapshot, content::WeakDocumentPtr) {
              ++arrivals;
            }));
  }
  // A genuine DownloadItemImpl with no DownloadItemUtils data, as restored
  // history and imported in-progress items have (AttachInfo(nullptr)).
  std::unique_ptr<download::DownloadItemImpl> MakeItem(
      download::DownloadItem::DownloadState state,
      download::DownloadDangerType danger =
          download::DOWNLOAD_DANGER_TYPE_NOT_DANGEROUS) {
    return std::make_unique<download::DownloadItemImpl>(
        &delegate, base::Uuid::GenerateRandomV4().AsLowercaseString(), 7,
        base::FilePath("/tmp/parc-download.part"),
        base::FilePath("/tmp/parc-download.txt"),
        std::vector<GURL>{GURL("https://example.test/download")}, GURL(), "",
        GURL(), GURL(), std::nullopt, "text/plain", "text/plain",
        base::Time::Now(), base::Time(), "etag", "", 12, -1, 0, "", state,
        danger, download::DOWNLOAD_INTERRUPT_REASON_NETWORK_FAILED, false,
        false, false, base::Time(), false,
        std::vector<download::DownloadItem::ReceivedSlice>{}, 0, 0, nullptr);
  }
  void ExpectNestedObserverDefersDelivery(bool manager_shutdown) {
    Create();
    tasks.RunUntilIdle();
    updates.clear();
    destroy_on_update = destroy_item_on_update = true;
    bool nested_ran = false;
    CallbackObserver observer(*item, base::BindLambdaForTesting([&] {
      if (manager_shutdown) {
        service->ManagerGoingDown(&manager);
      }
      base::RunLoop nested(base::RunLoop::Type::kNestableTasksAllowed);
      base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
          FROM_HERE, nested.QuitClosure());
      nested.Run();
      nested_ran = true;
      EXPECT_TRUE(updates.empty());
      EXPECT_TRUE(service);
      EXPECT_TRUE(item);
    }));
    // Enter an actual outer loop first; the observer's loop must be nested.
    base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
        FROM_HERE, base::BindLambdaForTesting([&] {
          item->UpdateObservers();
          EXPECT_TRUE(nested_ran);
          EXPECT_TRUE(updates.empty());
          EXPECT_TRUE(service);
          EXPECT_TRUE(item);
        }));
    tasks.RunUntilIdle();
    ASSERT_EQ(updates.size(), 1u);
    EXPECT_EQ(updates.back().available, !manager_shutdown);
    EXPECT_FALSE(service);
    // Real DownloadItemImpl destruction CHECKs that UpdateObservers unwound.
    EXPECT_FALSE(item);
  }
  void TearDown() override {
    service.reset();
    item.reset();
    tasks.RunUntilIdle();
  }
  content::BrowserTaskEnvironment tasks;
  testing::NiceMock<content::MockDownloadManager> manager;
  ResumeDelegate delegate;
  std::unique_ptr<download::DownloadItemImpl> item;
  std::unique_ptr<NativeDownloads> service;
  std::vector<NativeDownloadSnapshot> updates;
  bool destroy_on_update = false;
  bool destroy_item_on_update = false;
  int arrivals = 0;
};

TEST_F(NativeDownloadsTest, ExtensionInstallsAreNotLibraryDownloads) {
  item = std::make_unique<download::DownloadItemImpl>(
      &delegate, base::Uuid::GenerateRandomV4().AsLowercaseString(), 7,
      base::FilePath("/tmp/parc-download.part"),
      base::FilePath("/tmp/1password.crx"),
      std::vector<GURL>{GURL("https://clients2.google.com/service/update2/crx")},
      GURL(), "", GURL(), GURL(), std::nullopt,
      "application/x-chrome-extension", "application/x-chrome-extension",
      base::Time::Now(), base::Time(), "etag", "", 12, -1, 0, "",
      download::DownloadItem::IN_PROGRESS,
      download::DOWNLOAD_DANGER_TYPE_NOT_DANGEROUS,
      download::DOWNLOAD_INTERRUPT_REASON_NONE, false, false, false,
      base::Time(), false,
      std::vector<download::DownloadItem::ReceivedSlice>{}, 0, 0, nullptr);
  ON_CALL(manager, GetAllDownloads).WillByDefault([this](auto* items) {
    items->push_back(item.get());
  });
  ON_CALL(manager, GetDownloadByGuid)
      .WillByDefault([this](const std::string& id) {
        return item && id == item->GetGuid() ? item.get() : nullptr;
      });
  service = std::make_unique<NativeDownloads>(
      manager, base::FilePath("/profiles/work"),
      base::BindLambdaForTesting([this](NativeDownloadSnapshot snapshot) {
        updates.push_back(std::move(snapshot));
      }),
      base::BindLambdaForTesting(
          [this](NativeDownloadSnapshot, content::WeakDocumentPtr) {
            ++arrivals;
          }));
  tasks.RunUntilIdle();
  EXPECT_TRUE(updates.empty());
  EXPECT_EQ(arrivals, 0);
  EXPECT_TRUE(service->Snapshots().empty());
}

TEST_F(NativeDownloadsTest, InitialHistoryIsCopiedAndNeverClaimsCompletion) {
  Create();
  EXPECT_TRUE(updates.empty());
  tasks.RunUntilIdle();
  ASSERT_EQ(updates.size(), 1u);
  const auto& value = updates.back();
  EXPECT_EQ(value.profile_path, base::FilePath("/profiles/work"));
  EXPECT_EQ(value.guid, item->GetGuid());
  EXPECT_EQ(value.total, -1);
  EXPECT_EQ(value.received, 12);
  EXPECT_EQ(value.source_domain, "example.test");
  EXPECT_EQ(value.mime_type, "text/plain");
  EXPECT_LT(value.time_remaining_seconds, 0);
  EXPECT_EQ(value.state, download::DownloadItem::INTERRUPTED);
  EXPECT_EQ(value.interrupt_reason,
            download::DOWNLOAD_INTERRUPT_REASON_NETWORK_FAILED);
  EXPECT_EQ(value.can_resume, item->CanResume());
}

//
// enumeration or an item without an initiating document.
TEST_F(NativeDownloadsTest, ManagerInitEnumeratesHistoryConstructorMissed) {
  ON_CALL(manager, GetAllDownloads).WillByDefault([](auto* items) {});
  service = std::make_unique<NativeDownloads>(
      manager, base::FilePath("/profiles/work"),
      base::BindLambdaForTesting([this](NativeDownloadSnapshot snapshot) {
        updates.push_back(std::move(snapshot));
      }),
      base::BindLambdaForTesting(
          [this](NativeDownloadSnapshot, content::WeakDocumentPtr) {
            ++arrivals;
          }));
  tasks.RunUntilIdle();
  EXPECT_TRUE(updates.empty());
  item = MakeItem(download::DownloadItem::COMPLETE);
  ON_CALL(manager, GetAllDownloads).WillByDefault([this](auto* items) {
    items->push_back(item.get());
  });
  service->OnManagerInitialized();
  tasks.RunUntilIdle();
  ASSERT_EQ(updates.size(), 1u);
  EXPECT_EQ(updates.back().guid, item->GetGuid());
  EXPECT_EQ(arrivals, 0);
}

TEST_F(NativeDownloadsTest, HistoryAndDetachedItemsNeverPresentArrival) {
  Create();
  tasks.RunUntilIdle();
  EXPECT_EQ(arrivals, 0);
  auto created = MakeItem(download::DownloadItem::IN_PROGRESS);
  ON_CALL(manager, GetDownloadByGuid)
      .WillByDefault([&](const std::string& id) -> download::DownloadItem* {
        if (item && id == item->GetGuid()) return item.get();
        return created && id == created->GetGuid() ? created.get() : nullptr;
      });
  service->OnDownloadCreated(&manager, created.get());
  tasks.RunUntilIdle();
  EXPECT_EQ(updates.back().guid, created->GetGuid());
  EXPECT_EQ(arrivals, 0);
  created.reset();
  tasks.RunUntilIdle();
}

TEST_F(NativeDownloadsTest, ArrivalAdmissionIsTheLiveIncarnationOnly) {
  Create(download::DownloadItem::IN_PROGRESS);
  tasks.RunUntilIdle();
  const auto value = updates.back();
  EXPECT_TRUE(service->CanPresentArrival(value.guid, value.item_identity));
  EXPECT_FALSE(service->CanPresentArrival(value.guid, "another-incarnation"));
  EXPECT_FALSE(service->CanPresentArrival("missing", value.item_identity));
  //
  // an existing owner, never the pending hover query).
  EXPECT_TRUE(service->Perform(item->GetGuid(), NativeDownloadAction::kCancel));
  EXPECT_TRUE(service->CanPresentArrival(value.guid, value.item_identity));
  service->Shutdown();
  EXPECT_FALSE(service->CanPresentArrival(value.guid, value.item_identity));
}

TEST_F(NativeDownloadsTest, ResumeUsesRealControllerAndDoesNotInventSuccess) {
  Create();
  ASSERT_TRUE(item->CanResume());
  EXPECT_TRUE(service->Perform(item->GetGuid(), NativeDownloadAction::kResume));
  EXPECT_EQ(delegate.resumptions, 1);
  EXPECT_NE(item->GetState(), download::DownloadItem::COMPLETE);
  tasks.RunUntilIdle();
  EXPECT_EQ(updates.back().state, item->GetState());
}

TEST_F(NativeDownloadsTest, CancelChangesActualItemAndRejectsSecondCancel) {
  Create();
  EXPECT_TRUE(service->Perform(item->GetGuid(), NativeDownloadAction::kCancel));
  EXPECT_EQ(item->GetState(), download::DownloadItem::CANCELLED);
  EXPECT_FALSE(
      service->Perform(item->GetGuid(), NativeDownloadAction::kCancel));
  tasks.RunUntilIdle();
  EXPECT_EQ(updates.back().state, download::DownloadItem::CANCELLED);
  EXPECT_FALSE(updates.back().can_resume);
}

TEST_F(NativeDownloadsTest,
       CompletedAndUnsafeItemsDoNotExposeTransferControls) {
  Create(download::DownloadItem::COMPLETE);
  EXPECT_FALSE(service->Perform(item->GetGuid(), NativeDownloadAction::kPause));
  EXPECT_FALSE(
      service->Perform(item->GetGuid(), NativeDownloadAction::kResume));
  EXPECT_FALSE(
      service->Perform(item->GetGuid(), NativeDownloadAction::kCancel));
  service.reset();
  item.reset();
  Create(download::DownloadItem::INTERRUPTED,
         download::DOWNLOAD_DANGER_TYPE_DANGEROUS_FILE);
  EXPECT_TRUE(service->Snapshots().front().requires_review);
  EXPECT_FALSE(
      service->Perform(item->GetGuid(), NativeDownloadAction::kResume));
  EXPECT_EQ(delegate.resumptions, 0);
}

TEST_F(NativeDownloadsTest, RemovalInvalidatesGUIDBeforeLaterCommands) {
  Create();
  const auto id = item->GetGuid();
  item->Remove();
  EXPECT_FALSE(service->Perform(id, NativeDownloadAction::kResume));
  EXPECT_TRUE(service->Snapshots().empty());
  tasks.RunUntilIdle();
  EXPECT_TRUE(updates.back().removed);
  EXPECT_FALSE(updates.back().available);
}

TEST_F(NativeDownloadsTest, DestructionDoesNotLeaveBorrowedItemOrCallback) {
  Create();
  const auto id = item->GetGuid();
  item.reset();
  EXPECT_FALSE(service->Perform(id, NativeDownloadAction::kCancel));
  tasks.RunUntilIdle();
  EXPECT_TRUE(updates.back().removed);
}

TEST_F(NativeDownloadsTest,
       ObserverDeliveryMayReleaseServiceAfterEngineStackReturns) {
  Create();
  tasks.RunUntilIdle();
  destroy_on_update = true;
  item->UpdateObservers();
  ASSERT_TRUE(
      service);  // No shell callback ran inside DownloadItem notification.
  tasks.RunUntilIdle();
  EXPECT_FALSE(service);
  item->UpdateObservers();  // Observer was genuinely removed.
}

TEST_F(NativeDownloadsTest, LaterObserverNestedLoopCannotDeliverItemUpdate) {
  ExpectNestedObserverDefersDelivery(/*manager_shutdown=*/false);
}

TEST_F(NativeDownloadsTest,
       LaterObserverNestedLoopCannotDeliverManagerShutdown) {
  ExpectNestedObserverDefersDelivery(/*manager_shutdown=*/true);
}

TEST_F(NativeDownloadsTest,
       ManagerShutdownDisablesControlsWithoutInventingFailure) {
  Create(download::DownloadItem::COMPLETE);
  const auto id = item->GetGuid();
  service->ManagerGoingDown(&manager);
  EXPECT_FALSE(service->Perform(id, NativeDownloadAction::kCancel));
  tasks.RunUntilIdle();
  ASSERT_FALSE(updates.empty());
  EXPECT_EQ(updates.back().state, download::DownloadItem::COMPLETE);
  EXPECT_FALSE(updates.back().available);
}

TEST_F(NativeDownloadsTest, ForeignGUIDCannotControlAnotherProfileItem) {
  Create();
  EXPECT_FALSE(
      service->Perform(base::Uuid::GenerateRandomV4().AsLowercaseString(),
                       NativeDownloadAction::kCancel));
  EXPECT_EQ(item->GetState(), download::DownloadItem::INTERRUPTED);
}
TEST_F(NativeDownloadsTest, PendingTargetNeverPretendsPauseIsAvailable) {
  Create();
  service.reset();
  item.reset();
  download::DownloadCreateInfo info;
  info.save_info = std::make_unique<download::DownloadSaveInfo>();
  info.url_chain.push_back(GURL("https://example.test/download"));
  item = std::make_unique<download::DownloadItemImpl>(&delegate, 8, info);
  service = std::make_unique<NativeDownloads>(
      manager, base::FilePath("/profiles/work"),
      base::BindLambdaForTesting([this](NativeDownloadSnapshot value) {
        updates.push_back(std::move(value));
      }));
  ASSERT_EQ(item->GetState(), download::DownloadItem::IN_PROGRESS);
  ASSERT_TRUE(item->GetFullPath().empty());
  EXPECT_FALSE(service->Snapshots().front().can_pause);
  EXPECT_FALSE(service->Perform(item->GetGuid(), NativeDownloadAction::kPause));
  EXPECT_FALSE(item->IsPaused());
}

class NativeDownloadPreferencesTest : public testing::Test {
 protected:
  content::BrowserTaskEnvironment task_environment;
  TestingProfile profile;
  DownloadPrefs preferences{&profile};
};
TEST_F(NativeDownloadPreferencesTest, RealPreferencesOwnValuesAndSavePath) {
  const base::FilePath directory("/tmp/parc-download-preferences");
  ASSERT_TRUE(SetNativeDownloadDirectory(profile, preferences, directory));
  ASSERT_TRUE(SetNativeDownloadPrompt(profile, true));
  const auto snapshot = ReadNativeDownloadPreferences(profile, preferences);
  EXPECT_EQ(snapshot.directory, directory);
  EXPECT_EQ(preferences.SaveFilePath(), directory);
  EXPECT_TRUE(snapshot.prompt);
  EXPECT_FALSE(snapshot.directory_managed);
  EXPECT_FALSE(snapshot.prompt_managed);
  ASSERT_TRUE(SetNativeDownloadPrompt(profile, false));
  EXPECT_TRUE(snapshot.prompt);
  EXPECT_FALSE(preferences.PromptForDownload());
}
TEST_F(NativeDownloadPreferencesTest,
       InvalidPathDoesNotChangeEitherPreference) {
  const auto before = preferences.DownloadPath();
  const auto save_before = preferences.SaveFilePath();
  for (const char* path : {"", "relative/downloads", "/tmp/../downloads"}) {
    EXPECT_FALSE(
        SetNativeDownloadDirectory(profile, preferences, base::FilePath(path)));
    EXPECT_EQ(preferences.DownloadPath(), before);
    EXPECT_EQ(preferences.SaveFilePath(), save_before);
  }
}
TEST_F(NativeDownloadPreferencesTest, ManagedDirectoryRefusesBothChanges) {
  auto* values = profile.GetTestingPrefService();
  values->SetManagedPref(prefs::kPromptForDownload, base::Value(false));
  values->SetManagedPref(prefs::kDownloadDefaultDirectory,
                         base::Value("/tmp/parc-managed-downloads"));
  EXPECT_FALSE(SetNativeDownloadDirectory(
      profile, preferences, base::FilePath("/tmp/parc-user-downloads")));
  EXPECT_FALSE(SetNativeDownloadPrompt(profile, true));
  const auto snapshot = ReadNativeDownloadPreferences(profile, preferences);
  EXPECT_EQ(snapshot.directory, base::FilePath("/tmp/parc-managed-downloads"));
  EXPECT_TRUE(snapshot.directory_managed);
  EXPECT_TRUE(snapshot.prompt_managed);
  EXPECT_FALSE(snapshot.prompt);
}
TEST_F(NativeDownloadPreferencesTest,
       ManagedDirectoryAloneRefusesPromptChange) {
  // The normal mandatory directory policy also manages the prompt to false.
  // Preserve refusal during a partially delivered policy update as well.
  ASSERT_TRUE(SetNativeDownloadPrompt(profile, false));
  profile.GetTestingPrefService()->SetManagedPref(
      prefs::kDownloadDefaultDirectory,
      base::Value("/tmp/parc-managed-downloads"));
  EXPECT_FALSE(SetNativeDownloadPrompt(profile, true));
  const auto snapshot = ReadNativeDownloadPreferences(profile, preferences);
  EXPECT_TRUE(snapshot.directory_managed);
  EXPECT_FALSE(snapshot.prompt_managed);
  EXPECT_FALSE(snapshot.prompt);
}
TEST_F(NativeDownloadPreferencesTest,
       ManagedPromptDoesNotLockUnmanagedDirectory) {
  profile.GetTestingPrefService()->SetManagedPref(prefs::kPromptForDownload,
                                                  base::Value(true));
  EXPECT_FALSE(SetNativeDownloadPrompt(profile, false));
  EXPECT_TRUE(SetNativeDownloadDirectory(
      profile, preferences, base::FilePath("/tmp/parc-allowed-downloads")));
  const auto snapshot = ReadNativeDownloadPreferences(profile, preferences);
  EXPECT_TRUE(snapshot.prompt);
  EXPECT_TRUE(snapshot.prompt_managed);
  EXPECT_FALSE(snapshot.directory_managed);
}
TEST_F(NativeDownloadPreferencesTest, OffTheRecordProfileRefusesChanges) {
  Profile* off_the_record = profile.GetPrimaryOTRProfile(true);
  ASSERT_TRUE(off_the_record);
  DownloadPrefs private_preferences(off_the_record);
  const auto before =
      ReadNativeDownloadPreferences(*off_the_record, private_preferences);
  EXPECT_FALSE(SetNativeDownloadDirectory(
      *off_the_record, private_preferences,
      base::FilePath("/tmp/parc-private-downloads")));
  EXPECT_FALSE(SetNativeDownloadPrompt(*off_the_record, !before.prompt));
  EXPECT_EQ(private_preferences.DownloadPath(), before.directory);
  EXPECT_EQ(private_preferences.PromptForDownload(), before.prompt);
}
TEST_F(NativeDownloadPreferencesTest,
       ReentrantPolicyWinsAndSetterReportsRefusal) {
  ASSERT_TRUE(SetNativeDownloadPrompt(profile, false));
  PrefChangeRegistrar registrar;
  registrar.Init(profile.GetPrefs());
  bool changed = false;
  registrar.Add(prefs::kPromptForDownload, base::BindLambdaForTesting([&] {
                  if (!changed) {
                    changed = true;
                    profile.GetTestingPrefService()->SetManagedPref(
                        prefs::kPromptForDownload, base::Value(false));
                  }
                }));
  EXPECT_FALSE(SetNativeDownloadPrompt(profile, true));
  EXPECT_TRUE(changed);
  EXPECT_FALSE(preferences.PromptForDownload());
  EXPECT_TRUE(
      ReadNativeDownloadPreferences(profile, preferences).prompt_managed);
}
TEST_F(NativeDownloadPreferencesTest, DifferentProfileRetainsItsOwnValues) {
  TestingProfile other;
  DownloadPrefs other_preferences(&other);
  const auto before = ReadNativeDownloadPreferences(other, other_preferences);
  ASSERT_TRUE(SetNativeDownloadDirectory(
      profile, preferences, base::FilePath("/tmp/parc-profile-downloads")));
  ASSERT_TRUE(SetNativeDownloadPrompt(profile, !before.prompt));
  EXPECT_EQ(other_preferences.DownloadPath(), before.directory);
  EXPECT_EQ(other_preferences.PromptForDownload(), before.prompt);
}

}  // namespace
}  // namespace parc
