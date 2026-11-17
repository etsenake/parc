// Copyright 2026 Parc contributors.
#ifndef PARC_NATIVE_NATIVE_SEARCH_CATALOG_H_
#define PARC_NATIVE_NATIVE_SEARCH_CATALOG_H_

#include <array>
#include <cstddef>
#include <optional>
#include <string_view>

namespace parc {

struct SiteSearchDefinition {
  const char* guid;
  const char* name;
  const char* keyword;
  const char* url;
  const char* favicon;
};
inline constexpr auto kSiteSearchCatalog = std::to_array<SiteSearchDefinition>({
    {"0cf7718d-24a6-5801-9c5b-ecfb44277073", "Google Drive", "drive.google.com", "https://drive.google.com/drive/search?q={searchTerms}", "https://drive.google.com/favicon.ico"},
    {"20b37e46-d9c6-533e-91ae-32f6d10458b4", "Gmail", "mail.google.com", "https://mail.google.com/mail/ca/u/0/#apps/{searchTerms}", "https://mail.google.com/favicon.ico"},
    {"167d11c6-3958-5218-8ecc-956dfa6dde80", "Google Maps", "maps.google.com", "https://www.google.com/maps/search/{searchTerms}", "https://www.google.com/images/branding/product/ico/maps15_bnuw3a_32dp.ico"},
    {"2171baf7-023a-5ff0-a340-459ce48ca7b3", "Google Calendar", "calendar.google.com", "https://calendar.google.com/calendar/u/0/r/search?q={searchTerms}", "https://calendar.google.com/googlecalendar/images/favicons_2020q4/calendar_14.ico"},
    {"8ff1e208-73b2-589b-8265-68df764e4d9a", "Google Docs", "docs.google.com", "https://docs.google.com/document/u/0/?q={searchTerms}", "https://ssl.gstatic.com/docs/documents/images/kix-favicon7.ico"},
    {"a41a710c-238d-56ce-b240-ccfa9fb4fa35", "Dropbox", "dropbox.com", "https://www.dropbox.com/search/personal?&query={searchTerms}", "https://cfl.dropboxstatic.com/static/metaserver/static/images/favicon-vfl8lUR9B.ico"},
    {"030ef70f-7e00-5283-bbca-be7b06657bdc", "Amazon", "amazon.com", "https://www.amazon.com/s?k={searchTerms}", "https://www.amazon.com/favicon.ico"},
    {"54d73b34-4280-507f-a3d0-eb316c292788", "GitHub", "github.com", "https://github.com/search?q={searchTerms}", "https://github.com/favicon.ico"},
    {"5bad1bdb-7414-5b7e-9aab-07e73e9bf27e", "Figma", "figma.com", "https://www.figma.com/files/search?q={searchTerms}", "https://static.figma.com/app/icon/1/favicon.png"},
    {"9ef02093-93f8-56d4-851d-c7fdda08ff4f", "X", "x.com", "https://x.com/search?q={searchTerms}", "https://x.com/favicon.ico"},
    {"79380b6e-192f-5003-90e1-431771bb58c0", "X", "twitter.com", "https://twitter.com/search?q={searchTerms}", "https://x.com/favicon.ico"},
    {"64fd37f5-de13-578f-8208-6145c3eca689", "YouTube", "youtube.com", "https://www.youtube.com/results?search_query={searchTerms}", "https://www.youtube.com/s/desktop/9318de79/img/favicon_32x32.png"},
    {"486bf911-81b2-59f5-bf51-313343d54279", "Wikipedia", "wikipedia.org", "https://wikipedia.org/w/index.php?search={searchTerms}", "https://en.wikipedia.org/favicon.ico"},
    {"ea825f65-cce5-534a-8732-1540d4eb8631", "Reddit", "reddit.com", "https://www.reddit.com/search/?q={searchTerms}", "https://reddit.com/favicon.ico"},
    {"85d2c217-155f-5436-a4d5-bd6269548377", "SoundCloud", "soundcloud.com", "https://soundcloud.com/search?q={searchTerms}", "https://soundcloud.com/favicon.ico"},
    {"4fb3b1aa-d1ad-5578-8235-3264cbaf9eeb", "Asana", "asana.com", "https://app.asana.com/0/search?q={searchTerms}", "https://asana.com/favicon.ico"},
    {"906387f3-b0c8-57e7-8531-0f1a6aecb3f7", "LinkedIn", "linkedin.com", "https://linkedin.com/search/results/all/?keywords={searchTerms}", "https://www.linkedin.com/favicon.ico"},
    {"8f9395dc-e84c-56b6-ada1-af1554285442", "Apple Music", "music.apple.com", "https://music.apple.com/us/search?term={searchTerms}", "https://music.apple.com/favicon.ico"},
    {"8bb123a5-6ed4-5338-bfed-568edce910a4", "Spotify", "spotify.com", "https://open.spotify.com/search/{searchTerms}", "https://www.scdn.co/i/_global/favicon.ico"},
});
using SiteSearchPresence = std::array<bool, kSiteSearchCatalog.size()>;

inline bool IsSiteSearchCatalogGUID(std::string_view guid) {
  for (const auto& definition : kSiteSearchCatalog) {
    if (guid == definition.guid)
      return true;
  }
  return false;
}

struct SiteSearchHolder {
  bool normal = true;
  bool same_guid = false;
  bool same_keyword = false;
  bool policy = false;
  bool replaceable = false;
  bool learned = false;
};

inline bool KeepsSiteSearch(const SiteSearchHolder& engine) {
  return engine.normal &&
         (engine.same_guid ||
          (engine.same_keyword && !engine.policy && !engine.replaceable));
}

inline bool TakesSiteSearchKeyword(const SiteSearchHolder& engine) {
  return engine.normal && engine.same_keyword && !engine.learned;
}

struct SiteSearchRemoval {
  std::optional<std::size_t> removed;
  bool reset = false;
};

inline SiteSearchRemoval ClassifySiteSearchRemoval(
    const SiteSearchPresence& before,
    const SiteSearchPresence& after,
    std::size_t engines_removed) {
  std::optional<std::size_t> removed;
  std::size_t count = 0;
  for (std::size_t i = 0; i < before.size(); ++i) {
    if (before[i] && !after[i]) {
      removed = i;
      ++count;
    }
  }
  if (!count)
    return {};
  if (engines_removed > 1)
    return {.reset = true};
  return count == 1 ? SiteSearchRemoval{.removed = removed} : SiteSearchRemoval{};
}

}

#endif
