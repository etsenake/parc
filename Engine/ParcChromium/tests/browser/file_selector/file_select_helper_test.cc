// Copyright 2026 Parc contributors.

#include "chrome/browser/file_select_helper.h"
#include "base/functional/bind.h"
#include "base/functional/callback_helpers.h"
#include "parc/native/native_file_types.h"

#include "chrome/test/base/testing_profile.h"
#include "content/public/test/browser_task_environment.h"
#include "testing/gtest/include/gtest/gtest.h"

class ParcFileSelectHelperTest : public testing::Test {};

TEST_F(ParcFileSelectHelperTest,
       RecognizedMimeDescriptionSurvivesUnknownType) {
  parc_hooks::SetFileTypeInfoFactory(&parc::NativeFileTypesFromAcceptType);
  base::ScopedClosureRunner reset(base::BindOnce([] {
    parc_hooks::SetFileTypeInfoFactory(nullptr);
  }));
  content::BrowserTaskEnvironment task_environment;
  TestingProfile profile;
  scoped_refptr<FileSelectHelper> file_select_helper =
      new FileSelectHelper(&profile);

  auto image_only =
      file_select_helper->GetFileTypesFromAcceptType({u"image/*"});
  auto with_unknown = file_select_helper->GetFileTypesFromAcceptType(
      {u"image/*", u"application/x-parc-unmapped-type"});

  ASSERT_EQ(1u, image_only->extension_description_overrides.size());
  ASSERT_EQ(1u, with_unknown->extension_description_overrides.size());
  EXPECT_FALSE(image_only->extension_description_overrides.front().empty());
  EXPECT_EQ(image_only->extension_description_overrides.front(),
            with_unknown->extension_description_overrides.front());
}

TEST_F(ParcFileSelectHelperTest, CombinedAndIndividualFilters) {
  auto info = parc::NativeFileTypesFromAcceptType(
      {u".mp4", u".斤拷锟", u".🔥", u".png"});
  ASSERT_EQ(5u, info->extensions.size());
  EXPECT_EQ((std::vector<base::FilePath::StringType>{"mp4", "斤拷锟", "🔥", "png"}),
            info->extensions[0]);
  EXPECT_EQ((std::vector<base::FilePath::StringType>{"mp4"}), info->extensions[1]);
  EXPECT_EQ((std::vector<base::FilePath::StringType>{"斤拷锟"}), info->extensions[2]);
  EXPECT_EQ((std::vector<base::FilePath::StringType>{"🔥"}), info->extensions[3]);
  EXPECT_EQ((std::vector<base::FilePath::StringType>{"png"}), info->extensions[4]);
  EXPECT_TRUE(info->include_all_files);
  EXPECT_EQ(5u, info->extension_description_overrides.size());
}
