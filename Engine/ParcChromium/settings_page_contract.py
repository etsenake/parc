#!/usr/bin/env python3
import argparse
import json
import re
import sys
from pathlib import Path

SETTINGS_JS = 'chrome/browser/resources/settings'
SETTINGS_CC = 'chrome/browser/ui/webui/settings'
PAGE_VISIBILITY = f'{SETTINGS_JS}/page_visibility.ts'
ROUTES = f'{SETTINGS_JS}/route.ts'
SETTINGS_UI = f'{SETTINGS_CC}/settings_ui.cc'
SETTINGS_UI_HEADER = f'{SETTINGS_CC}/settings_ui.h'
NESTED_INTERFACES = {
    'appearance': 'AppearancePageVisibility',
    'privacy': 'PrivacyPageVisibility',
}
NESTED_CONSUMERS = {
    'appearance': (f'{SETTINGS_JS}/appearance_page/appearance_page.html.ts',
                   'pageVisibility_.{key}'),
    'privacy': (f'{SETTINGS_JS}/privacy_page/personalization_options.ts',
                'PrivacyPageVisibility).{key}'),
}
FEATURES = {
    'SkillsEnabled': ('kSkillsEnabled', 'components/skills/features.cc'),
    'GoogleSearchAiModeWorkspace':
        ('kGoogleSearchAiModeWorkspace', 'chrome/common/chrome_features.cc'),
}
VALUES = re.compile(r'R"json\((.*?)\)json"', re.S)


class Contract:
    def __init__(self, chromium: Path):
        self.chromium = chromium
        self.read_paths = set()
        self.problems = []

    def text(self, relative: str) -> str:
        path = self.chromium / relative
        self.read_paths.add(path)
        if not path.is_file():
            self.problems.append(f'{relative} is missing')
            return ''
        return path.read_text(encoding='utf-8')

    def tree(self, relative: str, suffixes: tuple) -> str:
        root = self.chromium / relative
        if not root.is_dir():
            self.problems.append(f'{relative} is missing')
            return ''
        parts = []
        for path in sorted(root.rglob('*')):
            if path.suffix in suffixes and path.is_file() and 'test' not in path.name:
                self.read_paths.add(path)
                parts.append(path.read_text(encoding='utf-8'))
        return '\n'.join(parts)

    def fail(self, message: str):
        self.problems.append(message)


def interface_keys(source: str, name: str):
    match = re.search(r'export interface ' + name + r' \{(.*?)\n\}', source, re.S)
    if not match:
        return None
    return dict(re.findall(r'^\s*(\w+)\??:\s*([^;]+);', match.group(1), re.M))


def reads(source: str, expression: str) -> bool:
    return re.search(re.escape(expression) + r'(?!\w)', source) is not None


def load_values(path: Path) -> dict:
    match = VALUES.search(path.read_text(encoding='utf-8'))
    if not match:
        raise ValueError(f'{path} has no R"json(...)json" settings values')
    values = json.loads(match.group(1))
    if not isinstance(values, dict) or not isinstance(values.get('parcPageVisibility'), dict):
        raise ValueError(f'{path} values need a parcPageVisibility dictionary')
    return values


def check_visibility(contract: Contract, visibility: dict, applied: bool):
    source = contract.text(PAGE_VISIBILITY)
    routes = contract.text(ROUTES)
    if applied and "loadTimeData.valueExists('parcPageVisibility')" not in source:
        contract.fail(f'{PAGE_VISIBILITY} no longer reads parcPageVisibility')
    if "if (!loadTimeData.getBoolean('isGuest')) {" not in source:
        contract.fail(f'{PAGE_VISIBILITY} lost the guest check the Parc patch precedes')
    keys = interface_keys(source, 'PageVisibility')
    if keys is None:
        contract.fail(f'{PAGE_VISIBILITY} no longer exports interface PageVisibility')
        return
    if visibility.get('people') is False and 'return routes.PEOPLE;' in routes:
        contract.fail('people cannot be hidden: route.ts still sends the settings home page and search to it')
    for key, value in sorted(visibility.items()):
        if key not in keys:
            contract.fail(f'page visibility key {key} is no longer in PageVisibility')
            continue
        if f'visibility.{key} !== false' not in routes:
            contract.fail(f'route.ts no longer removes the {key} section through visibility.{key}')
        if isinstance(value, bool):
            continue
        interface = NESTED_INTERFACES.get(key)
        if not isinstance(value, dict) or interface is None:
            contract.fail(f'page visibility key {key} must be true, false or a known section object')
            continue
        if interface not in keys[key]:
            contract.fail(f'PageVisibility.{key} no longer accepts {interface}')
        nested = interface_keys(source, interface) or {}
        consumer, pattern = NESTED_CONSUMERS[key]
        consumer_source = contract.text(consumer)
        for nested_key in sorted(set(nested) - set(value)):
            contract.fail(f'{interface}.{nested_key} is new; name it in Parc\'s {key} list, '
                          'or Chromium hides that row')
        for nested_key, nested_value in sorted(value.items()):
            if not isinstance(nested_value, bool):
                contract.fail(f'{key}.{nested_key} must be true or false')
            if nested_key not in nested:
                contract.fail(f'{key}.{nested_key} is no longer in {interface}')
            elif nested_value is False and not reads(consumer_source, pattern.format(key=nested_key)):
                contract.fail(f'{consumer} no longer reads {key}.{nested_key}')


def check_flags(contract: Contract, flags: dict):
    emitted = contract.tree(SETTINGS_CC, ('.cc',))
    read = contract.tree(SETTINGS_JS, ('.ts',))
    for key, value in sorted(flags.items()):
        if not isinstance(value, bool):
            contract.fail(f'load-time value {key} must be true or false')
        if f'"{key}"' not in emitted:
            contract.fail(f'{SETTINGS_CC} no longer sets the load-time value {key}')
        if f"loadTimeData.getBoolean('{key}')" not in read:
            contract.fail(f'{SETTINGS_JS} no longer reads the load-time value {key}')


def check_features(contract: Contract, startup_policy: Path):
    policy = startup_policy.read_text(encoding='utf-8')
    contract.read_paths.add(startup_policy)
    disabled = re.search(r'kBaselineDisabledFeatures\[\] = \{(.*?)\};', policy, re.S)
    settings_ui = contract.text(SETTINGS_UI)
    for name, (identifier, relative) in sorted(FEATURES.items()):
        if not disabled or f'"{name}"' not in disabled.group(1):
            contract.fail(f'Parc startup policy no longer turns {name} off by default')
        definition = re.search(r'BASE_FEATURE\(\s*' + identifier + r'\s*,\s*(?:"([^"]+)"\s*,)?',
                               contract.text(relative))
        if not definition:
            contract.fail(f'{relative} no longer defines {identifier}')
        elif (definition.group(1) or identifier[1:]) != name:
            contract.fail(f'{identifier} is now named {definition.group(1) or identifier[1:]}, not {name}')
        if not reads(settings_ui, identifier):
            contract.fail(f'{SETTINGS_UI} no longer shows the AI page through {identifier}')


def check_mechanism(contract: Contract):
    header = contract.text(SETTINGS_UI_HEADER)
    if 'class SettingsUIConfig : public content::DefaultWebUIConfig<SettingsUI>' not in header:
        contract.fail(f'{SETTINGS_UI_HEADER} changed how SettingsUIConfig builds SettingsUI')
    source = contract.text(SETTINGS_UI)
    constructor = source.find('SettingsUI::SettingsUI(content::WebUI* web_ui)')
    body = source[constructor:constructor + 800] if constructor >= 0 else ''
    if 'content::WebUIDataSource::CreateAndAdd(' not in body or 'chrome::kChromeUISettingsHost' not in body:
        contract.fail(f'{SETTINGS_UI} no longer creates the settings data source in its constructor')


def run(chromium: Path, values_path: Path, startup_policy: Path, applied: bool) -> Contract:
    contract = Contract(chromium)
    contract.read_paths.add(values_path)
    values = load_values(values_path)
    flags = {key: value for key, value in values.items() if key != 'parcPageVisibility'}
    check_visibility(contract, values['parcPageVisibility'], applied)
    check_flags(contract, flags)
    check_features(contract, startup_policy)
    check_mechanism(contract)
    return contract


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('--chromium', type=Path, required=True)
    parser.add_argument('--values', type=Path, required=True)
    parser.add_argument('--startup-policy', type=Path, required=True)
    parser.add_argument('--applied', action='store_true')
    parser.add_argument('--stamp', type=Path)
    parser.add_argument('--depfile', type=Path)
    args = parser.parse_args()
    try:
        contract = run(args.chromium, args.values, args.startup_policy, args.applied)
    except (OSError, ValueError) as error:
        print(f'Parc settings page contract failed: {error}', file=sys.stderr)
        return 1
    if contract.problems:
        print('Parc settings page contract failed. Chromium changed something the hidden '
              'settings rows rely on:', file=sys.stderr)
        for problem in contract.problems:
            print(f'  - {problem}', file=sys.stderr)
        return 1
    if args.stamp:
        args.stamp.write_text('ok\n', encoding='utf-8')
    if args.depfile and args.stamp:
        inputs = ' '.join(str(path).replace(' ', '\\ ') for path in sorted(contract.read_paths))
        args.depfile.write_text(f'{args.stamp}: {inputs}\n', encoding='utf-8')
    return 0


if __name__ == '__main__':
    sys.exit(main())
