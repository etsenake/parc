// Copyright 2026 Parc contributors.
#import "native_search.h"
#include "native_search_readiness.h"

#include <map>
#include <memory>
#include <optional>
#include <utility>
#include <vector>

#include "base/check.h"
#include "base/callback_list.h"
#include "native_internal_urls.h"
#include "base/containers/span.h"
#include "base/functional/bind.h"
#include "base/functional/callback_helpers.h"
#include "base/memory/raw_ptr.h"
#include "base/memory/weak_ptr.h"
#include "base/scoped_observation.h"
#include "base/strings/strcat.h"
#include "base/strings/sys_string_conversions.h"
#include "base/strings/utf_string_conversions.h"
#include "base/supports_user_data.h"
#include "base/task/single_thread_task_runner.h"
#include "components/prefs/pref_registry_simple.h"
#include "chrome/browser/autocomplete/autocomplete_classifier_factory.h"
#include "chrome/browser/autocomplete/chrome_autocomplete_provider_client.h"
#include "chrome/browser/autocomplete/chrome_autocomplete_scheme_classifier.h"
#include "chrome/browser/extensions/api/omnibox/omnibox_api.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/profiles/profile_observer.h"
#include "chrome/browser/search_engines/template_url_service_factory.h"
#include "chrome/common/pref_names.h"
#include "chrome/browser/ui/search_engines/keyword_editor_controller.h"
#include "components/omnibox/browser/autocomplete_classifier.h"
#include "components/omnibox/browser/autocomplete_controller.h"
#include "components/omnibox/browser/autocomplete_controller_config.h"
#include "components/omnibox/browser/autocomplete_input.h"
#include "components/omnibox/browser/autocomplete_match.h"
#include "components/omnibox/browser/autocomplete_match_type.h"
#include "components/omnibox/browser/autocomplete_provider.h"
#include "components/omnibox/browser/keyword_provider.h"
#include "components/omnibox/browser/omnibox_field_trial.h"
#include "components/omnibox/browser/omnibox_pref_names.h"
#include "components/prefs/pref_change_registrar.h"
#include "components/prefs/pref_service.h"
#include "components/prefs/scoped_user_pref_update.h"
#include "components/search_engines/search_terms_data.h"
#include "components/search_engines/template_url.h"
#include "components/search_engines/template_url_service.h"
#include "components/search_engines/template_url_service_observer.h"
#include "content/public/browser/navigation_controller.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/weak_document_ptr.h"
#include "content/public/browser/web_contents.h"
#include "content/public/browser/web_contents_observer.h"
#include "extensions/browser/extension_registry.h"
#include "extensions/browser/extension_registry_observer.h"
#include "extensions/browser/extension_util.h"
#include "extensions/browser/event_router.h"
#include "extensions/browser/permissions/active_tab_permission_granter.h"
#include "extensions/common/extension.h"
#include "native_appkit_host.h"
#include "native_profiles.h"
#include "window_security_reservation.h"
#include "native_profile_removal.h"
#include "native_appkit_page.h"
#include "native_page_retirement.h"
#include "services/network/public/cpp/resource_request_body.h"
#include "tab_transfer.h"
#include "third_party/metrics_proto/omnibox_event.pb.h"
#include "ui/base/page_transition_types.h"

NSNotificationName const PCNativeSearchPreferencesDidChangeNotification =
    @"PCNativeSearchPreferencesDidChange";

namespace parc {
namespace {
NSError* SearchError(NSString* message) {
  return [NSError errorWithDomain:@"org.parc.search"
                             code:1
                         userInfo:@{NSLocalizedDescriptionKey : message}];
}
constexpr char kSiteCatalogPreference[] = "parc.search.site_catalog";
struct SiteSearchDefinition {
  const char* guid;
  const char* name;
  const char* keyword;
  const char* url;
  const char* favicon;
};
constexpr SiteSearchDefinition kSiteSearchCatalog[] = {
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
};
bool CanOfferAsDefault(const TemplateURLService& service,
                       const TemplateURL* engine) {
  if (!service.CanMakeDefault(engine) || !service.ShowInDefaultList(engine))
    return false;
  const TemplateURL* winner = service.GetTemplateURLForKeyword(engine->keyword());
  return !winner || winner == engine || !service.ShowInDefaultList(winner);
}
bool IsUnusedLearnedShortcut(const TemplateURLService& service,
                             const TemplateURL& value) {
  return &value != service.GetDefaultSearchProvider() &&
         value.type() == TemplateURL::NORMAL && value.safe_for_autoreplace() &&
         value.usage_count() == 0 &&
         value.prepopulate_id() == 0 && !value.CreatedByPolicy() &&
         value.starter_pack_id() ==
             template_url_starter_pack_data::StarterPackId::kNone &&
         value.is_active() == TemplateURLData::ActiveStatus::kUnspecified;
}
bool SupportsSuggestionDeletion(const AutocompleteMatch& match) {
  if (!match.deletable || !match.provider)
    return false;
  switch (match.type) {
    case omnibox::AutocompleteMatchType::kSearchWhatYouTyped:
    case omnibox::AutocompleteMatchType::kSearchSuggest:
    case omnibox::AutocompleteMatchType::kSearchHistory:
    case omnibox::AutocompleteMatchType::kSearchSuggestEntity:
    case omnibox::AutocompleteMatchType::kHistoryUrl:
    case omnibox::AutocompleteMatchType::kHistoryTitle:
    case omnibox::AutocompleteMatchType::kUrlWhatYouTyped:
    case omnibox::AutocompleteMatchType::kNavsuggest:
    case omnibox::AutocompleteMatchType::kSearchOtherEngine:
    case omnibox::AutocompleteMatchType::kCalculator:
    case omnibox::AutocompleteMatchType::kBookmarkTitle:
      return true;
    default:
      return false;
  }
}
const char kSearchStateKey = 0;
struct NavigationData {
  GURL destination_url;
  ui::PageTransition transition;
  std::optional<TemplateURLRef::PostContent> post_content;
  std::map<std::string, std::string> extra_headers;
  explicit NavigationData(const AutocompleteMatch& match)
      : destination_url(match.destination_url),
        transition(match.transition),
        extra_headers(match.extra_headers) {
    if (match.post_content)
      post_content = *match.post_content;
  }
};
class SearchState final : public base::SupportsUserData::Data,
                          public TemplateURLServiceObserver,
                          public ProfileObserver {
 public:
  explicit SearchState(Profile& profile)
      : profile_(profile.GetWeakPtr()),
        service_(TemplateURLServiceFactory::GetForProfile(&profile)),
        readiness_(base::BindRepeating(&SearchState::InstallSiteCatalog,
                                      base::Unretained(this))) {
    profile.AddObserver(this);
    if (service_) {
      service_->AddObserver(this);
      loaded_subscription_ = service_->RegisterOnLoadedCallback(base::BindOnce(
          &SearchState::Loaded, weak_factory_.GetWeakPtr()));
    }
    prefs_.Init(profile.GetPrefs());
    prefs_.Add(
        omnibox::kKeywordSpaceTriggeringEnabled,
        base::BindRepeating(&SearchState::Changed, weak_factory_.GetWeakPtr()));
    prefs_.Add(
        prefs::kSearchSuggestEnabled,
        base::BindRepeating(&SearchState::Changed, weak_factory_.GetWeakPtr()));
  }
  ~SearchState() override {
    if (profile_)
      profile_->RemoveObserver(this);
    if (service_)
      service_->RemoveObserver(this);
    service_ = nullptr;
    readiness_.Stop();
  }
  void OnProfileWillBeDestroyed(Profile* profile) override {
    profile->RemoveObserver(this);
    profile_.reset();
    if (service_)
      service_->RemoveObserver(this);
    service_ = nullptr;
    prefs_.RemoveAll();
    ++revision_;
    readiness_.Stop();
  }
  static SearchState& Get(Profile& profile) {
    auto* state =
        static_cast<SearchState*>(profile.GetUserData(&kSearchStateKey));
    if (!state) {
      auto owned = std::make_unique<SearchState>(profile);
      state = owned.get();
      profile.SetUserData(&kSearchStateKey, std::move(owned));
    }
    return *state;
  }
  void WhenLoaded(base::OnceClosure callback) {
    readiness_.Add(std::move(callback));
    if (service_ && !service_->loaded()) {
      service_->Load();
    } else {
      readiness_.Schedule();
    }
  }
  void Loaded() { readiness_.Schedule(); }
  void OnTemplateURLServiceChanged() override {
    Changed();
    if (service_ && service_->loaded())
      readiness_.Schedule();
  }
  void OnTemplateURLServiceShuttingDown() override {
    service_->RemoveObserver(this);
    service_ = nullptr;
    prefs_.RemoveAll();
    Changed();
    readiness_.Stop();
  }
  void Changed() {
    ++revision_;
    if (!profile_ || IsNativeProfileRemovalBlocked(profile_->GetOriginalProfile()->GetPath()))
      return;
    NSString* path = base::SysUTF8ToNSString(profile_->GetPath().value());
    dispatch_async(dispatch_get_main_queue(), ^{
      [NSNotificationCenter.defaultCenter
          postNotificationName:PCNativeSearchPreferencesDidChangeNotification
                        object:path];
    });
  }
  TemplateURLService* service() const { return service_; }
  uint64_t revision() const { return revision_; }

 private:
  void InstallSiteCatalog() {
    if (installing_catalog_ || !profile_ || profile_->IsOffTheRecord() ||
        !service_ || !service_->loaded() || service_->is_default_search_managed() ||
        IsNativeProfileRemovalBlocked(profile_->GetPath()))
      return;
    auto* prefs = profile_->GetPrefs();
    if (!prefs->FindPreference(kSiteCatalogPreference))
      return;
    const auto& recorded = prefs->GetDict(kSiteCatalogPreference);
    bool has_unrecorded = false;
    for (const auto& definition : kSiteSearchCatalog)
      has_unrecorded |= !recorded.contains(definition.guid);
    if (!has_unrecorded)
      return;
    installing_catalog_ = true;
    ScopedDictPrefUpdate installed(prefs, kSiteCatalogPreference);
    for (const auto& definition : kSiteSearchCatalog) {
      if (installed->contains(definition.guid))
        continue;
      bool existing = false;
      for (const TemplateURL* value : service_->GetTemplateURLs()) {
        if (value->sync_guid() == definition.guid ||
            (value->keyword() == base::UTF8ToUTF16(definition.keyword) &&
             !IsUnusedLearnedShortcut(*service_, *value))) {
          existing = true;
          break;
        }
      }
      if (!existing) {
        TemplateURLData data;
        data.sync_guid = definition.guid;
        data.SetShortName(base::UTF8ToUTF16(definition.name));
        data.SetKeyword(base::UTF8ToUTF16(definition.keyword));
        data.SetURL(definition.url);
        data.favicon_url = GURL(definition.favicon);
        data.safe_for_autoreplace = false;
        data.is_active = TemplateURLData::ActiveStatus::kTrue;
        if (!service_->Add(std::make_unique<TemplateURL>(data)))
          continue;
      }
      installed->Set(definition.guid, true);
    }
    installing_catalog_ = false;
  }
  base::WeakPtr<Profile> profile_;
  raw_ptr<TemplateURLService> service_;
  PrefChangeRegistrar prefs_;
  bool installing_catalog_ = false;
  uint64_t revision_ = 1;
  NativeSearchReadiness readiness_;
  base::CallbackListSubscription loaded_subscription_;
  base::WeakPtrFactory<SearchState> weak_factory_{this};
};
}
void RegisterNativeSearchPreferences(PrefRegistrySimple& registrar) {
  registrar.RegisterDictionaryPref(kSiteCatalogPreference);
}
void InitializeNativeSearch(Profile& profile) {
  if (!profile.IsOffTheRecord())
    SearchState::Get(profile).WhenLoaded(base::DoNothing());
}
}

@interface PCNativeSearchEngine ()
- (instancetype)initWithTemplate:(const TemplateURL&)value
                         service:(TemplateURLService&)service;
@end
@implementation PCNativeSearchEngine
@synthesize identifier = _identifier;
@synthesize name = _name;
@synthesize keyword = _keyword;
@synthesize canMakeDefault = _canMakeDefault;
- (instancetype)initWithTemplate:(const TemplateURL&)value
                         service:(TemplateURLService&)service {
  self = [super init];
  if (self) {
    _identifier = [base::SysUTF8ToNSString(value.sync_guid()) copy];
    _name =
        [base::SysUTF16ToNSString(value.AdjustedShortNameForLocaleDirection())
            copy];
    _keyword = [base::SysUTF16ToNSString(value.keyword()) copy];
    _canMakeDefault = service.CanMakeDefault(&value);
  }
  return self;
}
@end

@interface PCNativeSearchPreferences () {
 @public
  base::WeakPtr<Profile> _profile;
}
- (instancetype)initWithProfile:(Profile&)profile;
@end
@implementation PCNativeSearchPreferences
@synthesize profilePath = _profilePath;
@synthesize revision = _revision;
@synthesize engines = _engines;
@synthesize defaultIdentifier = _defaultIdentifier;
@synthesize defaultEditable = _defaultEditable;
@synthesize defaultManaged = _defaultManaged;
@synthesize defaultExtensionControlled = _defaultExtensionControlled;
@synthesize suggestionsEnabled = _suggestionsEnabled;
@synthesize suggestionsEditable = _suggestionsEditable;
@synthesize suggestionsManaged = _suggestionsManaged;
- (instancetype)initWithProfile:(Profile&)profile {
  self = [super init];
  if (self) {
    _profile = profile.GetWeakPtr();
    _profilePath = [base::SysUTF8ToNSString(profile.GetPath().value()) copy];
    auto& state = parc::SearchState::Get(profile);
    auto& service = *state.service();
    _revision = state.revision();
    _defaultManaged = service.is_default_search_managed();
    _defaultExtensionControlled = service.IsExtensionControlledDefaultSearch();
    _defaultEditable = service.CanDefaultSearchProviderBeModifiedByUser();
    const auto* current = service.GetDefaultSearchProvider();
    _defaultIdentifier =
        current ? [base::SysUTF8ToNSString(current->sync_guid()) copy] : nil;
    NSMutableArray* engines = [NSMutableArray array];
    for (const TemplateURL* engine : service.GetTemplateURLs()) {
      if (engine == current || parc::CanOfferAsDefault(service, engine)) {
        [engines
            addObject:[[PCNativeSearchEngine alloc] initWithTemplate:*engine
                                                             service:service]];
      }
    }
    _engines = [engines copy];
    auto* pref =
        profile.GetPrefs()->FindPreference(prefs::kSearchSuggestEnabled);
    _suggestionsEnabled =
        profile.GetPrefs()->GetBoolean(prefs::kSearchSuggestEnabled);
    _suggestionsEditable = pref && pref->IsUserModifiable();
    _suggestionsManaged = pref && pref->IsManaged();
  }
  return self;
}
@end

@interface PCNativeSearchNavigation () {
 @public
  base::WeakPtr<Profile> _profile;
  std::unique_ptr<parc::NavigationData> _match;
  BOOL _consumed;
}
- (instancetype)initWithProfile:(Profile&)profile
                          match:(const AutocompleteMatch&)match;
- (PCNativeSearchNavigation*)requestForRepeatedOpen;
@property(nonatomic, readwrite, copy, nullable) NSString* inlineCompletionText;
@end
@implementation PCNativeSearchNavigation
- (PCNativeSearchNavigation*)requestForRepeatedOpen {
  PCNativeSearchNavigation* copy = [[PCNativeSearchNavigation alloc] init];
  copy->_profile = _profile;
  copy->_match = _match ? std::make_unique<parc::NavigationData>(*_match) : nullptr;
  copy->_profilePath = _profilePath;
  copy->_revision = _revision;
  copy->_URL = _URL; copy->_title = _title; copy->_detail = _detail;
  copy->_search = _search; copy->_editText = _editText;
  copy->_canCompleteWithTab = _canCompleteWithTab;
  copy->_inlineCompletionText = _inlineCompletionText;
  copy->_matchType = _matchType; copy->_relevance = _relevance;
  return copy;
}
@synthesize profilePath = _profilePath;
@synthesize revision = _revision;
@synthesize URL = _URL;
@synthesize title = _title;
@synthesize detail = _detail;
@synthesize search = _search;
@synthesize editText = _editText;
@synthesize inlineCompletionText = _inlineCompletionText;
@synthesize canCompleteWithTab = _canCompleteWithTab;
@synthesize matchType = _matchType;
@synthesize relevance = _relevance;
- (instancetype)initWithProfile:(Profile&)profile
                          match:(const AutocompleteMatch&)match {
  self = [super init];
  if (self) {
    _profile = profile.GetWeakPtr();
    _match = std::make_unique<parc::NavigationData>(match);
    _profilePath = [base::SysUTF8ToNSString(profile.GetPath().value()) copy];
    _revision = parc::SearchState::Get(profile).revision();
    _URL = [NSURL
        URLWithString:base::SysUTF8ToNSString(parc::PublicInternalURL(match.destination_url).spec())];
    _title = [base::SysUTF16ToNSString(match.contents) copy];
    _detail = [base::SysUTF16ToNSString(match.description) copy];
    _search = AutocompleteMatch::IsSearchType(match.type);
    _editText = [base::SysUTF16ToNSString(match.fill_into_edit) copy];
    _matchType = [base::SysUTF8ToNSString(omnibox::AutocompleteMatchTypeToString(match.type)) copy];
    _relevance = match.relevance;
    switch (match.type) {
      case omnibox::AutocompleteMatchType::kSearchWhatYouTyped:
      case omnibox::AutocompleteMatchType::kSearchSuggest:
      case omnibox::AutocompleteMatchType::kSearchSuggestEntity:
      case omnibox::AutocompleteMatchType::kSearchSuggestTail:
      case omnibox::AutocompleteMatchType::kSearchSuggestPersonalized:
      case omnibox::AutocompleteMatchType::kSearchSuggestProfile:
      case omnibox::AutocompleteMatchType::kCalculator:
        _canCompleteWithTab = !_editText.length ? NO : YES;
        break;
      default:
        _canCompleteWithTab = NO;
        break;
    }
    if (!_search) {
      const GURL edit(base::UTF16ToUTF8(match.fill_into_edit));
      if (edit.is_valid() && edit.SchemeIs("chrome"))
        _editText = [base::SysUTF8ToNSString(parc::PublicInternalURL(edit).spec()) copy];
    }
    if (!_search) {
      const GURL label(base::UTF16ToUTF8(match.contents));
      const GURL detail(base::UTF16ToUTF8(match.description));
      if (label.is_valid() && label.SchemeIs("chrome"))
        _title = base::SysUTF8ToNSString(parc::PublicInternalURL(label).spec());
      if (detail.is_valid() && detail.SchemeIs("chrome"))
        _detail = base::SysUTF8ToNSString(parc::PublicInternalURL(detail).spec());
    }
  }
  return self;
}
@end

namespace parc {
namespace {
void WithSearchProfile(
    NSString* path,
    PCNativePage* page,
    base::OnceCallback<void(Profile*, parc::NativeProfileLeasePtr, NSError*)>
        callback, PCNativeBrowserWindow* window = nil) {
  if (window.isPrivateBrowsing) {
    Profile* profile = NativePrivateProfileForWindow(window, path);
    auto* contents = page ? ContentsForNativePage(page) : nullptr;
    if (!profile || (page && (!contents || page.isClosed ||
        [PCNativeBrowserApplication ownerForPage:page] != window ||
        Profile::FromBrowserContext(contents->GetBrowserContext()) != profile))) {
      std::move(callback).Run(nullptr, nullptr, SearchError(@"The original private search window closed."));
      return;
    }
    std::move(callback).Run(profile, NativeLeaseForProfile(*profile), nil);
    return;
  }
  if (!page) {
    WithNativeProfile(path, std::move(callback));
    return;
  }
  auto* contents = ContentsForNativePage(page);
  if (!contents || page.isClosed || ![page.profilePath isEqual:path] ||
      ![PCNativeBrowserApplication ownerForPage:page].window) {
    std::move(callback).Run(
        nullptr, nullptr, SearchError(@"The originating page is unavailable."));
    return;
  }
  std::move(callback).Run(
      Profile::FromBrowserContext(contents->GetBrowserContext()),
      NativeLeaseForProfile(*Profile::FromBrowserContext(contents->GetBrowserContext())), nil);
}
void SearchPreferences(NSString* path,
                       PCNativePage* page,
                       void (^completion)(PCNativeSearchPreferences*,
                                          NSError*), PCNativeBrowserWindow* window = nil);
PCNativeSearchPreferences* Snapshot(Profile* profile) {
  if (!profile || IsNativeProfileRemovalBlocked(profile->GetOriginalProfile()->GetPath()))
    return nil;
  auto* service = SearchState::Get(*profile).service();
  return service && service->loaded()
             ? [[PCNativeSearchPreferences alloc] initWithProfile:*profile]
             : nil;
}
Profile* Validate(PCNativeSearchPreferences* snapshot, NSError** error) {
  Profile* profile = snapshot ? snapshot->_profile.get() : nullptr;
  if (profile && !IsNativeProfileRemovalBlocked(profile->GetOriginalProfile()->GetPath())) {
    auto& state = SearchState::Get(*profile);
    if (state.service() && state.service()->loaded() &&
        state.revision() == snapshot.revision)
      return profile;
  }
  if (error)
    *error = SearchError(
        @"These search settings changed. Review the updated choices.");
  return nullptr;
}
bool NavigationValid(PCNativeSearchNavigation* request, Profile* profile) {
  return request && !request->_consumed && profile &&
         !IsNativeProfileRemovalBlocked(profile->GetOriginalProfile()->GetPath()) &&
         request->_profile.get() == profile && request->_match &&
         request->_match->destination_url.is_valid() &&
         !IsNativeAppDocumentURL(request->_match->destination_url) &&
         !request->_match->destination_url.SchemeIs("arc") &&
         SearchState::Get(*profile).service() &&
         SearchState::Get(*profile).revision() == request.revision;
}
}
}

namespace parc {
namespace {
void SearchPreferences(NSString* path,
                       PCNativePage* page,
                       void (^completion)(PCNativeSearchPreferences*,
                                          NSError*), PCNativeBrowserWindow* window) {
  parc::WithSearchProfile(
      path, page,
      base::BindOnce(^(Profile* profile, parc::NativeProfileLeasePtr context,
                       NSError* error) {
        if (!profile || !context) {
          completion(nil, error ?: SearchError(@"The search Profile is closing."));
          return;
        }
        auto weak = profile->GetWeakPtr();
        __weak PCNativeBrowserWindow* originalWindow = window;
        const BOOL isPrivate = window.isPrivateBrowsing;
        parc::SearchState::Get(*profile).WhenLoaded(base::BindOnce(^{
          auto lease = context;
          if (!lease || lease->profile() != weak.get()) {
            completion(nil, SearchError(@"The search Profile closed.")); return;
          }
          if (isPrivate && NativePrivateProfileForWindow(originalWindow, path) != weak.get()) {
            completion(nil, SearchError(@"The original private search window closed.")); return;
          }
          auto* snapshot = parc::Snapshot(weak.get());
          completion(
              snapshot,
              snapshot
                  ? nil
                  : parc::SearchError(
                        @"Search settings are unavailable for this profile."));
        }));
      }), window);
}
}
Profile* ProfileForSearchNavigation(PCNativeSearchNavigation* request) {
  Profile* profile = request ? request->_profile.get() : nullptr;
  return NavigationValid(request, profile) ? profile : nullptr;
}
}

@implementation PCNativeBrowserApplication (Search)
+ (void)searchPreferencesForProfilePath:(NSString*)path
                             completion:(void (^)(PCNativeSearchPreferences*,
                                                  NSError*))completion {
  parc::SearchPreferences(path, nil, completion);
}
+ (PCNativeSearchPreferences*)setDefaultSearchEngine:(NSString*)identifier
                                      forPreferences:
                                          (PCNativeSearchPreferences*)snapshot
                                               error:(NSError**)error {
  CHECK(NSThread.isMainThread);
  auto* profile = parc::Validate(snapshot, error);
  if (!profile)
    return nil;
  auto* service = parc::SearchState::Get(*profile).service();
  auto* engine =
      service->GetTemplateURLForGUID(base::SysNSStringToUTF8(identifier));
  if (!engine || !parc::CanOfferAsDefault(*service, engine)) {
    if (error)
      *error = parc::SearchError(
          @"This search engine cannot be selected as the default.");
    return nil;
  }
  auto context = parc::NativeLeaseForProfile(*profile);
  if (!context) {
    if (error)
      *error = parc::SearchError(@"This profile is closing.");
    return nil;
  }
  auto weak = profile->GetWeakPtr();
  service->SetUserSelectedDefaultSearchProvider(engine);
  return parc::Snapshot(weak.get());
}
+ (PCNativeSearchPreferences*)
    setSearchSuggestionsEnabled:(BOOL)enabled
                 forPreferences:(PCNativeSearchPreferences*)snapshot
                          error:(NSError**)error {
  CHECK(NSThread.isMainThread);
  auto* profile = parc::Validate(snapshot, error);
  if (!profile)
    return nil;
  const auto* pref =
      profile->GetPrefs()->FindPreference(prefs::kSearchSuggestEnabled);
  if (!pref || !pref->IsUserModifiable()) {
    if (error)
      *error = parc::SearchError(
          @"Search suggestions are controlled for this profile.");
    return nil;
  }
  auto context = parc::NativeLeaseForProfile(*profile);
  if (!context) {
    if (error)
      *error = parc::SearchError(@"This profile is closing.");
    return nil;
  }
  auto weak = profile->GetWeakPtr();
  profile->GetPrefs()->SetBoolean(prefs::kSearchSuggestEnabled, enabled);
  return parc::Snapshot(weak.get());
}
+ (void)resolveSearchInput:(NSString*)input
               profilePath:(NSString*)path
                      page:(PCNativePage*)page
                completion:
                    (void (^)(PCNativeSearchNavigation*, NSError*))completion {
  [self resolveSearchInput:input profilePath:path page:page window:nil completion:completion];
}
+ (void)resolveSearchInput:(NSString*)input profilePath:(NSString*)path
                      page:(PCNativePage*)page window:(PCNativeBrowserWindow*)window
                completion:(void (^)(PCNativeSearchNavigation*, NSError*))completion {
  NSString* text = [input
      stringByTrimmingCharactersInSet:NSCharacterSet
                                          .whitespaceAndNewlineCharacterSet];
  const GURL requested(base::SysNSStringToUTF8(text));
  if (!text.length || parc::IsNativeAppDocumentURL(requested) || requested.SchemeIs("arc")) {
    completion(nil, parc::SearchError(@"Enter a web address or search."));
    return;
  }
  parc::SearchPreferences(
      path, page, ^(PCNativeSearchPreferences* snapshot, NSError* error) {
        Profile* profile = snapshot ? snapshot->_profile.get() : nullptr;
        if (!profile) {
          completion(nil, error);
          return;
        }
        auto* classifier =
            AutocompleteClassifierFactory::GetForProfile(profile);
        if (!classifier) {
          completion(nil, parc::SearchError(@"Search is unavailable "
                                            @"for this profile."));
          return;
        }
        AutocompleteMatch match;
        classifier->Classify(base::SysNSStringToUTF16(text), false, true,
                             metrics::OmniboxEventProto::OTHER, &match,
                             nullptr);
        const TemplateURL* selected_template = match.GetTemplateURL(
            parc::SearchState::Get(*profile).service());
        PCNativeSearchNavigation* request =
            match.destination_url.is_valid() &&
                    (!selected_template || selected_template->type() != TemplateURL::OMNIBOX_API_EXTENSION)
                ? [[PCNativeSearchNavigation alloc] initWithProfile:*profile
                                                              match:match]
                : nil;
        completion(request,
                   request ? nil
                           : parc::SearchError(@"This input has no available "
                                               @"navigation result."));
      }, window);
}
@end

@implementation PCNativePage (Search)
- (BOOL)loadSearchNavigation:(PCNativeSearchNavigation*)request {
  CHECK(NSThread.isMainThread);
  auto* contents = parc::ContentsForNativePage(self);
  auto* profile =
      contents ? Profile::FromBrowserContext(contents->GetBrowserContext())
               : nullptr;
  auto* owner = [PCNativeBrowserApplication ownerForPage:self];
  if (self.isClosed || !owner.window || parc::IsNativePageRetiring(self) ||
      parc::IsLiveTabTransferTarget(contents) ||
      !parc::NavigationValid(request, profile))
    return NO;
  const auto& match = *request->_match;
  content::NavigationController::LoadURLParams params(match.destination_url);
  params.transition_type = ui::PageTransitionFromInt(
      match.transition | ui::PAGE_TRANSITION_FROM_ADDRESS_BAR);
  params.has_user_gesture = true;
  for (const auto& header : match.extra_headers) {
    base::StrAppend(&params.extra_headers,
                    {header.first, ": ", header.second, "\r\n"});
  }
  if (match.post_content) {
    params.load_type = content::NavigationController::LOAD_TYPE_HTTP_POST;
    params.post_data = network::ResourceRequestBody::CreateFromCopyOfBytes(
        base::as_byte_span(match.post_content->second));
    base::StrAppend(&params.extra_headers,
                    {"Content-Type: ", match.post_content->first, "\r\n"});
  }
  request->_consumed = YES;
  contents->GetController().LoadURLWithParams(params);
  return YES;
}
@end

@implementation PCNativeBrowserWindow (Search)
- (void)openBackgroundSearchNavigation:(PCNativeSearchNavigation*)request
    sourcePage:(PCNativePage*)sourcePage container:(NSView*)container validateOwner:(BOOL (^)(void))validateOwner
    completion:(void (^)(PCNativePage*, NSError*))completion {
  CHECK(NSThread.isMainThread);
  CHECK(completion);
  if (!validateOwner || !validateOwner() ||
      !parc::NavigationValid(request, request ? request->_profile.get() : nullptr)) {
    completion(nil, parc::SearchError(@"The search result or original owner changed."));
    return;
  }
  __weak PCNativePage* weak_source = sourcePage;
  __weak PCNativeBrowserWindow* weak_owner = self;
  const bool has_source = sourcePage != nil;
  auto* source_contents = parc::ContentsForNativePage(sourcePage);
  const auto document = source_contents ? source_contents->GetPrimaryMainFrame()->GetWeakDocumentPtr()
                                        : content::WeakDocumentPtr();
  BOOL (^original)(void) = ^BOOL {
    PCNativeBrowserWindow* owner = weak_owner;
    PCNativePage* source = weak_source;
    if (!owner.window || !validateOwner()) return NO;
    if (!has_source) return YES;
    auto* frame = document.AsRenderFrameHostIfValid();
    auto* contents = parc::ContentsForNativePage(source);
    return source && !source.isClosed && contents && frame &&
        contents->GetPrimaryMainFrame() == frame &&
        [PCNativeBrowserApplication ownerForPage:source] == owner &&
        Profile::FromBrowserContext(contents->GetBrowserContext()) == request->_profile.get() &&
        !parc::IsNativePageRetiring(source) && !parc::IsLiveTabTransferTarget(contents);
  };
  if (!original()) { completion(nil, parc::SearchError(@"The original document changed.")); return; }
  PCNativeSearchNavigation* operation = [request requestForRepeatedOpen];
  [self openBackgroundURL:[NSURL URLWithString:@"about:blank"]
      profilePath:operation.profilePath container:container searchNavigation:operation
      validateOwner:original completion:^(PCNativePage* page, NSError* error) {
        if (!page) { completion(nil, error); return; }
        if (!original() || ![page loadSearchNavigation:operation]) {
          [page requestClose:^(PCNativePageCloseResult result) {}];
          completion(nil, parc::SearchError(@"The search owner changed before navigation."));
          return;
        }
        completion(page, nil);
      }];
}
- (void)openSearchNavigation:(PCNativeSearchNavigation*)request
                   container:(NSView*)container
                  completion:(void (^)(PCNativePage*, NSError*))completion {
  if (!request || !parc::NavigationValid(request, request->_profile.get())) {
    completion(nil,
               parc::SearchError(@"The search result is no longer current."));
    return;
  }
  [self openURL:[NSURL URLWithString:@"about:blank"]
           profilePath:request.profilePath
             container:container
      searchNavigation:request
            completion:^(PCNativePage* page, NSError* error) {
              if (!page) {
                completion(nil, error);
                return;
              }
              if (![page loadSearchNavigation:request]) {
                [page requestClose:^(PCNativePageCloseResult result){
                }];
                completion(nil,
                           parc::SearchError(@"The search result changed "
                                             @"before its page was ready."));
                return;
              }
              completion(page, nil);
            }];
}
@end

@interface PCNativeOmniboxExtensionAction () {
 @public
  scoped_refptr<const extensions::Extension> _extension;
  std::u16string _keyword;
  std::string _content;
  BOOL _consumed;
}
- (instancetype)initWithExtension:(const extensions::Extension*)extension
                            match:(const AutocompleteMatch&)match
                            index:(NSUInteger)index;
@end
@implementation PCNativeOmniboxExtensionAction
@synthesize identifier = _identifier;
@synthesize extensionID = _extensionID;
@synthesize title = _title;
@synthesize detail = _detail;
@synthesize editText = _editText;
@synthesize resultIndex = _resultIndex;
- (instancetype)initWithExtension:(const extensions::Extension*)extension
                            match:(const AutocompleteMatch&)match
                            index:(NSUInteger)index {
  self = [super init];
  if (self) {
    _identifier = [NSUUID.UUID.UUIDString copy];
    _extension = extension;
    _extensionID = [base::SysUTF8ToNSString(extension->id()) copy];
    _keyword = match.keyword;
    std::u16string remaining;
    AutocompleteInput::SplitKeywordFromInput(match.fill_into_edit, true, &remaining);
    _content = base::UTF16ToUTF8(remaining);
    _editText = [base::SysUTF16ToNSString(remaining) copy];
    _title = [base::SysUTF16ToNSString(match.contents) copy];
    if (!_title.length) _title = _editText;
    _detail = [base::SysUTF8ToNSString(extension->name()) copy];
    _resultIndex = index;
  }
  return self;
}
@end

@interface PCNativeOmniboxScope () {
 @public
  std::string _engineGUID;
  std::string _extensionID;
  scoped_refptr<const extensions::Extension> _extensionOwner;
  uint64_t _preferencesRevision;
}
@property(nonatomic, strong, readwrite) PCNativeOmniboxExtensionAction* extensionAction;
- (instancetype)initWithTemplate:(const TemplateURL&)value
                       revision:(uint64_t)revision
            preferencesRevision:(uint64_t)preferencesRevision
            spaceTriggerEnabled:(BOOL)spaceTriggerEnabled
                         result:(PCNativeSearchNavigation*)result;
@end
@implementation PCNativeOmniboxScope
@synthesize identifier = _identifier;
@synthesize name = _name;
@synthesize keyword = _keyword;
@synthesize revision = _revision;
@synthesize result = _result;
@synthesize extensionAction = _extensionAction;
@synthesize extension = _extension;
@synthesize spaceTriggerEnabled = _spaceTriggerEnabled;
@synthesize templateURL = _templateURL;
@synthesize searchHost = _searchHost;
@synthesize prepopulated = _prepopulated;
- (instancetype)initWithTemplate:(const TemplateURL&)value
                       revision:(uint64_t)revision
            preferencesRevision:(uint64_t)preferencesRevision
            spaceTriggerEnabled:(BOOL)spaceTriggerEnabled
                         result:(PCNativeSearchNavigation*)result {
  self = [super init];
  if (self) {
    _identifier = [NSUUID.UUID.UUIDString copy];
    _name = [base::SysUTF16ToNSString(value.short_name()) copy];
    _keyword = [base::SysUTF16ToNSString(value.keyword()) copy];
    _revision = revision;
    _result = result;
    _engineGUID = value.sync_guid();
    _extension = value.type() == TemplateURL::OMNIBOX_API_EXTENSION;
    if (_extension) _extensionID = value.GetExtensionId();
    _preferencesRevision = preferencesRevision;
    _spaceTriggerEnabled = spaceTriggerEnabled;
    _templateURL = [base::SysUTF8ToNSString(value.url()) copy];
    _searchHost = [base::SysUTF8ToNSString(value.GenerateSearchURL(SearchTermsData(), u"").host()) copy];
    _prepopulated = value.prepopulate_id() > 0;
  }
  return self;
}
@end

@interface PCNativeOmniboxScopeMenu ()
- (instancetype)initWithActive:(PCNativeOmniboxScope*)active
                       choices:(NSArray<PCNativeOmniboxScope*>*)choices
                     canRemove:(BOOL)canRemove confirmation:(BOOL)confirmation
                     canManage:(BOOL)canManage;
@end
@implementation PCNativeOmniboxScopeMenu
@synthesize activeScope = _activeScope;
@synthesize choices = _choices;
@synthesize canRemove = _canRemove;
@synthesize requiresRemovalConfirmation = _requiresRemovalConfirmation;
@synthesize canManage = _canManage;
- (instancetype)initWithActive:(PCNativeOmniboxScope*)active
                       choices:(NSArray<PCNativeOmniboxScope*>*)choices
                     canRemove:(BOOL)canRemove confirmation:(BOOL)confirmation
                     canManage:(BOOL)canManage {
  self = [super init];
  if (self) {
    _activeScope = active;
    _choices = [choices copy];
    _canRemove = canRemove;
    _requiresRemovalConfirmation = confirmation;
    _canManage = canManage;
  }
  return self;
}
@end

@interface PCNativeOmniboxSnapshot ()
@property(nonatomic, strong, readwrite) PCNativeOmniboxScope* offeredScope;
@property(nonatomic, copy, readwrite) NSArray<PCNativeOmniboxExtensionAction*>* extensionActions;
@property(nonatomic, copy, readwrite) NSArray<PCNativeOmniboxScope*>* siteScopes;
- (instancetype)initWithRevision:(uint64_t)revision
                          input:(NSString*)input
                        results:(NSArray<PCNativeSearchNavigation*>*)results
                         offers:(NSArray<PCNativeOmniboxScope*>*)offers
                         active:(PCNativeOmniboxScope*)active
                          error:(NSError*)error;
@end
@implementation PCNativeOmniboxSnapshot
@synthesize revision = _revision;
@synthesize input = _input;
@synthesize results = _results;
@synthesize extensionActions = _extensionActions;
@synthesize scopeOffers = _scopeOffers;
@synthesize siteScopes = _siteScopes;
@synthesize offeredScope = _offeredScope;
@synthesize activeScope = _activeScope;
@synthesize error = _error;
- (instancetype)initWithRevision:(uint64_t)revision
                          input:(NSString*)input
                        results:(NSArray<PCNativeSearchNavigation*>*)results
                         offers:(NSArray<PCNativeOmniboxScope*>*)offers
                         active:(PCNativeOmniboxScope*)active
                          error:(NSError*)error {
  self = [super init];
  if (self) {
    _revision = revision;
    _input = [input copy];
    _results = [results copy];
    _extensionActions = @[];
    _scopeOffers = [offers copy];
    _siteScopes = @[];
    for (PCNativeOmniboxScope* offer in offers) {
      if (offer.result == results.firstObject) {
        _offeredScope = offer;
        break;
      }
    }
    _activeScope = active;
    _error = error;
  }
  return self;
}
@end

namespace parc {
class OmniboxSession final : public AutocompleteController::Observer,
                             public ProfileObserver,
                             public TemplateURLServiceObserver,
                             public content::WebContentsObserver,
                             public extensions::ExtensionRegistryObserver {
 public:
  OmniboxSession(Profile& profile, PCNativePage* page,
                 PCNativeBrowserWindow* window, void (^changed)(PCNativeOmniboxSnapshot*))
      : content::WebContentsObserver(ContentsForNativePage(page)),
        profile_(profile.GetWeakPtr()),
        origin_page_(page),
        origin_owner_(page ? [PCNativeBrowserApplication ownerForPage:page] : window),
        origin_document_(web_contents() ? web_contents()->GetPrimaryMainFrame()->GetWeakDocumentPtr()
                                        : content::WeakDocumentPtr()),
        has_origin_page_(page != nil),
        changed_([changed copy]),
        service_(SearchState::Get(profile).service()),
        preferences_revision_(SearchState::Get(profile).revision()) {
    profile.AddObserver(this);
    registry_observation_.Observe(extensions::ExtensionRegistry::Get(&profile));
    if (service_)
      service_->AddObserver(this);
    AutocompleteControllerConfig config;
    config.provider_types =
        static_cast<int>(AutocompleteProvider::Type::kSearch |
                         AutocompleteProvider::Type::kHistoryUrl |
                         AutocompleteProvider::Type::kHistoryQuick |
                         AutocompleteProvider::Type::kBookmark |
                         AutocompleteProvider::Type::kBuiltin |
                         AutocompleteProvider::Type::kKeyword |
                         AutocompleteProvider::Type::kShortcuts) |
        (OmniboxFieldTrial::IsOnDeviceHeadSuggestEnabledForAnyMode()
             ? static_cast<int>(AutocompleteProvider::Type::kOnDeviceHead)
             : 0);
    controller_ = std::make_unique<AutocompleteController>(
        std::make_unique<ChromeAutocompleteProviderClient>(&profile), config);
    controller_->AddObserver(this);
  }
  ~OmniboxSession() override {
    registry_observation_.Reset();
    weak_factory_.InvalidateWeakPtrs();
    if (profile_)
      profile_->RemoveObserver(this);
    DetachService();
    ResetController();
  }
  void OnProfileWillBeDestroyed(Profile* profile) override {
    registry_observation_.Reset();
    profile->RemoveObserver(this);
    profile_.reset();
    DetachService();
    Fail(@"This search profile is no longer available.", true);
  }
  void OnExtensionUnloaded(content::BrowserContext*, const extensions::Extension* extension,
                           extensions::UnloadedExtensionReason) override {
    bool affected = active_ && active_->_extensionOwner.get() == extension;
    for (PCNativeOmniboxExtensionAction* action in extension_actions_)
      affected = affected || action->_extension.get() == extension;
    if (!affected) return;
    accepting_results_ = false;
    RevokeExtensionActions();
    offers_ = @[];
    ++generation_;
    auto weak = weak_factory_.GetWeakPtr();
    dispatch_async(dispatch_get_main_queue(), ^{
      if (weak) weak->Fail(@"This search extension is no longer available.", false);
    });
  }
  void OnShutdown(extensions::ExtensionRegistry*) override {
    registry_observation_.Reset();
  }
  bool HasActiveScope() const { return active_ != nil; }
  void PrimaryPageChanged(content::Page&) override {
    accepting_results_ = false;
    RevokeExtensionActions();
    offers_ = @[];
    ++generation_;
    auto weak = weak_factory_.GetWeakPtr();
    dispatch_async(dispatch_get_main_queue(), ^{
      if (weak) weak->Fail(@"The original search page changed. Open search again.", true);
    });
  }
  void WebContentsDestroyed() override {
    Observe(nullptr);
    Fail(@"The original search page was closed.", true);
  }
  void OnTemplateURLServiceShuttingDown() override {
    DetachService();
    Fail(@"Search engines are no longer available.", true);
  }
  void OnTemplateURLServiceChanged() override {
    if (scope_invalidated_)
      return;
    menu_ = nil;
    RevokeDeletions();
    RevokeExtensionActions();
    offers_ = @[];
    ++revision_;
    ++generation_;
    const bool scoped = active_ != nil;
    active_ = nil;
    invalidated_scope_ = invalidated_scope_ || scoped;
    auto weak = weak_factory_.GetWeakPtr();
    dispatch_async(dispatch_get_main_queue(), ^{
      if (weak)
        weak->PreferencesChanged();
    });
  }
  void PreferencesChanged() {
    if (!Available()) {
      Fail(@"This search session is no longer available.", true);
      return;
    }
    const auto current = SearchState::Get(*profile_).revision();
    if (scope_invalidated_) {
      preferences_revision_ = current;
      return;
    }
    if (invalidated_scope_ || (active_ && current != preferences_revision_)) {
      invalidated_scope_ = false;
      preferences_revision_ = current;
      Fail(@"The search engine changed. Choose a search scope again.", false);
      return;
    }
    if (current != preferences_revision_) {
      preferences_revision_ = current;
      Query(input_, allows_inline_completion_);
    }
  }
  void Query(NSString* text, bool allows_inline_completion = false) {
    menu_ = nil;
    allows_inline_completion_ = allows_inline_completion;
    scope_invalidated_ = false;
    RevokeDeletions();
    RevokeExtensionActions();
    input_ = [text copy];
    ++generation_;
    ++revision_;
    offers_ = @[];
    if (!Available()) {
      Fail(@"This search session is no longer available.", true);
      return;
    }
    if (invalidated_scope_ || (active_ && !Resolve(active_))) {
      invalidated_scope_ = false;
      Fail(@"The search engine changed. Choose a search scope again.", false);
      return;
    }
    preferences_revision_ = SearchState::Get(*profile_).revision();
    const bool continues = started_ && input_.length && active_ == started_scope_ &&
        preferences_revision_ == started_preferences_revision_;
    accepting_results_ = false;
    if (!active_.isExtension && !continues) {
      controller_->Stop(AutocompleteStopReason::kClobbered);
      started_ = false;
    }
    if (!input_.length && !active_.isExtension) {
      Publish(@[], @[], nil);
      return;
    }
    std::u16string text_value = base::SysNSStringToUTF16(input_);
    if (active_)
      text_value = base::SysNSStringToUTF16(active_.keyword) + u" " + text_value;
    AutocompleteInput input(text_value, metrics::OmniboxEventProto::OTHER,
                            ChromeAutocompleteSchemeClassifier(profile_.get()));
    input.set_prevent_inline_autocomplete(!allows_inline_completion_ || active_);
    const TemplateURL* input_template = controller_->keyword_provider()->GetTemplateUrlForText(text_value, service_);
    input.set_allow_exact_keyword_match(active_ != nil || !input_template ||
        input_template->type() != TemplateURL::OMNIBOX_API_EXTENSION);
    input.set_in_keyword_mode(active_ != nil);
    accepting_results_ = true;
    started_ = true;
    started_scope_ = active_;
    started_preferences_revision_ = preferences_revision_;
    controller_->Start(input);
  }
  bool Enter(PCNativeOmniboxScope* offer) {
    if (!Available() || active_ || !offer ||
        (offer.revision != revision_ && [site_scopes_ indexOfObjectIdenticalTo:offer] == NSNotFound) ||
        [offers_ indexOfObjectIdenticalTo:offer] == NSNotFound)
      return false;
    const auto* value = Resolve(offer);
    if (!value)
      return false;
    active_ = Scope(*value, revision_ + 2, nil, nil);
    Query(@"");
    return active_ != nil;
  }
  bool Leave() {
    if (!active_)
      return false;
    active_ = nil;
    invalidated_scope_ = false;
    Query(@"");
    return true;
  }
  PCNativeOmniboxScopeMenu* ScopeMenu() {
    if (!CanSubmit() || !origin_owner_.client ||
        [origin_owner_.client selectedNativePage] != origin_page_ ||
        !active_ || active_.isExtension || !Resolve(active_))
      return nil;
    NSMutableArray<PCNativeOmniboxScope*>* choices = [NSMutableArray array];
    for (const TemplateURL* value : service_->GetTemplateURLs()) {
      if (WebsiteTemplate(value->keyword()) != value ||
          value->sync_guid() == active_->_engineGUID)
        continue;
      [choices addObject:[[PCNativeOmniboxScope alloc]
          initWithTemplate:*value revision:revision_
          preferencesRevision:preferences_revision_
          spaceTriggerEnabled:profile_->GetPrefs()->GetBoolean(omnibox::kKeywordSpaceTriggeringEnabled)
          result:nil]];
    }
    KeywordEditorController editor(profile_.get());
    const TemplateURL* value = Resolve(active_);
    const bool regular = !profile_->IsOffTheRecord();
    menu_ = [[PCNativeOmniboxScopeMenu alloc] initWithActive:active_ choices:choices
        canRemove:regular && editor.CanRemove(value)
        confirmation:editor.ShouldConfirmRemoval(value) canManage:regular];
    menu_generation_ = generation_;
    return menu_;
  }
  bool CanUseScopeMenu(PCNativeOmniboxScopeMenu* menu) const {
    return menu && menu == menu_ && menu_generation_ == generation_ &&
        CanSubmit() && origin_owner_.client &&
        [origin_owner_.client selectedNativePage] == origin_page_ &&
        active_ == menu.activeScope && Resolve(active_);
  }
  bool ChangeScope(PCNativeOmniboxScope* choice, PCNativeOmniboxScopeMenu* menu) {
    if (!CanUseScopeMenu(menu) ||
        [menu.choices indexOfObjectIdenticalTo:choice] == NSNotFound)
      return false;
    const TemplateURL* value = Resolve(choice);
    if (!value)
      return false;
    active_ = [[PCNativeOmniboxScope alloc] initWithTemplate:*value
        revision:revision_ + 2 preferencesRevision:preferences_revision_
        spaceTriggerEnabled:choice.spaceTriggerEnabled result:nil];
    Query(input_);
    return active_ != nil;
  }
  bool RemoveScope(PCNativeOmniboxScopeMenu* menu, bool confirmed) {
    if (!CanUseScopeMenu(menu) || profile_->IsOffTheRecord())
      return false;
    KeywordEditorController editor(profile_.get());
    const TemplateURL* value = Resolve(active_);
    if (!value || !editor.CanRemove(value) ||
        (editor.ShouldConfirmRemoval(value) && !confirmed))
      return false;
    const auto id = value->id();
    menu_ = nil;
    active_ = nil;
    offers_ = @[];
    RevokeDeletions();
    RevokeExtensionActions();
    accepting_results_ = false;
    controller_->Stop(AutocompleteStopReason::kInteraction);
    editor.RemoveTemplateURL(id);
    invalidated_scope_ = false;
    preferences_revision_ = SearchState::Get(*profile_).revision();
    Query(@"");
    return true;
  }
  bool CanSubmit() const {
    return Available() && origin_owner_.window && !invalidated_scope_ && !scope_invalidated_ &&
        (!has_origin_page_ || origin_document_.AsRenderFrameHostIfValid()) &&
        SearchState::Get(*profile_).revision() == preferences_revision_;
  }
  bool CanExecuteExtension(PCNativeOmniboxExtensionAction* action) const {
    if (!action || action->_consumed || !ExtensionOwnerValid() ||
        !accepting_results_ || delivered_revision_ != revision_ ||
        extension_revision_ != revision_ ||
        [extension_actions_ indexOfObjectIdenticalTo:action] == NSNotFound)
      return false;
    return ExtensionForTemplate(service_->GetTemplateURLForKeyword(action->_keyword)) ==
        action->_extension.get();
  }
  bool ExecuteExtension(PCNativeOmniboxExtensionAction* action,
                        PCNativeOmniboxExtensionDisposition disposition) {
    if (!CanExecuteExtension(action)) return false;
    WindowOpenDisposition native_disposition;
    switch (disposition) {
      case PCNativeOmniboxExtensionDispositionCurrentTab:
        native_disposition = WindowOpenDisposition::CURRENT_TAB; break;
      case PCNativeOmniboxExtensionDispositionNewForegroundTab:
        native_disposition = WindowOpenDisposition::NEW_FOREGROUND_TAB; break;
      case PCNativeOmniboxExtensionDispositionNewBackgroundTab:
        native_disposition = WindowOpenDisposition::NEW_BACKGROUND_TAB; break;
      default: return false;
    }
    if (!ExtensionPresentationValid()) return false;
    const std::string extension_id = action->_extension->id();
    const std::string content = action->_content;
    action->_consumed = YES;
    accepting_results_ = false;
    ++generation_;
    offers_ = @[];
    RevokeDeletions();
    RevokeExtensionActions();
    auto weak = weak_factory_.GetWeakPtr();
    extensions::ExtensionOmniboxEventRouter::OnInputEntered(
        web_contents(), extension_id, content, native_disposition);
    if (weak && weak->controller_) {
      weak->controller_->Stop(AutocompleteStopReason::kInteraction);
      if (disposition == PCNativeOmniboxExtensionDispositionNewBackgroundTab)
        weak->Query(weak->input_);
      else
        weak->Publish(@[], @[], nil);
    }
    return true;
  }
  bool CanDeleteExtension(PCNativeOmniboxExtensionAction* action) const {
    if (!CanExecuteExtension(action)) return false;
    const auto index = [extension_actions_ indexOfObjectIdenticalTo:action];
    return index < extension_matches_.size() && extension_matches_[index].deletable;
  }
  bool DeleteExtension(PCNativeOmniboxExtensionAction* action) {
    if (!CanDeleteExtension(action) || !ExtensionPresentationValid()) return false;
    const auto index = [extension_actions_ indexOfObjectIdenticalTo:action];
    AutocompleteMatch match = extension_matches_[index];
    match.contents = base::UTF8ToUTF16(action->_content);
    action->_consumed = YES;
    ++generation_;
    offers_ = @[];
    RevokeExtensionActions();
    RevokeDeletions();
    controller_->DeleteMatch(match);
    return true;
  }
  bool CanDelete(PCNativeSearchNavigation* result) const {
    if (!result || result->_consumed || !Available() || !accepting_results_ ||
        invalidated_scope_ || scope_invalidated_ || !origin_owner_.window ||
        (has_origin_page_ && !origin_document_.AsRenderFrameHostIfValid()) ||
        deletion_revision_ != revision_ || delivered_revision_ != revision_ ||
        SearchState::Get(*profile_).revision() != preferences_revision_)
      return false;
    const auto index = [deletion_results_ indexOfObjectIdenticalTo:result];
    return index != NSNotFound && index < deletion_matches_.size() &&
           SupportsSuggestionDeletion(deletion_matches_[index]);
  }
  bool Delete(PCNativeSearchNavigation* result) {
    if (!CanDelete(result))
      return false;
    const auto index = [deletion_results_ indexOfObjectIdenticalTo:result];
    AutocompleteMatch match = deletion_matches_[index];
    RevokeDeletions();
    RevokeExtensionActions();
    ++generation_;
    offers_ = @[];
    accepting_results_ = false;
    controller_->Stop(AutocompleteStopReason::kInteraction);
    result->_consumed = YES;
    accepting_results_ = true;
    controller_->DeleteMatch(match);
    return true;
  }
  void OnResultChanged(AutocompleteController* controller, bool) override {
    if (!accepting_results_ || !Available() || controller != controller_.get() ||
        invalidated_scope_ || (!input_.length && !active_.isExtension))
      return;
    if (SearchState::Get(*profile_).revision() != preferences_revision_ ||
        (active_ && !Resolve(active_))) {
      return;
    }
    RevokeDeletions();
    RevokeExtensionActions();
    NSMutableArray<PCNativeSearchNavigation*>* deletable = [NSMutableArray array];
    NSMutableArray<PCNativeSearchNavigation*>* values = [NSMutableArray array];
    NSMutableArray<PCNativeOmniboxExtensionAction*>* actions = [NSMutableArray array];
    NSMutableArray<PCNativeOmniboxScope*>* offers = [NSMutableArray array];
    const uint64_t publication = revision_ + 1;
    for (const auto& match : controller->result()) {
      if (!match.destination_url.is_valid() || IsNativeAppDocumentURL(match.destination_url) || match.destination_url.SchemeIs("arc"))
        continue;
      if (active_ &&
          (!match.IsExplicitlyInvokedKeyword(service_) ||
           match.keyword != base::SysNSStringToUTF16(active_.keyword)))
        continue;
      const TemplateURL* match_template = match.GetTemplateURL(service_);
      if (match_template && match_template->type() == TemplateURL::OMNIBOX_API_EXTENSION) {
        const auto* extension = ExtensionForTemplate(match_template);
        if (extension && ExtensionOwnerValid()) {
          PCNativeOmniboxExtensionAction* action = [[PCNativeOmniboxExtensionAction alloc]
              initWithExtension:extension match:match index:values.count + actions.count];
          [actions addObject:action];
          extension_matches_.push_back(match);
          if (!active_)
            [offers addObject:Scope(*match_template, publication, nil, action)];
        }
      } else {
        PCNativeSearchNavigation* navigation = [[PCNativeSearchNavigation alloc]
            initWithProfile:*profile_ match:match];
        if (allows_inline_completion_ && !active_ &&
            &match == controller->result().default_match() &&
            match.allowed_to_be_default_match && !match.inline_autocompletion.empty()) {
          navigation.inlineCompletionText = [input_ stringByAppendingString:
              base::SysUTF16ToNSString(match.inline_autocompletion)];
        }
        [values addObject:navigation];
        if (SupportsSuggestionDeletion(match)) {
          [deletable addObject:navigation];
          deletion_matches_.push_back(match);
        }
        if (!active_) {
          KeywordState state = KeywordState::kNone;
          std::u16string keyword, placeholder;
          match.GetKeywordUiState(service_, false, &state, &keyword, &placeholder);
          if (state == KeywordState::kHint) {
            const auto* value = ScopeTemplate(keyword);
            if (value)
              [offers addObject:Scope(*value, publication, navigation, nil)];
          }
        }
      }
      if (values.count + actions.count == 8)
        break;
    }
    extension_actions_ = [actions copy];
    extension_revision_ = publication;
    deletion_results_ = [deletable copy];
    deletion_revision_ = publication;
    Publish(values, offers, nil);
  }

 private:
  void RevokeExtensionActions() {
    extension_actions_ = @[];
    extension_matches_.clear();
    extension_revision_ = 0;
  }
  bool ExtensionPresentationValid() const {
    NSWindow* window = origin_owner_.window;
    NSWindow* key = NSApp.keyWindow;
    while (key && key != window) key = key.parentWindow;
    return NSApp.active && window.visible && !window.miniaturized && key &&
        !window.attachedSheet && !PCNativeWindowHasSecurityReservation(window);
  }
  bool ExtensionOwnerValid() const {
    return CanSubmit() && has_origin_page_ && origin_owner_.client &&
        [origin_owner_.client selectedNativePage] == origin_page_ &&
        origin_page_.nativeView.window == origin_owner_.window &&
        extensions::ActiveTabPermissionGranter::FromWebContents(web_contents()) &&
        extensions::EventRouter::Get(profile_.get());
  }
  const extensions::Extension* ExtensionForTemplate(const TemplateURL* value) const {
    if (!value || value->type() != TemplateURL::OMNIBOX_API_EXTENSION || !profile_)
      return nullptr;
    const auto* extension = extensions::ExtensionRegistry::Get(profile_.get())
        ->enabled_extensions().GetByID(value->GetExtensionId());
    return extension && (!profile_->IsOffTheRecord() ||
        extensions::util::IsIncognitoEnabled(extension->id(), profile_.get())) ? extension : nullptr;
  }
  const TemplateURL* ScopeTemplate(const std::u16string& keyword) const {
    if (!controller_ || !controller_->keyword_provider()) return nullptr;
    const auto* value = controller_->keyword_provider()->GetTemplateUrlForText(keyword, service_);
    if (value && value->type() == TemplateURL::OMNIBOX_API_EXTENSION)
      return ExtensionOwnerValid() && ExtensionForTemplate(value) ? value : nullptr;
    return WebsiteTemplate(keyword);
  }
  PCNativeOmniboxScope* Scope(const TemplateURL& value, uint64_t revision,
                            PCNativeSearchNavigation* navigation,
                            PCNativeOmniboxExtensionAction* action) const {
    auto* token = [[PCNativeOmniboxScope alloc] initWithTemplate:value revision:revision
        preferencesRevision:preferences_revision_
        spaceTriggerEnabled:profile_->GetPrefs()->GetBoolean(omnibox::kKeywordSpaceTriggeringEnabled)
        result:navigation];
    token.extensionAction = action;
    if (token.isExtension) token->_extensionOwner = ExtensionForTemplate(&value);
    return token;
  }
  void RevokeDeletions() {
    deletion_results_ = @[];
    deletion_matches_.clear();
    deletion_revision_ = 0;
  }
  bool Available() const {
    if (!profile_ || !controller_ || !service_ || !service_->loaded() ||
        IsNativeProfileRemovalBlocked(profile_->GetOriginalProfile()->GetPath()))
      return false;
    if (!has_origin_page_)
      return true;
    PCNativePage* page = origin_page_;
    PCNativeBrowserWindow* owner = origin_owner_;
    return page && !page.isClosed && owner.window && web_contents() &&
           ContentsForNativePage(page) == web_contents() &&
           [PCNativeBrowserApplication ownerForPage:page] == owner &&
           Profile::FromBrowserContext(web_contents()->GetBrowserContext()) == profile_.get() &&
           !IsNativePageRetiring(page) && !IsLiveTabTransferTarget(web_contents());
  }
  const TemplateURL* WebsiteTemplate(const std::u16string& keyword) const {
    if (!controller_->keyword_provider())
      return nullptr;
    const auto* value = controller_->keyword_provider()->GetTemplateUrlForText(keyword, service_);
    return value && value->type() != TemplateURL::OMNIBOX_API_EXTENSION &&
                   value->starter_pack_id() == template_url_starter_pack_data::StarterPackId::kNone &&
                   !value->sync_guid().empty()
               ? value : nullptr;
  }
  const TemplateURL* Resolve(PCNativeOmniboxScope* token) const {
    if (!token || token->_preferencesRevision != SearchState::Get(*profile_).revision())
      return nullptr;
    const auto* value = ScopeTemplate(base::SysNSStringToUTF16(token.keyword));
    if (token.isExtension)
      return value && value->type() == TemplateURL::OMNIBOX_API_EXTENSION &&
          value->GetExtensionId() == token->_extensionID &&
          ExtensionForTemplate(value) == token->_extensionOwner.get() ? value : nullptr;
    return value && value->type() != TemplateURL::OMNIBOX_API_EXTENSION &&
        value->sync_guid() == token->_engineGUID ? value : nullptr;
  }
  NSArray<PCNativeOmniboxScope*>* SiteScopes(uint64_t publication) {
    if (active_ || !controller_ || !service_ || !service_->loaded())
      return @[];
    if (preferences_revision_ != SearchState::Get(*profile_).revision())
      return @[];
    if (site_scopes_revision_ == preferences_revision_)
      return site_scopes_;
    NSMutableArray<PCNativeOmniboxScope*>* scopes = [NSMutableArray array];
    for (const TemplateURL* value : service_->GetTemplateURLs()) {
      if (value->CanBeUsedForKeywordMatching() && WebsiteTemplate(value->keyword()) == value)
        [scopes addObject:Scope(*value, publication, nil, nil)];
    }
    site_scopes_ = [scopes copy];
    site_scopes_revision_ = preferences_revision_;
    return site_scopes_;
  }
  void Publish(NSArray<PCNativeSearchNavigation*>* values,
               NSArray<PCNativeOmniboxScope*>* offers, NSError* error) {
    NSArray<PCNativeOmniboxScope*>* site_scopes = values.count ? SiteScopes(revision_ + 1) : @[];
    offers_ = [offers arrayByAddingObjectsFromArray:site_scopes];
    PCNativeOmniboxSnapshot* snapshot = [[PCNativeOmniboxSnapshot alloc]
        initWithRevision:++revision_ input:input_ results:values offers:offers
        active:active_ error:error];
    snapshot.extensionActions = extension_actions_;
    snapshot.siteScopes = site_scopes;
    snapshot.offeredScope = nil;
    const bool extension_first = extension_actions_.count && extension_actions_.firstObject.resultIndex == 0;
    for (PCNativeOmniboxScope* offer in offers_) {
      if ((extension_first && offer.extensionAction == extension_actions_.firstObject) ||
          (!extension_first && offer.result && offer.result == values.firstObject)) {
        snapshot.offeredScope = offer;
        break;
      }
    }
    auto weak = weak_factory_.GetWeakPtr();
    const auto generation = generation_;
    const auto preferences_revision = preferences_revision_;
    dispatch_async(dispatch_get_main_queue(), ^{
      if (!weak || weak->generation_ != generation ||
          weak->revision_ != snapshot.revision)
        return;
      if (!snapshot.error && !weak->Available()) {
        weak->Fail(@"This search session is no longer available.", true);
        return;
      }
      if (!snapshot.error && SearchState::Get(*weak->profile_).revision() !=
                                 preferences_revision) {
        weak->PreferencesChanged();
        return;
      }
      weak->delivered_revision_ = snapshot.revision;
      weak->changed_(snapshot);
    });
  }
  void Fail(NSString* message, bool terminal) {
    menu_ = nil;
    RevokeDeletions();
    RevokeExtensionActions();
    if (!terminal)
      scope_invalidated_ = true;
    accepting_results_ = false;
    ++generation_;
    active_ = nil;
    offers_ = @[];
    if (terminal)
      ResetController();
    else if (controller_)
      controller_->Stop(AutocompleteStopReason::kClobbered);
    started_ = false;
    Publish(@[], @[], SearchError(message));
  }
  void DetachService() {
    if (service_)
      service_->RemoveObserver(this);
    service_ = nullptr;
  }
  void ResetController() {
    RevokeDeletions();
    RevokeExtensionActions();
    if (controller_) {
      controller_->RemoveObserver(this);
      controller_->Stop(AutocompleteStopReason::kClobbered);
      controller_.reset();
    }
  }
  base::WeakPtr<Profile> profile_;
  __weak PCNativePage* origin_page_;
  __weak PCNativeBrowserWindow* origin_owner_;
  const content::WeakDocumentPtr origin_document_;
  base::ScopedObservation<extensions::ExtensionRegistry, extensions::ExtensionRegistryObserver>
      registry_observation_{this};
  NSArray<PCNativeOmniboxExtensionAction*>* extension_actions_ = @[];
  std::vector<AutocompleteMatch> extension_matches_;
  uint64_t extension_revision_ = 0;
  NSArray<PCNativeSearchNavigation*>* deletion_results_ = @[];
  std::vector<AutocompleteMatch> deletion_matches_;
  uint64_t deletion_revision_ = 0;
  uint64_t delivered_revision_ = 0;
  const bool has_origin_page_;
  void (^changed_)(PCNativeOmniboxSnapshot*);
  raw_ptr<TemplateURLService> service_;
  std::unique_ptr<AutocompleteController> controller_;
  NSString* input_ = @"";
  NSArray<PCNativeOmniboxScope*>* offers_ = @[];
  NSArray<PCNativeOmniboxScope*>* site_scopes_ = @[];
  uint64_t site_scopes_revision_ = UINT64_MAX;
  PCNativeOmniboxScope* active_ = nil;
  bool started_ = false;
  PCNativeOmniboxScope* started_scope_ = nil;
  uint64_t started_preferences_revision_ = 0;
  PCNativeOmniboxScopeMenu* menu_ = nil;
  uint64_t menu_generation_ = 0;
  bool invalidated_scope_ = false;
  bool scope_invalidated_ = false;
  bool accepting_results_ = false;
  uint64_t preferences_revision_;
  uint64_t generation_ = 0;
  bool allows_inline_completion_ = false;
  uint64_t revision_ = 0;
  base::WeakPtrFactory<OmniboxSession> weak_factory_{this};
};
}

@implementation PCNativeOmnibox {
  std::unique_ptr<parc::OmniboxSession> _session;
  NSString* _profilePath;
  NSString* _query;
  BOOL _cancelled;
  BOOL _allowsInlineCompletion;
  id _preferencesObserver;
}
@synthesize resultsChanged = _resultsChanged;
@synthesize snapshotChanged = _snapshotChanged;
- (instancetype)initWithProfilePath:(NSString*)path page:(PCNativePage*)page {
  return [self initWithProfilePath:path page:page window:nil];
}
- (instancetype)initWithProfilePath:(NSString*)path page:(PCNativePage*)page window:(PCNativeBrowserWindow*)window {
  self = [super init];
  if (self) {
    _profilePath = [path copy];
    _query = @"";
    __weak PCNativeOmnibox* weak = self;
    __weak PCNativePage* originPage = page;
    __weak PCNativeBrowserWindow* originOwner = [PCNativeBrowserApplication ownerForPage:page];
    const BOOL hasOriginPage = page != nil;
    auto* initial_contents = parc::ContentsForNativePage(page);
    const content::WeakDocumentPtr initial_document = initial_contents
        ? initial_contents->GetPrimaryMainFrame()->GetWeakDocumentPtr()
        : content::WeakDocumentPtr();
    _preferencesObserver = [NSNotificationCenter.defaultCenter
        addObserverForName:PCNativeSearchPreferencesDidChangeNotification
                    object:nil queue:NSOperationQueue.mainQueue
                usingBlock:^(NSNotification* notification) {
                  PCNativeOmnibox* current = weak;
                  if (current && !current->_cancelled && current->_session &&
                      [notification.object isEqual:current->_profilePath])
                    current->_session->PreferencesChanged();
                }];
    parc::SearchPreferences(
        path, page, ^(PCNativeSearchPreferences* snapshot, NSError* error) {
          PCNativeOmnibox* current = weak;
          if (!current || current->_cancelled)
            return;
          Profile* profile = snapshot ? snapshot->_profile.get() : nullptr;
          PCNativePage* original = originPage;
          auto* contents = original ? parc::ContentsForNativePage(original) : nullptr;
          if (hasOriginPage && (!original || original.isClosed || !contents ||
              initial_document.AsRenderFrameHostIfValid() != contents->GetPrimaryMainFrame() ||
              !originOwner.window || [PCNativeBrowserApplication ownerForPage:original] != originOwner ||
              Profile::FromBrowserContext(contents->GetBrowserContext()) != profile ||
              parc::IsNativePageRetiring(original) || parc::IsLiveTabTransferTarget(contents))) {
            profile = nullptr;
            error = parc::SearchError(@"The original search page is no longer available.");
          }
          if (!profile) {
            NSError* failure = error ?: parc::SearchError(@"Search is unavailable.");
            dispatch_async(dispatch_get_main_queue(), ^{
              PCNativeOmnibox* owner = weak;
              if (!owner || owner->_cancelled)
                return;
              if (owner.snapshotChanged) {
                owner.snapshotChanged([[PCNativeOmniboxSnapshot alloc]
                    initWithRevision:1 input:owner->_query results:@[] offers:@[]
                    active:nil error:failure]);
              } else if (owner.resultsChanged) {
                owner.resultsChanged(@[], failure);
              }
            });
            return;
          }
          current->_session = std::make_unique<parc::OmniboxSession>(
              *profile, original, window, ^(PCNativeOmniboxSnapshot* result) {
                PCNativeOmnibox* owner = weak;
                if (!owner || owner->_cancelled)
                  return;
                if (owner.snapshotChanged)
                  owner.snapshotChanged(result);
                else if (owner.resultsChanged)
                  owner.resultsChanged(result.results, result.error);
              });
          current->_session->Query(current->_query, current->_allowsInlineCompletion);
        }, window);
  }
  return self;
}
- (void)updateInput:(NSString*)input {
  [self updateInput:input allowsInlineCompletion:NO];
}
- (void)updateInput:(NSString*)input allowsInlineCompletion:(BOOL)allowed {
  CHECK(NSThread.isMainThread);
  if (_cancelled)
    return;
  _allowsInlineCompletion = allowed;
  _query = _session && _session->HasActiveScope() ? [input copy] :
      [[input stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] copy];
  if (_session)
    _session->Query(_query, _allowsInlineCompletion);
}
- (BOOL)enterScope:(PCNativeOmniboxScope*)offer {
  CHECK(NSThread.isMainThread);
  if (_cancelled || !_session || !_session->Enter(offer))
    return NO;
  _query = @"";
  return YES;
}
- (BOOL)leaveScope {
  CHECK(NSThread.isMainThread);
  if (_cancelled || !_session || !_session->Leave())
    return NO;
  _query = @"";
  return YES;
}
- (PCNativeOmniboxScopeMenu*)scopeMenu {
  CHECK(NSThread.isMainThread);
  return !_cancelled && _session ? _session->ScopeMenu() : nil;
}
- (BOOL)canUseScopeMenu:(PCNativeOmniboxScopeMenu*)menu {
  CHECK(NSThread.isMainThread);
  return !_cancelled && _session && _session->CanUseScopeMenu(menu);
}
- (BOOL)changeScope:(PCNativeOmniboxScope*)scope menu:(PCNativeOmniboxScopeMenu*)menu {
  CHECK(NSThread.isMainThread);
  return !_cancelled && _session && _session->ChangeScope(scope, menu);
}
- (BOOL)removeScope:(PCNativeOmniboxScopeMenu*)menu confirmed:(BOOL)confirmed {
  CHECK(NSThread.isMainThread);
  if (_cancelled || !_session || !_session->RemoveScope(menu, confirmed))
    return NO;
  _query = @"";
  return YES;
}
- (BOOL)canSubmit {
  CHECK(NSThread.isMainThread);
  return !_cancelled && _session && _session->CanSubmit();
}
- (BOOL)canExecuteExtensionAction:(PCNativeOmniboxExtensionAction*)action {
  CHECK(NSThread.isMainThread);
  return !_cancelled && _session && _session->CanExecuteExtension(action);
}
- (BOOL)executeExtensionAction:(PCNativeOmniboxExtensionAction*)action
                 disposition:(PCNativeOmniboxExtensionDisposition)disposition {
  CHECK(NSThread.isMainThread);
  return !_cancelled && _session && _session->ExecuteExtension(action, disposition);
}
- (BOOL)canDeleteExtensionAction:(PCNativeOmniboxExtensionAction*)action {
  CHECK(NSThread.isMainThread);
  return !_cancelled && _session && _session->CanDeleteExtension(action);
}
- (BOOL)deleteExtensionAction:(PCNativeOmniboxExtensionAction*)action {
  CHECK(NSThread.isMainThread);
  return !_cancelled && _session && _session->DeleteExtension(action);
}
- (BOOL)canDeleteResult:(PCNativeSearchNavigation*)result {
  CHECK(NSThread.isMainThread);
  return !_cancelled && _session && _session->CanDelete(result);
}
- (BOOL)deleteResult:(PCNativeSearchNavigation*)result {
  CHECK(NSThread.isMainThread);
  return !_cancelled && _session && _session->Delete(result);
}
- (void)cancel {
  CHECK(NSThread.isMainThread);
  _cancelled = YES;
  _session.reset();
  self.resultsChanged = nil;
  self.snapshotChanged = nil;
  if (_preferencesObserver) {
    [NSNotificationCenter.defaultCenter removeObserver:_preferencesObserver];
    _preferencesObserver = nil;
  }
}
- (void)dealloc {
  if (_preferencesObserver)
    [NSNotificationCenter.defaultCenter removeObserver:_preferencesObserver];
}
@end
