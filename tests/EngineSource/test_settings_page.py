import importlib.util
import json
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

LINK_SECTIONS = {
    '': 'yourSavedInfo',
    'clearBrowserData': 'privacy',
    'content': 'privacy',
    'payments': 'yourSavedInfo',
    'privacy': 'privacy',
    'searchEngines': None,
    'security': 'privacy',
}
LINK_PAGES = ('settings-payments-page', 'settings-security-page')
CHILD_VIEW_HOSTS = ('settings-autofill-page-index',)
KEPT_ROWS = {
    'settings-a11y-page': ('#captions',),
    'settings-autofill-page': ('#passwordManagerButton', '#paymentManagerButton',
                               '#addressesManagerButton'),
    'settings-payments-page': ('#autofillCreditCardToggle', '#canMakePaymentToggle'),
    'settings-security-page': ('#safeBrowsingStandard', '#safeBrowsingDisabled'),
    'settings-system-page': ('#hardwareAcceleration', '#proxy'),
}

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


def subject(selector):
    outer = re.sub(r':has\([^)]*\)', '', selector)
    return re.split(r'\s*[>+~]\s*|\s+', outer.strip())[-1]


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


class SettingsPageValuesTests(unittest.TestCase):
    def test_values_parse_as_the_dictionary_the_engine_sends(self):
        values = settings_values()
        self.assertIsInstance(values[contract.VISIBILITY_KEY], dict)
        self.assertIsInstance(values[contract.ROWS_KEY], dict)
        for key, value in flags().items():
            self.assertIsInstance(value, bool, key)

    def test_settings_home_page_falls_back_to_a_section_that_stays(self):
        visibility = settings_values()[contract.VISIBILITY_KEY]
        self.assertIs(visibility['people'], False)
        self.assertNotEqual(visibility.get('yourSavedInfo'), False)
        self.assertIn(f'+    {contract.HOME_FALLBACK}\n', PATCH.read_text(encoding='utf-8'))

    def test_inert_sections_and_rows_are_hidden(self):
        visibility = settings_values()[contract.VISIBILITY_KEY]
        self.assertIs(visibility['onStartup'], False)
        self.assertIs(visibility['ai'], False)
        self.assertIs(visibility['privacy']['searchPrediction'], False)
        self.assertIs(visibility['privacy']['networkPrediction'], True)
        appearance = visibility['appearance']
        for key in ('bookmarksBar', 'homeButton', 'hoverCard', 'setTheme'):
            self.assertIs(appearance[key], False, key)
        self.assertIs(flags()['showPrivacyGuide'], False)
        expected = {
            'settings-about-page': ('#updateStatusMessage', '#buttonContainer'),
            'settings-appearance-page': ('#toolbarRow', '#colorSchemeModeRow',
                                         '.cr-row:has(> #tabStripPosition)',
                                         '#showOrganizerPanelButton',
                                         '.list-frame:has(#sidePanelPosition)',
                                         '#splitViewDragAndDrop',
                                         '[pref-key="browser.confirm_to_quit"]'),
            'settings-autofill-page': ('#googleWalletButton', '#googleAccountButton',
                                       'settings-section:has(> collapsible-autofill-settings-card)'),
            'settings-payments-page': ('#cardBenefitsToggle', '#manageLink'),
            'settings-performance-page': ('#performanceInterventionToggleButton',
                                          '#discardRingTreatmentToggleButton',
                                          'cr-link-row:has(+ #exceptionList)'),
            'settings-reset-profile-dialog': ('[slot="footer"]',),
            'settings-safety-hub-page': ('#version',),
            'settings-security-page': ('#safeBrowsingEnhanced',),
            'settings-system-page': ('#hardwareAcceleration > cr-button',),
            'settings-translate-page': ('settings-section',),
        }
        rows = hidden_rows()
        for host, selectors in expected.items():
            for selector in selectors:
                self.assertIn(selector, rows.get(host, []), host)

    def test_every_hidden_row_is_a_supported_selector(self):
        for host, selectors in hidden_rows().items():
            self.assertRegex(host, r'^[a-z]+(?:-[a-z0-9]+)+$')
            self.assertEqual(len(selectors), len(set(selectors)), host)
            for selector in selectors:
                self.assertTrue(contract.supported(selector), f'{host}: {selector}')
                self.assertTrue(contract.selector_parts(selector), selector)

    def test_working_rows_stay(self):
        visibility = settings_values()[contract.VISIBILITY_KEY]
        self.assertIs(visibility['appearance']['pageZoom'], True)
        self.assertIs(visibility['appearance']['sidePanel'], True)
        for section in ('autofill', 'downloads', 'extensions', 'languages', 'performance',
                        'privacy', 'reset', 'safetyHub', 'system', 'yourSavedInfo', 'defaultBrowser'):
            self.assertNotEqual(visibility.get(section), False, section)
        for flag in ('mandatoryReauthFeatureFlagEnabled', 'cvcStorageAvailable', 'showIbansSettings',
                     'enableSecurityKeysSubpage', 'showSecureDnsSetting'):
            self.assertNotIn(flag, flags())
        rows = hidden_rows()
        for host, kept in KEPT_ROWS.items():
            subjects = {subject(selector) for selector in rows.get(host, [])}
            for row in kept:
                self.assertNotIn(row, subjects, host)

    def test_no_parc_settings_link_lands_on_a_hidden_section(self):
        visibility = settings_values()[contract.VISIBILITY_KEY]
        links = set()
        sources = [path for pattern in ('*.swift', '*.cc', '*.mm')
                   for root in (REPO / 'Sources', REPO / 'Engine') for path in root.rglob(pattern)]
        for path in sources:
            links.update(re.findall(r'parc://settings/([A-Za-z]*)', path.read_text(encoding='utf-8')))
        downloads = (REPO / 'Engine/ParcNative/downloads.cc').read_text(encoding='utf-8')
        if 'kSafeBrowsingEnhancedProtectionSubPage' in downloads:
            links.add('security')
        self.assertIn('', links)
        for link in sorted(links):
            self.assertIn(link, LINK_SECTIONS, f'map parc://settings/{link} to its section')
            section = LINK_SECTIONS[link]
            if section:
                self.assertNotEqual(visibility.get(section), False, link)
        rows = hidden_rows()
        for page in LINK_PAGES:
            for selector in rows.get(page, []):
                self.assertNotIn(subject(selector), ('settings-subpage', 'settings-section'), page)


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
