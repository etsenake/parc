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
    '': 'people',
    'clearBrowserData': 'privacy',
    'content': 'privacy',
    'payments': 'yourSavedInfo',
    'privacy': 'privacy',
    'searchEngines': None,
    'security': 'privacy',
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
export function getTopLevelRoute(): Route {
  if (!loadTimeData.getBoolean('isGuest')) {
    return routes.PEOPLE;
  }
}
"""
APPEARANCE = ''.join(f'?hidden="${{!this.pageVisibility_.{key}}}"\n' for key in
                     ('bookmarksBar', 'homeButton', 'hoverCard', 'pageZoom', 'setTheme'))
PERSONALIZATION = 'return (pageVisibility.privacy as PrivacyPageVisibility).searchPrediction;\n'
SETTINGS_UI_HEADER = 'class SettingsUIConfig : public content::DefaultWebUIConfig<SettingsUI> {\n'
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


def settings_values():
    return contract.load_values(VALUES)


def flags():
    return {key: value for key, value in settings_values().items() if key != 'parcPageVisibility'}


class SettingsPageValuesTests(unittest.TestCase):
    def test_values_parse_as_the_dictionary_the_engine_sends(self):
        values = settings_values()
        self.assertIsInstance(values['parcPageVisibility'], dict)
        for key, value in flags().items():
            self.assertIsInstance(value, bool, key)

    def test_settings_home_page_section_stays(self):
        visibility = settings_values()['parcPageVisibility']
        self.assertNotEqual(visibility.get('people'), False)

    def test_inert_sections_and_rows_are_hidden(self):
        visibility = settings_values()['parcPageVisibility']
        self.assertIs(visibility['onStartup'], False)
        self.assertIs(visibility['ai'], False)
        self.assertIs(visibility['privacy']['searchPrediction'], False)
        self.assertIs(visibility['privacy']['networkPrediction'], True)
        appearance = visibility['appearance']
        for key in ('bookmarksBar', 'homeButton', 'hoverCard', 'setTheme'):
            self.assertIs(appearance[key], False, key)
        self.assertIs(flags()['showPrivacyGuide'], False)

    def test_working_rows_stay(self):
        visibility = settings_values()['parcPageVisibility']
        self.assertIs(visibility['appearance']['pageZoom'], True)
        self.assertIs(visibility['appearance']['sidePanel'], True)
        for section in ('autofill', 'downloads', 'extensions', 'languages', 'performance',
                        'privacy', 'reset', 'safetyHub', 'system', 'yourSavedInfo', 'defaultBrowser'):
            self.assertNotEqual(visibility.get(section), False, section)
        for flag in ('mandatoryReauthFeatureFlagEnabled', 'cvcStorageAvailable', 'showIbansSettings',
                     'enableSecurityKeysSubpage', 'showSecureDnsSetting'):
            self.assertNotIn(flag, flags())

    def test_no_parc_settings_link_lands_on_a_hidden_section(self):
        visibility = settings_values()['parcPageVisibility']
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


class SettingsPageContractTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        files = {
            contract.PAGE_VISIBILITY: PAGE_VISIBILITY,
            contract.ROUTES: ROUTES,
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
        for relative, text in files.items():
            path = self.root / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text, encoding='utf-8')

    def edit(self, relative, old, new):
        path = self.root / relative
        text = path.read_text(encoding='utf-8')
        self.assertIn(old, text)
        path.write_text(text.replace(old, new), encoding='utf-8')

    def problems(self, applied=False, values=VALUES, policy=POLICY):
        return contract.run(self.root, values, policy, applied).problems

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

    def test_hiding_the_home_page_section_fails(self):
        values = self.root / 'values.cc'
        source = VALUES.read_text(encoding='utf-8')
        values.write_text(source.replace('"ai": false,', '"ai": false,\n    "people": false,'),
                          encoding='utf-8')
        self.assertTrue(any(problem.startswith('people cannot be hidden')
                            for problem in self.problems(values=values)))

    def test_applied_build_requires_the_patch(self):
        self.assertIn(f'{contract.PAGE_VISIBILITY} no longer reads parcPageVisibility',
                      self.problems(applied=True))
        result = subprocess.run(['patch', '-p1', '-s', '-d', str(self.root), '-i', str(PATCH)],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.problems(applied=True), [])

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


@unittest.skipUnless(engine_source(), 'no engine workspace')
class SettingsPageEngineTests(unittest.TestCase):
    def test_pinned_chromium_meets_the_contract(self):
        root = engine_source()
        applied = "valueExists('parcPageVisibility')" in (root / contract.PAGE_VISIBILITY).read_text()
        self.assertEqual(contract.run(root, VALUES, POLICY, applied).problems, [])

    def test_patch_applies_to_pinned_chromium(self):
        root = engine_source()
        source = (root / contract.PAGE_VISIBILITY).read_text(encoding='utf-8')
        if "valueExists('parcPageVisibility')" in source:
            self.skipTest('workspace already carries the patch')
        with tempfile.TemporaryDirectory() as temporary:
            target = Path(temporary) / contract.PAGE_VISIBILITY
            target.parent.mkdir(parents=True)
            target.write_text(source, encoding='utf-8')
            result = subprocess.run(['patch', '-p1', '-s', '-d', temporary, '-i', str(PATCH)],
                                    capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("return loadTimeData.getValue<PageVisibility>('parcPageVisibility');",
                          target.read_text(encoding='utf-8'))


if __name__ == '__main__':
    unittest.main()
