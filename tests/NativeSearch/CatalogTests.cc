#include <cstdio>
#include <cstdlib>
#include <set>
#include <string>
#include <string_view>

#include "../../Engine/ParcNative/native_search_catalog.h"

namespace {
int checks = 0;
void Expect(bool value, const char* message) {
  ++checks;
  if (!value) {
    std::fprintf(stderr, "Failed: %s\n", message);
    std::abort();
  }
}
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

int main() {
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
  const std::size_t youtube = IndexOf("youtube.com"), github = IndexOf("github.com");
  Expect(youtube < parc::kSiteSearchCatalog.size() && github < parc::kSiteSearchCatalog.size(),
         "YouTube and GitHub are catalog sites");
  Expect(!parc::IsSiteSearchCatalogGUID("7c6b6a02-3c1f-4b5e-9f0a-1f3a9a0b2c4d"),
         "a hand-added engine such as Kagi is not a catalog site, so it stays the default");
  Expect(!parc::IsSiteSearchCatalogGUID(""), "an engine without a GUID is not a catalog site");

  using parc::SiteSearchHolder;
  const SiteSearchHolder catalog_entry{.same_guid = true, .same_keyword = true};
  const SiteSearchHolder renamed_entry{.same_guid = true};
  const SiteSearchHolder hand_added{.same_keyword = true};
  const SiteSearchHolder activated_from_tab{.same_keyword = true};
  const SiteSearchHolder policy{.same_keyword = true, .policy = true};
  const SiteSearchHolder extension{.normal = false, .same_keyword = true};
  const SiteSearchHolder learned{.same_keyword = true, .replaceable = true, .learned = true};
  const SiteSearchHolder built_in{.same_keyword = true, .replaceable = true};
  Expect(parc::KeepsSiteSearch(catalog_entry) && parc::KeepsSiteSearch(renamed_entry),
         "the catalog entry stays the Space's own even after the user renames its keyword");
  Expect(parc::KeepsSiteSearch(hand_added) && parc::TakesSiteSearchKeyword(hand_added),
         "a hand-added engine on the keyword is the user's and blocks a second copy");
  Expect(parc::KeepsSiteSearch(activated_from_tab), "a learned search entered with Tab becomes the user's");
  Expect(!parc::KeepsSiteSearch(policy) && parc::TakesSiteSearchKeyword(policy),
         "a policy engine blocks the catalog site but its departure is never the user's removal");
  Expect(!parc::KeepsSiteSearch(extension) && !parc::TakesSiteSearchKeyword(extension),
         "an extension keyword neither blocks the catalog site nor counts as a removal when it goes");
  Expect(!parc::KeepsSiteSearch(learned) && !parc::TakesSiteSearchKeyword(learned),
         "a shortcut Chromium learned and keeps inactive gives way, used or not");
  Expect(!parc::KeepsSiteSearch(built_in) && parc::TakesSiteSearchKeyword(built_in),
         "a built-in engine on the keyword blocks the catalog site");

  parc::SiteSearchPresence before = AllKept(), after = AllKept();
  auto change = parc::ClassifySiteSearchRemoval(before, after, 0);
  Expect(!change.removed && !change.reset, "nothing changed, nothing removed");
  change = parc::ClassifySiteSearchRemoval(before, after, 6);
  Expect(!change.removed && !change.reset,
         "Clear browsing data dropping learned shortcuts leaves the catalog record alone");
  after[youtube] = false;
  change = parc::ClassifySiteSearchRemoval(before, after, 1);
  Expect(change.removed == youtube && !change.reset,
         "removing YouTube in the scope menu or Manage search is remembered");
  change = parc::ClassifySiteSearchRemoval(before, after, 0);
  Expect(change.removed == youtube, "renaming the engine that held YouTube's keyword is remembered too");
  change = parc::ClassifySiteSearchRemoval(before, after, 4);
  Expect(!change.removed && change.reset,
         "Reset settings clearing the last catalog site with the shortcuts it learned is a reset");
  after[github] = false;
  change = parc::ClassifySiteSearchRemoval(before, after, 2);
  Expect(!change.removed && change.reset,
         "Reset settings, which clears every added search at once, restores the catalog");

  before = AllKept();
  before[github] = false;
  after = before;
  change = parc::ClassifySiteSearchRemoval(before, after, 0);
  Expect(!change.removed && !change.reset,
         "a site an earlier install skipped is never recorded as removed");
  after[github] = true;
  change = parc::ClassifySiteSearchRemoval(before, after, 1);
  Expect(!change.removed && !change.reset,
         "repairing a skipped site over a learned shortcut records nothing");
  after[youtube] = false;
  change = parc::ClassifySiteSearchRemoval(before, after, 1);
  Expect(change.removed == youtube, "a removal alongside a repair is still remembered");

  std::printf("CatalogTests: %d checks passed\n", checks);
  return 0;
}
