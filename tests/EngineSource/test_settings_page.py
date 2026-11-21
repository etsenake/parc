import importlib.util
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[2]
VALUES = REPO / 'Engine/ParcChromium/parc_settings_page.cc'
POLICY = REPO / 'Engine/ParcNative/native_startup_policy.h'
PATCH = REPO / 'Engine/ParcHost/integration/native-settings-visibility.patch'
spec = importlib.util.spec_from_file_location(
    'settings_page_contract', REPO / 'Engine/ParcChromium/settings_page_contract.py')
contract = importlib.util.module_from_spec(spec)
spec.loader.exec_module(contract)

CHILD_VIEW_HOSTS = ('settings-autofill-page-index',)
PAGE_VISIBILITY = """import {loadTimeData} from './i18n_setup.js';
export interface PageVisibility {
  ai?: boolean;
  appearance?: boolean|AppearancePageVisibility;
  onStartup?: boolean;
  people?: boolean;
  privacy?: boolean|PrivacyPageVisibility;
}
export interface AppearancePageVisibility {
  bookmarksBar: boolean;
  homeButton: boolean;
  hoverCard: boolean;
  pageZoom: boolean;
  setTheme: boolean;
  sidePanel: boolean;
}
export interface PrivacyPageVisibility {
  networkPrediction: boolean;
  searchPrediction: boolean;
}
function createPageVisibility(): PageVisibility|undefined {
  if (!loadTimeData.getBoolean('isGuest')) {
    return undefined;
  }
}
"""
ROUTES = """const visibility = pageVisibility || {};
if (visibility.people !== false) {}
if (visibility.ai !== false && loadTimeData.getBoolean('showAiPage')) {}
if (visibility.appearance !== false) {}
if (visibility.privacy !== false) {}
if (visibility.onStartup !== false) {}
r.AUTOFILL = r.BASIC.createSection('/autofill');
r.SEARCH = r.BASIC.createSection('/search');
export function getTopLevelRoute(): Route {
  if (!loadTimeData.getBoolean('isGuest')) {
    return routes.PEOPLE;
  }
}
"""
APPEARANCE = ''.join(f'?hidden="${{!this.pageVisibility_.{key}}}"\n' for key in
                     ('bookmarksBar', 'homeButton', 'hoverCard', 'pageZoom', 'setTheme'))
PERSONALIZATION = 'return (pageVisibility.privacy as PrivacyPageVisibility).searchPrediction;\n'
SETTINGS_UI_HEADER = """class SettingsUIConfig : public content::DefaultWebUIConfig<SettingsUI> {
class SettingsUI
    : public ui::MojoWebUIController {
"""
SETTINGS_UI = """SettingsUI::SettingsUI(content::WebUI* web_ui)
    : ui::MojoWebUIController(web_ui, true) {
  content::WebUIDataSource* html_source =
      content::WebUIDataSource::CreateAndAdd(
          web_ui->GetWebContents()->GetBrowserContext(),
          chrome::kChromeUISettingsHost);
{"showSkillsSettingPage", base::FeatureList::IsEnabled(features::kSkillsEnabled)},
{"showGoogleSearchAiModeWorkspaceControl",
 base::FeatureList::IsEnabled(features::kGoogleSearchAiModeWorkspace)},
"""
RESET_HANDLER = """  web_ui()->RegisterMessageCallback(
      "performResetProfileSettings",
      base::BindRepeating(&ResetSettingsHandler::HandleResetProfileSettings,
                          base::Unretained(this)));
  CHECK_EQ(3U, args.size());
  const std::string& callback_id = args[0].GetString();
  const bool& send_settings = args[1].GetBool();
  if (send_feedback && setting_snapshot_) {
"""
RESET_DIALOG = """  static get is() {
    return 'settings-reset-profile-dialog';
  }
    this.browserProxy_
        .performResetProfileSettings(
            this.$.sendSettings.checked, this.resetRequestOrigin_)
"""
SECURITY_PAGE = """      safeBrowsingPref_: {type: Object},
      'generated.safe_browsing': 'safeBrowsingPref_',
"""
SECURITY_PAGE_HTML = """      <settings-radio-group id="safeBrowsingRadioGroup" no-set-pref
          pref-key="generated.safe_browsing"
"""
SECURITY_PAGE_CSS = """ * #include=cr-shared-style-lit settings-shared-lit settings-columned-section-lit
"""
SHARED_STYLE = """ * #include=cr-hidden-style-lit cr-icons-lit
"""
HIDDEN_STYLE = """[hidden],
:host([hidden]) {
  display: none !important;
}
"""
RADIO_GROUP = """function isEnabled(radio: HTMLElement): boolean {
  return radio.matches(':not([disabled]):not([hidden])') &&
"""
BRAND_HEADER = "extern const char* g_brand_for_testing;\n"
BRAND_SOURCE = """bool GetRlzBrand(std::string* brand) {
#if BUILDFLAG(IS_CHROMEOS)
  brand->assign(google_brand::chromeos::GetRlzBrand());
  return true;
#else
  return GetBrand(brand);
#endif
}

bool IsOrganic(const std::string& brand) {
  if (brand.empty()) {
    // An empty brand string is considered the same as GGLS, which is organic.
    return true;
  }
"""
BRAND_MAC = """std::string GetBrandInternal() {
  NSString* system_brand_file =
      [@"/Library/Google/Google Chrome Brand.plist" stringByStandardizingPath];
  NSString* user_brand_file =
      [@"~/Library/Google/Google Chrome Brand.plist" stringByStandardizingPath];
  return {};
}

bool GetBrand(std::string* brand) {
  if (g_brand_for_testing) {
    *brand = g_brand_for_testing;
    return true;
  }

  static base::NoDestructor<std::string> s_brand_code(GetBrandInternal());
  *brand = *s_brand_code;
  return true;
}

bool GetReactivationBrand(std::string* brand) {
  brand->clear();
  return true;
}
"""
RESETTER = """  google_brand::GetBrand(&brandcode_);
  if (brandcode_.empty()) {
    return;
  }
  config_fetcher_ = std::make_unique<BrandcodeConfigFetcher>(
"""
RLZ_STORE = """#if BUILDFLAG(IS_POSIX)
namespace testing {
// Prefix |directory| to the path where the RLZ data file lives, for tests.
void SetRlzStoreDirectory(const base::FilePath& directory);
"""
RLZ_STORE_MAC = """// directory instead of the user's Application Support folder.
NSString* __strong g_test_folder;

NSURL* CreateRlzDirectory() {
  NSString* folder = nil;
  if (g_test_folder) {
    folder = [g_test_folder stringByAppendingPathComponent:@"Google/RLZ"];
  } else {
    NSArray* paths = NSSearchPathForDirectoriesInDomains(
        NSApplicationSupportDirectory, NSUserDomainMask, /*expandTilde=*/YES);
    if (!folder) {
      folder = [@"~/Library/Application Support" stringByStandardizingPath];
    }
    folder = [folder stringByAppendingPathComponent:@"Google/RLZ"];
  }
  return [NSURL fileURLWithPath:folder];
}

NSURL* RlzPlistPathURL() {
  NSString* const kRlzFile = @"RlzStore.plist";
  return [CreateRlzDirectory() URLByAppendingPathComponent:kRlzFile];
}

NSURL* RlzLockFileURL() {
  NSString* const kRlzLockfile = @"flockfile";
  return [CreateRlzDirectory() URLByAppendingPathComponent:kRlzLockfile];
}

ScopedRlzValueStoreLock::ScopedRlzValueStoreLock() {
  bool got_distributed_lock = g_recursive_lock.TryGetCrossProcessLock(
      base::apple::NSURLToFilePath(RlzLockFileURL()));
  NSURL* plist = RlzPlistPathURL();
}

ScopedRlzValueStoreLock::~ScopedRlzValueStoreLock() {
  VERIFY([dict writeToURL:RlzPlistPathURL() error:nil]);
}

void SetRlzStoreDirectory(const base::FilePath& directory) {
  @autoreleasepool {
    if (directory.empty()) {
      g_test_folder = nil;
    } else {
      g_test_folder = base::apple::FilePathToNSString(directory);
    }
  }
}
"""
RLZ_TRACKER = """bool SendFinancialPing(const std::string& brand,
                       const std::u16string& lang,
                       const std::u16string& referral) {
  return rlz_lib::SendFinancialPing(rlz_lib::CHROME, points, product_signature,
                                    brand, referral_ascii, lang_ascii, false,
                                    true);
}

void RLZTracker::DelayedInit() {
  if (!delegate_->IsBrandOrganic(brand_)) {
    RecordProductEvents(first_run_, is_google_default_search_,
                        app_list_used_);
    schedule_ping = true;
  }
  if (schedule_ping)
    ScheduleFinancialPing();
}

void RLZTracker::PingNowImpl() {
  if (!delegate_->IsBrandOrganic(brand_) &&
      SendFinancialPing(brand_, lang, referral)) {
    delegate_->ClearReferral();
  }

  if (!delegate_->IsBrandOrganic(reactivation_brand_)) {
    rlz_lib::SupplementaryBranding branding(reactivation_brand_.c_str());
    SendFinancialPing(reactivation_brand_, lang, referral);
  }
}

bool RLZTracker::SendFinancialPing(const std::string& brand,
                                   const std::u16string& lang,
                                   const std::u16string& referral) {
  return ::rlz::SendFinancialPing(brand, lang, referral);
}

std::string RLZTracker::GetAccessPointHttpHeader(rlz_lib::AccessPoint point) {
  std::string extra_headers;
  std::u16string rlz_string;
  RLZTracker::GetAccessPointRlz(point, &rlz_string);
  if (!rlz_string.empty()) {
    return base::StringPrintf("X-Rlz-String: %s\\r\\n",
                              base::UTF16ToUTF8(rlz_string).c_str());
  }
  return extra_headers;
}

bool RLZTracker::GetAccessPointRlzImpl(rlz_lib::AccessPoint point,
                                       std::u16string* rlz) {
  std::optional<std::string> str_rlz = rlz_lib::GetAccessPointRlz(point);
}
"""
RLZ_DELEGATE = """bool ChromeRLZTrackerDelegate::GetBrand(std::string* brand) {
  return google_brand::GetRlzBrand(brand);
}

bool ChromeRLZTrackerDelegate::IsBrandOrganic(const std::string& brand) {
  return google_brand::IsOrganic(brand);
}

bool ChromeRLZTrackerDelegate::GetReactivationBrand(std::string* brand) {
  return google_brand::GetReactivationBrand(brand);
}
"""
RESET_DIALOG_HTML = """<cr-dialog id="dialog">
  <div slot="footer">
    <cr-checkbox id="sendSettings" checked>
    </cr-checkbox>
  </div>
</cr-dialog>
"""


def settings_values():
    return contract.load_values(VALUES)


def flags():
    return {key: value for key, value in settings_values().items()
            if key not in (contract.VISIBILITY_KEY, contract.ROWS_KEY)}


def hidden_rows():
    return settings_values()[contract.ROWS_KEY]


def patch_context():
    files = {}
    target = None
    for line in PATCH.read_text(encoding='utf-8').splitlines(keepends=True):
        if line.startswith('--- a/'):
            target = line[6:].strip()
            files.setdefault(target, [])
        elif line.startswith(('+++ ', '@@ ')) or target is None:
            continue
        elif line[:1] in (' ', '-'):
            files[target].append(line[1:])
    return {target: ''.join(lines) for target, lines in files.items()}


def markup(parts):
    compound, rest = parts[0], parts[1:]
    follow = markup(rest[1:]) if rest else ''
    inside = ''.join(markup(inner[1:]) for inner in compound['has'] if inner[0] in (' ', '>'))
    beside = ''.join(markup(inner[1:]) for inner in compound['has'] if inner[0] in ('+', '~'))
    tag = compound['tag'] or 'div'
    attributes = ''.join(f' id="{name}"' for name in compound['id'])
    if compound['class']:
        attributes += f' class="{" ".join(compound["class"])}"'
    attributes += ''.join(f' {name}="{value}"' for name, value in compound['attribute'])
    child, sibling = (follow, '') if rest and rest[0] in (' ', '>') else ('', follow)
    return f'<{tag}{attributes}>{inside}{child}</{tag}>{beside}{sibling}\n'


def host_fixture(host, selectors):
    if host in CHILD_VIEW_HOSTS:
        return ''.join(f'<settings-{selector[1:].lower()}-page slot="view" id="{selector[1:]}"\n'
                       '    data-parent-view-id="parent">\n' for selector in selectors)
    return '<settings-section>\n</settings-section>\n' + ''.join(
        markup(contract.parse_selector(selector)) for selector in selectors)


class SettingsPageContractTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        context = patch_context()
        files = {
            contract.PAGE_VISIBILITY: PAGE_VISIBILITY,
            contract.ROUTES: ROUTES,
            contract.SEARCH: context[contract.SEARCH],
            contract.SECTION: context[contract.SECTION],
            contract.SUBPAGE: context[contract.SUBPAGE],
            contract.RESET_DIALOG: context[contract.RESET_DIALOG] + RESET_DIALOG,
            contract.RESET_DIALOG_HTML: RESET_DIALOG_HTML,
            contract.RESET_HANDLER: RESET_HANDLER,
            contract.SECURITY_PAGE: SECURITY_PAGE,
            contract.SECURITY_PAGE_HTML: SECURITY_PAGE_HTML + context[contract.SECURITY_PAGE_HTML],
            contract.SECURITY_PAGE_CSS: SECURITY_PAGE_CSS,
            contract.SHARED_STYLE: SHARED_STYLE,
            contract.HIDDEN_STYLE: HIDDEN_STYLE,
            contract.RADIO_GROUP: RADIO_GROUP,
            contract.BRAND_HEADER: BRAND_HEADER,
            contract.BRAND_SOURCE: BRAND_SOURCE,
            contract.BRAND_MAC: BRAND_MAC,
            contract.RESETTER: RESETTER,
            contract.RLZ_STORE: RLZ_STORE,
            contract.RLZ_STORE_MAC: RLZ_STORE_MAC,
            contract.RLZ_TRACKER: RLZ_TRACKER,
            contract.RLZ_DELEGATE: RLZ_DELEGATE,
            contract.LIVE_CAPTION[2]: 'BASE_FEATURE(kLiveCaption, base::FEATURE_ENABLED_BY_DEFAULT);\n',
            contract.NESTED_CONSUMERS['appearance'][0]: APPEARANCE,
            contract.NESTED_CONSUMERS['privacy'][0]: PERSONALIZATION,
            contract.SETTINGS_UI_HEADER: SETTINGS_UI_HEADER,
            contract.SETTINGS_UI: SETTINGS_UI,
            'components/skills/features.cc':
                'BASE_FEATURE(kSkillsEnabled, base::FEATURE_ENABLED_BY_DEFAULT);\n',
            'chrome/common/chrome_features.cc':
                'BASE_FEATURE(kGoogleSearchAiModeWorkspace, base::FEATURE_ENABLED_BY_DEFAULT);\n',
            f'{contract.SETTINGS_CC}/settings_localized_strings_provider.cc':
                ''.join(f'html_source->AddBoolean("{key}", true);\n' for key in flags()),
            f'{contract.SETTINGS_JS}/flags.ts':
                ''.join(f"loadTimeData.getBoolean('{key}');\n" for key in flags()),
        }
        for host, selectors in hidden_rows().items():
            if host in contract.SELF_HIDING_HOSTS:
                continue
            stem = f'{contract.SETTINGS_JS}/pages/{host.replace("-", "_")}'
            files[f'{stem}.ts'] = f"  static get is() {{\n    return '{host}';\n  }}\n"
            files[f'{stem}.html.ts'] = host_fixture(host, selectors)
        for relative, text in files.items():
            path = self.root / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text, encoding='utf-8')

    def page(self, host):
        return f'{contract.SETTINGS_JS}/pages/{host.replace("-", "_")}.html.ts'

    def edit(self, relative, old, new):
        path = self.root / relative
        text = path.read_text(encoding='utf-8')
        self.assertIn(old, text)
        path.write_text(text.replace(old, new), encoding='utf-8')

    def values(self, old, new):
        values = self.root / 'values.cc'
        source = VALUES.read_text(encoding='utf-8')
        self.assertIn(old, source)
        values.write_text(source.replace(old, new), encoding='utf-8')
        return values

    def problems(self, applied=False, values=VALUES, policy=POLICY):
        return contract.run(self.root, values, policy, applied).problems

    def apply_patch(self):
        result = subprocess.run(['patch', '-p1', '-s', '-d', str(self.root), '-i', str(PATCH)],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_matching_chromium_passes(self):
        self.assertEqual(self.problems(), [])

    def test_renamed_section_key_fails(self):
        self.edit(contract.PAGE_VISIBILITY, '  onStartup?: boolean;\n', '  startup?: boolean;\n')
        self.assertIn('page visibility key onStartup is no longer in PageVisibility', self.problems())

    def test_section_route_that_ignores_visibility_fails(self):
        self.edit(contract.ROUTES, 'visibility.ai !== false', 'true')
        self.assertIn('route.ts no longer removes the ai section through visibility.ai',
                      self.problems())

    def test_unread_appearance_row_key_fails(self):
        self.edit(contract.NESTED_CONSUMERS['appearance'][0], 'pageVisibility_.homeButton', 'x')
        self.assertTrue(any('appearance.homeButton' in problem for problem in self.problems()))

    def test_new_row_key_chromium_would_hide_fails(self):
        self.edit(contract.PAGE_VISIBILITY, '  sidePanel: boolean;\n',
                  '  sidePanel: boolean;\n  tabStrip: boolean;\n')
        self.assertTrue(any(problem.startswith('AppearancePageVisibility.tabStrip is new')
                            for problem in self.problems()))

    def test_renamed_row_read_fails_even_as_a_prefix(self):
        self.edit(contract.NESTED_CONSUMERS['appearance'][0], 'pageVisibility_.setTheme',
                  'pageVisibility_.setThemeV2')
        self.assertIn(f"{contract.NESTED_CONSUMERS['appearance'][0]} no longer reads appearance.setTheme",
                      self.problems())

    def test_removed_load_time_value_fails(self):
        self.edit(f'{contract.SETTINGS_JS}/flags.ts', "getBoolean('showPrivacyGuide')", "x")
        self.assertIn(f'{contract.SETTINGS_JS} no longer reads the load-time value showPrivacyGuide',
                      self.problems())
        self.edit(f'{contract.SETTINGS_CC}/settings_localized_strings_provider.cc',
                  '"showCtrlTabMru"', '"ctrlTabMru"')
        self.assertIn(f'{contract.SETTINGS_CC} no longer sets the load-time value showCtrlTabMru',
                      self.problems())

    def test_renamed_feature_fails(self):
        self.edit('components/skills/features.cc', 'kSkillsEnabled,', 'kSkillsEnabled, "Skills",')
        self.assertIn('kSkillsEnabled is now named Skills, not SkillsEnabled', self.problems())

    def test_removed_feature_fails(self):
        self.edit('chrome/common/chrome_features.cc', 'BASE_FEATURE(kGoogleSearchAiModeWorkspace',
                  'BASE_FEATURE(kGoogleSearchAiMode')
        self.assertIn('chrome/common/chrome_features.cc no longer defines kGoogleSearchAiModeWorkspace',
                      self.problems())

    def test_feature_no_longer_feeding_the_ai_page_fails(self):
        self.edit(contract.SETTINGS_UI, 'features::kSkillsEnabled', 'features::kSkillsEnabledV2')
        self.assertIn(f'{contract.SETTINGS_UI} no longer shows the AI page through kSkillsEnabled',
                      self.problems())

    def test_feature_missing_from_startup_policy_fails(self):
        policy = self.root / 'policy.h'
        policy.write_text(POLICY.read_text(encoding='utf-8').replace('"SkillsEnabled",\n', ''),
                          encoding='utf-8')
        self.assertIn('Parc startup policy no longer turns SkillsEnabled off by default',
                      self.problems(policy=policy))

    def test_hiding_the_home_page_section_needs_the_route_fallback(self):
        self.edit(contract.ROUTES, '    return routes.PEOPLE;\n', '    return routes.ACCOUNT;\n')
        self.assertTrue(any(problem.startswith('people cannot be hidden')
                            for problem in self.problems()))
        self.edit(contract.ROUTES, '    return routes.ACCOUNT;\n', '    return routes.PEOPLE;\n')
        self.assertTrue(any(problem.startswith('people cannot be hidden')
                            for problem in self.problems(applied=True)))
        self.apply_patch()
        self.assertEqual(self.problems(applied=True), [])
        self.edit(contract.ROUTES, "r.AUTOFILL = r.BASIC.createSection('/autofill');\n", '')
        self.assertIn('route.ts no longer creates the AUTOFILL section the settings home page '
                      'falls back to', self.problems(applied=True))

    def test_applied_build_requires_the_patch(self):
        problems = self.problems(applied=True)
        for relative, markers in contract.PATCH_MARKERS.items():
            for marker in markers:
                self.assertIn(f'{relative} no longer carries Parc\'s settings hook: {marker}', problems)
        self.apply_patch()
        self.assertEqual(self.problems(applied=True), [])

    def test_renamed_hidden_row_fails(self):
        self.edit(self.page('settings-appearance-page'), 'id="toolbarRow"', 'id="toolbar"')
        self.assertIn(f"{self.page('settings-appearance-page')} no longer renders the id toolbarRow "
                      "that Parc's settings-appearance-page row '#toolbarRow' names", self.problems())

    def test_reshaped_hidden_row_fails(self):
        self.edit(self.page('settings-appearance-page'), '<div id="tabStripPosition"></div>',
                  '<div><div id="tabStripPosition"></div></div>')
        problems = self.problems()
        for selector in ('.cr-row:has(> #tabStripPosition)',
                         '.cr-row:has(> #tabStripPosition) + .list-frame'):
            self.assertIn(f"{self.page('settings-appearance-page')} no longer has a row shaped like "
                          f"Parc's settings-appearance-page row {selector!r}", problems)

    def test_hidden_row_that_moves_out_of_its_parent_fails(self):
        self.edit(self.page('settings-system-page'),
                  '<div id="hardwareAcceleration"><cr-button></cr-button>\n</div>',
                  '<div id="hardwareAcceleration"></div><cr-button></cr-button>')
        self.assertIn(f"{self.page('settings-system-page')} no longer has a row shaped like Parc's "
                      "settings-system-page row '#hardwareAcceleration > cr-button'", self.problems())

    def test_renamed_hidden_row_attribute_fails(self):
        self.edit(contract.RESET_DIALOG_HTML, 'slot="footer"', 'slot="actions"')
        problems = self.problems()
        self.assertTrue(any('no longer renders the attribute slot="footer"' in problem
                            for problem in problems))
        self.assertIn(f'{contract.RESET_DIALOG_HTML} moved the report checkbox out of the footer '
                      'Parc hides', problems)

    def test_removed_hidden_row_host_fails(self):
        self.edit(f"{contract.SETTINGS_JS}/pages/settings_system_page.ts",
                  "'settings-system-page'", "'settings-system-page-v2'")
        self.assertIn(f'{contract.SETTINGS_JS} no longer defines settings-system-page exactly once',
                      self.problems())

    def test_host_without_section_or_subpage_fails(self):
        self.edit(self.page('settings-safety-hub-page'), '<settings-section>\n</settings-section>\n',
                  '')
        self.assertIn("settings-safety-hub-page renders no settings-section or settings-subpage, so "
                      "Parc's hide list never reaches its rows", self.problems())

    def test_child_view_that_stops_being_a_child_fails(self):
        self.edit(self.page('settings-autofill-page-index'), 'id="travel"\n    data-parent-view-id',
                  'id="travel"\n    data-view-id')
        self.assertIn("settings-autofill-page-index renders no settings-section or settings-subpage, "
                      "so Parc's hide list never reaches its rows", self.problems())

    def test_unsupported_selector_fails(self):
        values = self.values('"#version"', '"#version::before"')
        self.assertIn("settings-safety-hub-page row '#version::before' is not a selector Parc's "
                      "hide list supports", self.problems(values=values))

    def test_reset_report_choice_moving_fails(self):
        self.edit(contract.RESET_HANDLER, 'args[1].GetBool()', 'args[2].GetBool()')
        self.assertIn(f'{contract.RESET_HANDLER} no longer reads the report choice as the second of '
                      "three arguments, which Parc's reset guard turns off", self.problems())

    def test_reset_report_sent_unconditionally_fails(self):
        self.edit(contract.RESET_HANDLER, 'if (send_feedback && setting_snapshot_) {',
                  'if (setting_snapshot_) {')
        self.assertIn(f'{contract.RESET_HANDLER} no longer sends the settings report only when asked',
                      self.problems())

    def test_reset_dialog_choice_from_elsewhere_fails(self):
        self.edit(contract.RESET_DIALOG, 'this.$.sendSettings.checked, this', 'true, this')
        self.assertIn(f'{contract.RESET_DIALOG} no longer sends the report choice from #sendSettings',
                      self.problems())

    def test_settings_ui_filtering_messages_fails(self):
        self.edit(contract.SETTINGS_UI_HEADER, '    : public ui::MojoWebUIController {\n',
                  '    : public ui::MojoWebUIController {\n  bool OverrideHandleWebUIMessage();\n')
        self.assertIn(f"{contract.SETTINGS_UI_HEADER} now filters page messages itself, which Parc's "
                      'reset guard would replace', self.problems())

    def test_final_settings_ui_fails(self):
        self.edit(contract.SETTINGS_UI_HEADER, 'class SettingsUI\n', 'class SettingsUI final\n')
        self.assertIn(f"{contract.SETTINGS_UI_HEADER} made SettingsUI final; Parc's reset guard "
                      'subclasses it', self.problems())

    def test_build_action_writes_stamp_and_depfile_or_fails_by_name(self):
        stamp, depfile = self.root / 'out/contract.stamp', self.root / 'out/contract.d'
        stamp.parent.mkdir()
        command = [sys.executable, str(REPO / 'Engine/ParcChromium/settings_page_contract.py'),
                   '--chromium', str(self.root), '--values', str(VALUES),
                   '--startup-policy', str(POLICY), '--stamp', str(stamp), '--depfile', str(depfile)]
        result = subprocess.run(command, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(stamp.read_text(), 'ok\n')
        target, inputs = depfile.read_text().split(': ', 1)
        self.assertEqual(target, str(stamp))
        self.assertIn(str(self.root / contract.ROUTES), inputs)
        self.assertIn(str(self.root / contract.RESET_HANDLER), inputs)
        self.assertIn(str(self.root / self.page('settings-about-page')), inputs)
        self.assertIn(str(self.root / contract.SETTINGS_JS / 'pages') + ' ', inputs)
        self.assertIn(str(VALUES), inputs)
        stamp.unlink()
        self.edit(contract.ROUTES, 'visibility.onStartup !== false', 'true')
        result = subprocess.run(command, capture_output=True, text=True)
        self.assertEqual(result.returncode, 1)
        self.assertIn('route.ts no longer removes the onStartup section', result.stderr)
        self.assertFalse(stamp.exists())

    def test_hiding_enhanced_protection_again_fails(self):
        values = self.values('"#advancedProtectionProgramLink"',
                             '"#safeBrowsingEnhanced",\n      "#advancedProtectionProgramLink"')
        self.assertIn("Parc's settings-security-page list hides #safeBrowsingEnhanced, which leaves "
                      'Security with nothing selected for people on Enhanced protection',
                      self.problems(values=values))

    def test_hiding_enhanced_protection_by_another_selector_fails(self):
        values = self.values('"#advancedProtectionProgramLink"',
                             '"settings-collapse-radio-button#safeBrowsingEnhanced",\n'
                             '      "#advancedProtectionProgramLink"')
        self.assertIn("Parc's settings-security-page list hides #safeBrowsingEnhanced, which leaves "
                      'Security with nothing selected for people on Enhanced protection',
                      self.problems(values=values))

    def test_enhanced_visibility_bound_to_another_radio_fails(self):
        self.apply_patch()
        self.assertEqual(self.problems(applied=True), [])
        line = f'            {contract.ENHANCED_SHOWN}\n'
        self.edit(contract.SECURITY_PAGE_HTML, line, '')
        self.edit(contract.SECURITY_PAGE_HTML, '          pref-key="generated.safe_browsing"\n',
                  '          pref-key="generated.safe_browsing"\n'
                  '        <settings-collapse-radio-button id="safeBrowsingStandard"\n' + line)
        self.assertIn(f"{contract.SECURITY_PAGE_HTML} binds Parc's Enhanced visibility to some other "
                      'element', self.problems(applied=True))

    def test_hidden_radios_left_visible_fails(self):
        self.edit(contract.SECURITY_PAGE_CSS, 'cr-shared-style-lit ', '')
        self.assertIn(f'{contract.SECURITY_PAGE_CSS} no longer hides [hidden] radios', self.problems())

    def test_moved_enhanced_radio_fails(self):
        self.edit(contract.SECURITY_PAGE_HTML, 'id="safeBrowsingEnhanced"', 'id="enhancedRadio"')
        self.assertIn(f'{contract.SECURITY_PAGE_HTML} no longer renders the Enhanced radio Parc shows '
                      'only while it is chosen', self.problems())

    def test_radio_group_off_the_safe_browsing_pref_fails(self):
        self.edit(contract.SECURITY_PAGE_HTML, 'generated.safe_browsing', 'generated.safety')
        self.assertIn(f'{contract.SECURITY_PAGE_HTML} no longer binds its radio group to '
                      'generated.safe_browsing', self.problems())

    def test_safe_browsing_choice_kept_elsewhere_fails(self):
        self.edit(contract.SECURITY_PAGE, "'safeBrowsingPref_'", "'safeBrowsing_'")
        self.assertIn(f'{contract.SECURITY_PAGE} no longer keeps the Safe Browsing choice in '
                      'safeBrowsingPref_', self.problems())

    def test_radio_group_reaching_hidden_radios_fails(self):
        self.edit(contract.RADIO_GROUP, ':not([disabled]):not([hidden])', ':not([disabled])')
        self.assertIn(f'{contract.RADIO_GROUP} no longer skips hidden radios, so the keyboard could '
                      'pick a hidden Enhanced radio', self.problems())

    def test_brand_override_gone_fails(self):
        self.edit(contract.BRAND_HEADER, 'g_brand_for_testing', 'g_test_brand')
        self.assertIn(f'{contract.BRAND_HEADER} no longer exposes the brand override Parc clears',
                      self.problems())

    def test_brand_files_read_before_the_override_fails(self):
        self.edit(contract.BRAND_MAC, '  if (g_brand_for_testing) {\n    *brand = g_brand_for_testing;\n'
                  '    return true;\n  }\n\n', '')
        self.assertIn(f'{contract.BRAND_MAC} no longer reads the brand files only after the override '
                      'Parc sets', self.problems())

    def test_brand_files_read_by_a_caller_other_than_get_brand_fails(self):
        self.edit(contract.BRAND_MAC, 's_brand_code(GetBrandInternal());', 's_brand_code(Cached());')
        self.edit(contract.BRAND_MAC, 'bool GetBrand(std::string* brand) {',
                  'std::string Cached() {\n  return GetBrandInternal();\n}\n\n'
                  'bool GetBrand(std::string* brand) {')
        self.assertIn(f'{contract.BRAND_MAC} no longer reads the brand files only after the override '
                      'Parc sets', self.problems())

    def test_brand_files_read_outside_the_override_fails(self):
        self.edit(contract.BRAND_MAC, '  *brand = *s_brand_code;\n  return true;\n}\n',
                  '  *brand = *s_brand_code;\n  return true;\n}\n\nbool GetReactivationBrand() {\n'
                  '  return ReadBrandFile(@"/Library/Google/Google Chrome Brand.plist");\n}\n')
        self.assertIn(f"{contract.BRAND_MAC} reads Chrome's brand files outside the override Parc sets",
                      self.problems())

    def test_rlz_brand_from_elsewhere_fails(self):
        self.edit(contract.BRAND_SOURCE, 'return GetBrand(brand);', 'return GetRlzBrandFile(brand);')
        self.assertIn(f'{contract.BRAND_SOURCE} no longer takes the RLZ brand from GetBrand',
                      self.problems())

    def test_brand_download_without_a_brand_fails(self):
        self.edit(contract.RESETTER, '  if (brandcode_.empty()) {\n    return;\n  }\n', '')
        self.assertIn(f'{contract.RESETTER} no longer skips the brand code download when there is no '
                      'brand', self.problems())

    def test_parc_no_longer_clearing_the_brand_fails(self):
        values = self.values(contract.NO_BRAND, 'google_brand::g_brand_for_testing = nullptr;')
        self.assertIn('Parc no longer clears the brand code', self.problems(values=values))

    def test_rlz_folder_override_gone_fails(self):
        self.edit(contract.RLZ_STORE, 'void SetRlzStoreDirectory(', 'void SetRlzStorePath(')
        self.assertIn(f'{contract.RLZ_STORE} no longer declares the RLZ store folder override Parc sets',
                      self.problems())

    def test_rlz_folder_override_dropped_fails(self):
        self.edit(contract.RLZ_STORE_MAC, '      g_test_folder = base::apple::FilePathToNSString(directory);\n',
                  '')
        self.assertIn(f'{contract.RLZ_STORE_MAC} no longer keeps the RLZ store folder Parc sets',
                      self.problems())

    def test_rlz_store_ignoring_the_folder_fails(self):
        self.edit(contract.RLZ_STORE_MAC, '  if (g_test_folder) {\n', '  if (g_test_folder && false) {\n')
        self.assertIn(f'{contract.RLZ_STORE_MAC} no longer puts the RLZ store in the folder Parc sets',
                      self.problems())

    def test_chrome_rlz_store_found_outside_the_override_fails(self):
        self.edit(contract.RLZ_STORE_MAC, 'NSURL* RlzPlistPathURL() {',
                  'NSString* SharedFolder() {\n  return NSSearchPathForDirectoriesInDomains(\n'
                  '      NSApplicationSupportDirectory, NSUserDomainMask, YES)[0];\n}\n\n'
                  'NSURL* RlzPlistPathURL() {')
        self.assertIn(f"{contract.RLZ_STORE_MAC} finds Chrome's RLZ store outside the folder override "
                      'Parc sets', self.problems())

    def test_rlz_lock_outside_the_store_folder_fails(self):
        self.edit(contract.RLZ_STORE_MAC,
                  'return [CreateRlzDirectory() URLByAppendingPathComponent:kRlzLockfile];',
                  'return [NSURL fileURLWithPath:@"/tmp/flockfile"];')
        self.assertIn(f'{contract.RLZ_STORE_MAC} no longer keeps the RLZ store and its lock in one folder',
                      self.problems())

    def test_rlz_store_read_from_another_path_fails(self):
        self.edit(contract.RLZ_STORE_MAC, 'NSURL* plist = RlzPlistPathURL();',
                  'NSURL* plist = SharedPlistURL();')
        self.assertIn(f'{contract.RLZ_STORE_MAC} no longer keeps the RLZ store and its lock in one folder',
                      self.problems())

    def test_other_rlz_source_finding_chrome_store_fails(self):
        other = self.root / contract.RLZ_ROOT / 'mac/lib/shared_store.mm'
        other.write_text('NSString* const kFolder = @"Google/RLZ";\n', encoding='utf-8')
        self.assertIn(f"{contract.RLZ_ROOT}/mac/lib/shared_store.mm finds Chrome's RLZ store outside the "
                      'folder override Parc sets', self.problems())

    def test_parc_no_longer_moving_the_rlz_store_fails(self):
        values = self.values(contract.PARC_RLZ_STORE, 'static_cast<void>(user_data_dir);')
        self.assertIn('Parc no longer keeps the RLZ store in its own folder', self.problems(values=values))

    def test_rlz_header_sent_without_a_string_fails(self):
        self.edit(contract.RLZ_TRACKER, '  if (!rlz_string.empty()) {\n', '  {\n')
        self.assertIn(f'{contract.RLZ_TRACKER} no longer leaves the X-Rlz-String header out when the '
                      'store holds no RLZ string', self.problems())

    def test_rlz_header_added_elsewhere_fails(self):
        self.edit(contract.RLZ_TRACKER, 'std::string extra_headers;',
                  'std::string extra_headers = "X-Rlz-String: \\r\\n";')
        self.assertIn(f'{contract.RLZ_TRACKER} no longer leaves the X-Rlz-String header out when the '
                      'store holds no RLZ string', self.problems())

    def test_rlz_ping_without_a_brand_gate_fails(self):
        self.edit(contract.RLZ_TRACKER, '  if (!delegate_->IsBrandOrganic(brand_) &&\n      ', '  if (')
        self.assertIn(f'{contract.RLZ_TRACKER} no longer sends RLZ pings only for a non-organic brand',
                      self.problems())

    def test_rlz_ping_from_another_caller_fails(self):
        self.edit(contract.RLZ_TRACKER, '    delegate_->ClearReferral();\n',
                  '    delegate_->ClearReferral();\n    SendFinancialPing(brand_, lang, referral);\n')
        self.assertIn(f'{contract.RLZ_TRACKER} no longer sends RLZ pings only for a non-organic brand',
                      self.problems())

    def test_rlz_ping_through_rlz_lib_from_another_caller_fails(self):
        self.edit(contract.RLZ_TRACKER, '    delegate_->ClearReferral();\n',
                  '    delegate_->ClearReferral();\n'
                  '    rlz_lib::SendFinancialPing(rlz_lib::CHROME, points, "chrome", brand_, "", "",\n'
                  '                               false, true);\n')
        self.assertIn(f'{contract.RLZ_TRACKER} no longer sends RLZ pings only for a non-organic brand',
                      self.problems())

    def test_rlz_ping_scheduled_from_another_path_fails(self):
        self.edit(contract.RLZ_TRACKER, 'void RLZTracker::PingNowImpl() {',
                  'void RLZTracker::RecordFirstSearch() {\n  ScheduleFinancialPing();\n}\n\n'
                  'void RLZTracker::PingNowImpl() {')
        self.assertIn(f'{contract.RLZ_TRACKER} no longer sends RLZ pings only for a non-organic brand',
                      self.problems())

    def test_rlz_brand_from_another_source_fails(self):
        self.edit(contract.RLZ_DELEGATE, 'return google_brand::IsOrganic(brand);', 'return false;')
        self.assertIn(f'{contract.RLZ_DELEGATE} no longer takes the RLZ brand and its organic check '
                      'from google_brand', self.problems())

    def test_empty_brand_no_longer_organic_fails(self):
        self.edit(contract.BRAND_SOURCE, '  if (brand.empty()) {\n', '  if (brand == "GGLS") {\n')
        self.assertIn(f'{contract.BRAND_SOURCE} no longer treats no brand as organic', self.problems())

    def test_reactivation_brand_read_from_disk_fails(self):
        self.edit(contract.BRAND_MAC, '  brand->clear();\n', '  *brand = ReadReactivationBrand();\n')
        self.assertIn(f'{contract.BRAND_MAC} no longer leaves the reactivation brand empty',
                      self.problems())

    def test_live_caption_renamed_fails(self):
        self.edit(contract.LIVE_CAPTION[2], 'kLiveCaption,', 'kLiveCaption, "LiveCaptions",')
        self.assertIn('kLiveCaption is now named LiveCaptions, not LiveCaption', self.problems())

    def test_live_caption_missing_from_startup_policy_fails(self):
        policy = self.root / 'policy.h'
        policy.write_text(POLICY.read_text(encoding='utf-8').replace('"LiveCaption",\n', ''),
                          encoding='utf-8')
        self.assertIn('Parc startup policy no longer turns LiveCaption off by default',
                      self.problems(policy=policy))

    def test_lost_guest_fallback_fails(self):
        self.edit(contract.PAGE_VISIBILITY, "if (!loadTimeData.getBoolean('isGuest')) {",
                  "if (!loadTimeData.getBoolean('guest')) {")
        self.assertIn(f'{contract.PAGE_VISIBILITY} lost the guest check the Parc patch precedes',
                      self.problems())

    def test_changed_settings_data_source_fails(self):
        self.edit(contract.SETTINGS_UI, 'CreateAndAdd(', 'Create(')
        self.assertIn(f'{contract.SETTINGS_UI} no longer creates the settings data source in its '
                      'constructor', self.problems())


def engine_source():
    workspace = os.environ.get('PARC_ENGINE_WORKSPACE')
    root = Path(workspace) / 'chromium/src' if workspace else REPO / 'work/engine/chromium/src'
    return root if (root / contract.PAGE_VISIBILITY).is_file() else None


def pristine(root, relative):
    result = subprocess.run(['git', '-C', str(root), 'show', f'HEAD:{relative}'],
                            capture_output=True, text=True)
    return result.stdout if result.returncode == 0 else None


@unittest.skipUnless(engine_source(), 'no engine workspace')
class SettingsPageEngineTests(unittest.TestCase):
    def test_pinned_chromium_meets_the_contract(self):
        root = engine_source()
        self.assertEqual(contract.run(root, VALUES, POLICY, False).problems, [])
        applied = all(marker in (root / relative).read_text(encoding='utf-8')
                      for relative, markers in contract.PATCH_MARKERS.items() for marker in markers)
        if applied:
            self.assertEqual(contract.run(root, VALUES, POLICY, True).problems, [])

    def test_patch_applies_to_pinned_chromium(self):
        root = engine_source()
        with tempfile.TemporaryDirectory() as temporary:
            for relative in contract.PATCH_MARKERS:
                source = pristine(root, relative)
                if source is None:
                    self.skipTest('the workspace has no pristine Chromium history')
                target = Path(temporary) / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_text(source, encoding='utf-8')
            result = subprocess.run(['patch', '-p1', '-s', '-d', temporary, '-i', str(PATCH)],
                                    capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            check = contract.Contract(Path(temporary))
            contract.check_patch(check, True)
            self.assertEqual(check.problems, [])


if __name__ == '__main__':
    unittest.main()
