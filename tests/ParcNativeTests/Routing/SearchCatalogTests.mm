#import "ParcNativeTest.h"
#include <cstdio>
#include <cstdlib>
#include <set>
#include <string>
#include <string_view>

#include "native_search_catalog.h"

#define Expect(...) ParcNativeCheckMessage(__FILE__, __LINE__, __VA_ARGS__)
namespace {
constexpr std::size_t IndexOf(std::string_view keyword) {
  for (std::size_t i = 0; i < parc::kSiteSearchCatalog.size(); ++i) {
    if (keyword == parc::kSiteSearchCatalog[i].keyword)
      return i;
  }
  return parc::kSiteSearchCatalog.size();
}
parc::SiteSearchPresence AllKept() {
  parc::SiteSearchPresence kept{};
  kept.fill(true);
  return kept;
}
}

@interface SearchCatalogTests : ParcNativeTestCase
@end

@implementation SearchCatalogTests

- (void)testEveryCatalogSiteIsUniqueAndSearchesOverHTTPS {
  std::set<std::string> guids, keywords;
  for (const auto& site : parc::kSiteSearchCatalog) {
    const std::string url = site.url;
    Expect(guids.insert(site.guid).second, "every catalog site has its own GUID");
    Expect(keywords.insert(site.keyword).second, "every catalog site has its own keyword");
    Expect(std::string_view(site.guid).size() == 36, "catalog GUIDs are full GUIDs");
    Expect(url.starts_with("https://") && url.find("{searchTerms}") != std::string::npos,
           "catalog sites search over HTTPS with the typed words");
    Expect(parc::IsSiteSearchCatalogGUID(site.guid), "each catalog site is recognised");
  }
}

- (void)testOnlyCatalogGUIDsAreCatalogSites {
  Expect(IndexOf("youtube.com") < parc::kSiteSearchCatalog.size() &&
             IndexOf("github.com") < parc::kSiteSearchCatalog.size(),
         "YouTube and GitHub are catalog sites");
  Expect(!parc::IsSiteSearchCatalogGUID("7c6b6a02-3c1f-4b5e-9f0a-1f3a9a0b2c4d"),
         "a hand-added engine such as Kagi is not a catalog site, so it stays the default");
  Expect(!parc::IsSiteSearchCatalogGUID(""), "an engine without a GUID is not a catalog site");
}

- (void)testTheCatalogEntryStaysTheSpacesOwnEvenWhenRenamed {
  const parc::SiteSearchHolder catalog_entry{.same_guid = true, .same_keyword = true};
  const parc::SiteSearchHolder renamed_entry{.same_guid = true};
  Expect(parc::KeepsSiteSearch(catalog_entry) && parc::KeepsSiteSearch(renamed_entry),
         "the catalog entry stays the Space's own even after the user renames its keyword");
}

- (void)testAHandAddedEngineIsTheUsersAndBlocksASecondCopy {
  const parc::SiteSearchHolder hand_added{.same_keyword = true};
  Expect(parc::KeepsSiteSearch(hand_added) && parc::TakesSiteSearchKeyword(hand_added),
         "a hand-added engine on the keyword is the user's and blocks a second copy");
}

- (void)testASearchActivatedWithTabBecomesTheUsers {
  const parc::SiteSearchHolder activated_from_tab{.same_keyword = true};
  Expect(parc::KeepsSiteSearch(activated_from_tab), "a learned search entered with Tab becomes the user's");
}

- (void)testAPolicyEngineBlocksWithoutCountingAsARemoval {
  const parc::SiteSearchHolder policy{.same_keyword = true, .policy = true};
  Expect(!parc::KeepsSiteSearch(policy) && parc::TakesSiteSearchKeyword(policy),
         "a policy engine blocks the catalog site but its departure is never the user's removal");
}

- (void)testAnExtensionKeywordNeitherBlocksNorCounts {
  const parc::SiteSearchHolder extension{.normal = false, .same_keyword = true};
  Expect(!parc::KeepsSiteSearch(extension) && !parc::TakesSiteSearchKeyword(extension),
         "an extension keyword neither blocks the catalog site nor counts as a removal when it goes");
}

- (void)testALearnedInactiveShortcutGivesWay {
  const parc::SiteSearchHolder learned{.same_keyword = true, .replaceable = true, .learned = true};
  Expect(!parc::KeepsSiteSearch(learned) && !parc::TakesSiteSearchKeyword(learned),
         "a shortcut Chromium learned and keeps inactive gives way, used or not");
}

- (void)testABuiltInEngineBlocksTheCatalogSite {
  const parc::SiteSearchHolder built_in{.same_keyword = true, .replaceable = true};
  Expect(!parc::KeepsSiteSearch(built_in) && parc::TakesSiteSearchKeyword(built_in),
         "a built-in engine on the keyword blocks the catalog site");
}

- (void)testUnchangedPresenceRecordsNothing {
  const parc::SiteSearchPresence before = AllKept(), after = AllKept();
  auto change = parc::ClassifySiteSearchRemoval(before, after, 0);
  Expect(!change.removed && !change.reset, "nothing changed, nothing removed");
  change = parc::ClassifySiteSearchRemoval(before, after, 6);
  Expect(!change.removed && !change.reset,
         "Clear browsing data dropping learned shortcuts leaves the catalog record alone");
}

- (void)testRemovingOrRenamingACatalogSiteIsRemembered {
  const std::size_t youtube = IndexOf("youtube.com");
  parc::SiteSearchPresence before = AllKept(), after = AllKept();
  after[youtube] = false;
  auto change = parc::ClassifySiteSearchRemoval(before, after, 1);
  Expect(change.removed == youtube && !change.reset,
         "removing YouTube in the scope menu or Manage search is remembered");
  change = parc::ClassifySiteSearchRemoval(before, after, 0);
  Expect(change.removed == youtube, "renaming the engine that held YouTube's keyword is remembered too");
}

- (void)testResetSettingsIsAResetNotARemoval {
  const std::size_t youtube = IndexOf("youtube.com"), github = IndexOf("github.com");
  parc::SiteSearchPresence before = AllKept(), after = AllKept();
  after[youtube] = false;
  auto change = parc::ClassifySiteSearchRemoval(before, after, 4);
  Expect(!change.removed && change.reset,
         "Reset settings clearing the last catalog site with the shortcuts it learned is a reset");
  after[github] = false;
  change = parc::ClassifySiteSearchRemoval(before, after, 2);
  Expect(!change.removed && change.reset,
         "Reset settings, which clears every added search at once, restores the catalog");
}

- (void)testASkippedSiteIsNeverRecordedAsRemoved {
  parc::SiteSearchPresence before = AllKept();
  before[IndexOf("github.com")] = false;
  const auto change = parc::ClassifySiteSearchRemoval(before, before, 0);
  Expect(!change.removed && !change.reset, "a site an earlier install skipped is never recorded as removed");
}

- (void)testRepairingASkippedSiteRecordsNothing {
  const std::size_t github = IndexOf("github.com");
  parc::SiteSearchPresence before = AllKept();
  before[github] = false;
  parc::SiteSearchPresence after = before;
  after[github] = true;
  const auto change = parc::ClassifySiteSearchRemoval(before, after, 1);
  Expect(!change.removed && !change.reset, "repairing a skipped site over a learned shortcut records nothing");
}

- (void)testARemovalAlongsideARepairIsRemembered {
  const std::size_t youtube = IndexOf("youtube.com"), github = IndexOf("github.com");
  parc::SiteSearchPresence before = AllKept();
  before[github] = false;
  parc::SiteSearchPresence after = before;
  after[github] = true;
  after[youtube] = false;
  const auto change = parc::ClassifySiteSearchRemoval(before, after, 1);
  Expect(change.removed == youtube, "a removal alongside a repair is still remembered");
}

@end
