// Copyright 2026 Parc contributors.

#include "chrome/browser/file_select_helper.h"

#include "chrome/test/base/testing_profile.h"
#include "content/public/test/browser_task_environment.h"
#include "testing/gtest/include/gtest/gtest.h"

class ParcFileSelectHelperTest : public testing::Test {};

TEST_F(ParcFileSelectHelperTest,
       RecognizedMimeDescriptionSurvivesUnknownType) {
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
