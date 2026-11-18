#!/usr/bin/env python3
import argparse
import json
import re
import sys
from html.parser import HTMLParser
from pathlib import Path

SETTINGS_JS = 'chrome/browser/resources/settings'
SETTINGS_CC = 'chrome/browser/ui/webui/settings'
PAGE_VISIBILITY = f'{SETTINGS_JS}/page_visibility.ts'
ROUTES = f'{SETTINGS_JS}/route.ts'
SEARCH = f'{SETTINGS_JS}/search_settings.ts'
SECTION = f'{SETTINGS_JS}/settings_page/settings_section.ts'
SUBPAGE = f'{SETTINGS_JS}/settings_page/settings_subpage.ts'
RESET_DIALOG = f'{SETTINGS_JS}/reset_page/reset_profile_dialog.ts'
RESET_DIALOG_HTML = f'{SETTINGS_JS}/reset_page/reset_profile_dialog.html.ts'
RESET_HANDLER = f'{SETTINGS_CC}/reset_settings_handler.cc'
SECURITY_PAGE = f'{SETTINGS_JS}/privacy_page/security/security_page.ts'
SECURITY_PAGE_HTML = f'{SETTINGS_JS}/privacy_page/security/security_page.html'
SECURITY_PAGE_CSS = f'{SETTINGS_JS}/privacy_page/security/security_page.css'
SHARED_STYLE = 'ui/webui/resources/cr_elements/cr_shared_style_lit.css'
HIDDEN_STYLE = 'ui/webui/resources/cr_elements/cr_hidden_style_lit.css'
RADIO_GROUP = 'ui/webui/resources/cr_elements/cr_radio_group/cr_radio_group.ts'
BRAND_HEADER = 'chrome/browser/google/google_brand.h'
BRAND_SOURCE = 'chrome/browser/google/google_brand.cc'
BRAND_MAC = 'chrome/browser/google/google_brand_mac.mm'
RESETTER = 'chrome/browser/profile_resetter/profile_resetter.cc'
SETTINGS_UI = f'{SETTINGS_CC}/settings_ui.cc'
SETTINGS_UI_HEADER = f'{SETTINGS_CC}/settings_ui.h'
VISIBILITY_KEY = 'parcPageVisibility'
ROWS_KEY = 'parcHiddenRows'
HOME_FALLBACK = 'return routes.PEOPLE || routes.AUTOFILL || routes.SEARCH;'
HOME_SECTIONS = ('AUTOFILL', 'SEARCH')
ENHANCED_ROW = '#safeBrowsingEnhanced'
ENHANCED_SHOWN = '?hidden="${this.safeBrowsingPref_?.value !== SafeBrowsingSetting.ENHANCED}"'
NO_BRAND = 'google_brand::g_brand_for_testing = "";'
PATCH_MARKERS = {
    PAGE_VISIBILITY: ("loadTimeData.valueExists('parcPageVisibility')",
                      "loadTimeData.valueExists('parcHiddenRows')",
                      'export function hideParcRows(node: Node)',
                      'export function isParcHiddenRow(element: Element)'),
    ROUTES: (HOME_FALLBACK,),
    SEARCH: ('isParcHiddenRow(element)',),
    SECTION: ('hideParcRows(this);',),
    SUBPAGE: ('hideParcRows(this);',),
    RESET_DIALOG: ('hideParcRows(this.$.dialog);', 'this.$.sendSettings.checked = false;'),
    SECURITY_PAGE_HTML: (ENHANCED_SHOWN,),
}
SELF_HIDING_HOSTS = {'settings-reset-profile-dialog': RESET_DIALOG}
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
NAME = r'[A-Za-z][\w-]*'
ATTRIBUTE = r'\[([a-z][\w-]*)(?:="([^"\\]*)")?\]'
SIMPLE = re.compile(rf'#({NAME})|\.({NAME})|{ATTRIBUTE}|:has\(')
VOID_TAGS = {'area', 'br', 'col', 'embed', 'hr', 'img', 'input', 'link', 'meta', 'source', 'wbr'}
SCOPE = {}


class Contract:
    def __init__(self, chromium: Path):
        self.chromium = chromium
        self.read_paths = set()
        self.problems = []
        self.trees = {}

    def text(self, relative: str) -> str:
        path = self.chromium / relative
        self.read_paths.add(path)
        if not path.is_file():
            self.problems.append(f'{relative} is missing')
            return ''
        return path.read_text(encoding='utf-8')

    def files(self, relative: str, suffixes: tuple) -> dict:
        key = (relative, suffixes)
        if key not in self.trees:
            root = self.chromium / relative
            found = {}
            if not root.is_dir():
                self.problems.append(f'{relative} is missing')
            else:
                for path in sorted(root.rglob('*')):
                    if path.suffix in suffixes and path.is_file() and 'test' not in path.name:
                        self.read_paths.add(path)
                        found[path] = path.read_text(encoding='utf-8')
            self.trees[key] = found
        return self.trees[key]

    def watch(self, relative: str):
        root = self.chromium / relative
        self.read_paths.update([root, *(path for path in root.rglob('*') if path.is_dir())])

    def tree(self, relative: str, suffixes: tuple) -> str:
        return '\n'.join(self.files(relative, suffixes).values())

    def relative(self, path: Path) -> str:
        return path.relative_to(self.chromium).as_posix()

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
    if not isinstance(values, dict) or not isinstance(values.get(VISIBILITY_KEY), dict):
        raise ValueError(f'{path} values need a {VISIBILITY_KEY} dictionary')
    if not isinstance(values.get(ROWS_KEY, {}), dict):
        raise ValueError(f'{path} values need {ROWS_KEY} to be a dictionary')
    return values


def check_patch(contract: Contract, applied: bool):
    if not applied:
        return
    for relative, markers in PATCH_MARKERS.items():
        source = contract.text(relative)
        for marker in markers:
            if marker not in source:
                contract.fail(f'{relative} no longer carries Parc\'s settings hook: {marker}')


def check_visibility(contract: Contract, visibility: dict, applied: bool):
    source = contract.text(PAGE_VISIBILITY)
    routes = contract.text(ROUTES)
    if "if (!loadTimeData.getBoolean('isGuest')) {" not in source:
        contract.fail(f'{PAGE_VISIBILITY} lost the guest check the Parc patch precedes')
    keys = interface_keys(source, 'PageVisibility')
    if keys is None:
        contract.fail(f'{PAGE_VISIBILITY} no longer exports interface PageVisibility')
        return
    if visibility.get('people') is False:
        if HOME_FALLBACK not in routes and (applied or 'return routes.PEOPLE;' not in routes):
            contract.fail('people cannot be hidden: route.ts no longer lets the settings home page '
                          'fall back from it')
        for name in HOME_SECTIONS:
            if f'r.{name} = r.BASIC.createSection(' not in routes:
                contract.fail(f'route.ts no longer creates the {name} section the settings home '
                              'page falls back to')
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


class Element:
    def __init__(self, tag: str, attributes: dict, parent):
        self.tag = tag
        self.attributes = attributes
        self.parent = parent
        self.children = []


class TemplateTree(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.root = Element('', {}, None)
        self.open = [self.root]

    def add(self, tag: str, attributes: list) -> Element:
        element = Element(tag, {name: value or '' for name, value in attributes}, self.open[-1])
        self.open[-1].children.append(element)
        return element

    def handle_starttag(self, tag, attrs):
        if tag != 'if':
            element = self.add(tag, attrs)
            if tag not in VOID_TAGS:
                self.open.append(element)

    def handle_startendtag(self, tag, attrs):
        if tag != 'if':
            self.add(tag, attrs)

    def handle_endtag(self, tag):
        for index in range(len(self.open) - 1, 0, -1):
            if self.open[index].tag == tag:
                del self.open[index:]
                return


def template_tree(template: str) -> Element:
    start = template.find('<!--_html_template_start_-->')
    end = template.find('<!--_html_template_end_-->')
    parser = TemplateTree()
    parser.feed(template[start:end] if 0 <= start < end else template)
    parser.close()
    return parser.root


def parse_selector(text: str) -> list:
    parts, end = parse_complex(text, 0, False)
    if end != len(text):
        raise ValueError(text)
    return parts


def parse_complex(text: str, index: int, relative: bool):
    parts = []
    if relative:
        lead = re.match(r'\s*([>+~]?)\s*', text[index:])
        parts.append(lead.group(1) or ' ')
        index += lead.end()
    while True:
        compound, index = parse_compound(text, index)
        parts.append(compound)
        combinator = re.match(r'\s*([>+~])\s*|\s+(?=[^\s)])', text[index:])
        if not combinator:
            return parts, index
        parts.append(combinator.group(1) or ' ')
        index += combinator.end()


def parse_compound(text: str, index: int):
    compound = {'tag': None, 'id': [], 'class': [], 'attribute': [], 'has': []}
    tag = re.match(r'[a-z][a-z0-9-]*', text[index:])
    if tag:
        compound['tag'] = tag.group(0)
        index += tag.end()
    start = index
    while match := SIMPLE.match(text, index):
        if match.group(0) == ':has(':
            inner, index = parse_complex(text, match.end(), True)
            close = re.match(r'\s*\)', text[index:])
            if not close:
                raise ValueError(text)
            compound['has'].append(inner)
            index += close.end()
        elif match.group(1):
            compound['id'].append(match.group(1))
            index = match.end()
        elif match.group(2):
            compound['class'].append(match.group(2))
            index = match.end()
        else:
            compound['attribute'].append((match.group(3), match.group(4)))
            index = match.end()
    if compound['tag'] is None and index == start:
        raise ValueError(text)
    return compound, index


def supported(selector: str) -> bool:
    try:
        parse_selector(selector)
    except ValueError:
        return False
    return True


def descendants(element: Element):
    for child in element.children:
        yield child
        yield from descendants(child)


def compound_matches(element: Element, compound: dict, scope, root: Element) -> bool:
    if compound is SCOPE:
        return element is scope
    attributes = element.attributes
    return ((compound['tag'] is None or element.tag == compound['tag'])
            and all(attributes.get('id') == name for name in compound['id'])
            and all(name in attributes.get('class', '').split() for name in compound['class'])
            and all(name in attributes and (value is None or attributes[name] == value)
                    for name, value in compound['attribute'])
            and all(any(complex_matches(candidate, [SCOPE, *inner], element, root)
                        for candidate in descendants(root))
                    for inner in compound['has']))


def complex_matches(element: Element, parts: list, scope, root: Element) -> bool:
    if element is None or not compound_matches(element, parts[-1], scope, root):
        return False
    if len(parts) == 1:
        return True
    combinator, rest = parts[-2], parts[:-2]
    siblings = element.parent.children[:element.parent.children.index(element)]
    if combinator == '>':
        return complex_matches(element.parent, rest, scope, root)
    if combinator == '+':
        return bool(siblings) and complex_matches(siblings[-1], rest, scope, root)
    if combinator == '~':
        return any(complex_matches(sibling, rest, scope, root) for sibling in siblings)
    ancestor = element.parent
    while ancestor is not None:
        if complex_matches(ancestor, rest, scope, root):
            return True
        ancestor = ancestor.parent
    return False


def matches_in(template: str, selector: str) -> bool:
    root = template_tree(template)
    parts = parse_selector(selector)
    return any(complex_matches(element, parts, None, root) for element in descendants(root))


def selector_parts(selector: str) -> list:
    plain = re.sub(r'\[[^\]]*\]', ' ', selector)
    parts = [('id', name, None) for name in re.findall(rf'#({NAME})', plain)]
    parts += [('class', name, None) for name in re.findall(rf'\.({NAME})', plain)]
    parts += [('attribute', name, value or None) for name, value in re.findall(ATTRIBUTE, selector)]
    parts += [('tag', name, None) for name in re.findall(r'(?:^|[\s>+~(])([a-z][a-z0-9-]*)', plain)]
    return parts


def renders(template: str, kind: str, name: str, value) -> bool:
    if kind == 'id':
        pattern = rf'(?<![\w-])id="{re.escape(name)}"'
    elif kind == 'class':
        pattern = rf'(?<![\w-])class="[^"]*(?<![\w-]){re.escape(name)}(?![\w-])'
    elif kind == 'attribute' and value is not None:
        pattern = rf'(?<![\w-]){re.escape(name)}="{re.escape(value)}"'
    elif kind == 'attribute':
        pattern = rf'(?<![\w-]){re.escape(name)}[\s=>]'
    else:
        pattern = rf'<{re.escape(name)}[\s>]'
    return re.search(pattern, template) is not None


def child_view(template: str, selector: str) -> bool:
    match = re.fullmatch(rf'#({NAME})', selector)
    if not match:
        return False
    tag = re.search(rf'<[a-z][\w-]*\s[^>]*?(?<![\w-])id="{match.group(1)}"[^>]*>', template)
    return tag is not None and 'data-parent-view-id=' in tag.group(0)


def host_sources(contract: Contract) -> dict:
    hosts = {}
    for path, text in contract.files(SETTINGS_JS, ('.ts',)).items():
        for tag in re.findall(r"static get is\(\) \{\s*return '([a-z][a-z0-9-]*)';", text):
            hosts.setdefault(tag, []).append(path)
    return hosts


def template_for(contract: Contract, source: Path):
    stem = source.name[:-len('.ts')]
    for name in (f'{stem}.html.ts', f'{stem}.html'):
        path = source.with_name(name)
        if path.is_file():
            relative = contract.relative(path)
            return relative, contract.text(relative)
    return None


def check_rows(contract: Contract, rows: dict):
    contract.watch(SETTINGS_JS)
    hosts = host_sources(contract)
    for host, selectors in sorted(rows.items()):
        if (not isinstance(selectors, list) or not selectors
                or not all(isinstance(selector, str) for selector in selectors)):
            contract.fail(f'{ROWS_KEY}.{host} must be a list of selectors')
            continue
        sources = hosts.get(host, [])
        if len(sources) != 1:
            contract.fail(f'{SETTINGS_JS} no longer defines {host} exactly once')
            continue
        found = template_for(contract, sources[0])
        if found is None:
            contract.fail(f'{contract.relative(sources[0])} has no template beside it for {host}')
            continue
        relative, template = found
        for selector in selectors:
            if not supported(selector):
                contract.fail(f'{host} row {selector!r} is not a selector Parc\'s hide list supports')
                continue
            missing = [(kind, name, value) for kind, name, value in selector_parts(selector)
                       if not renders(template, kind, name, value)]
            for kind, name, value in missing:
                shown = f'{name}="{value}"' if value is not None else name
                contract.fail(f'{relative} no longer renders the {kind} {shown} that Parc\'s '
                              f'{host} row {selector!r} names')
            if not missing and not matches_in(template, selector):
                contract.fail(f'{relative} no longer has a row shaped like Parc\'s {host} row '
                              f'{selector!r}')
        hooked = (re.search(r'<settings-(?:section|subpage)[\s>]', template) is not None
                  or host in SELF_HIDING_HOSTS
                  or all(child_view(template, selector) for selector in selectors))
        if not hooked:
            contract.fail(f'{host} renders no settings-section or settings-subpage, so Parc\'s hide '
                          'list never reaches its rows')


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
    if re.search(r'class SettingsUI\s+final\b', header):
        contract.fail(f'{SETTINGS_UI_HEADER} made SettingsUI final; Parc\'s reset guard subclasses it')
    source = contract.text(SETTINGS_UI)
    if 'OverrideHandleWebUIMessage' in header or 'OverrideHandleWebUIMessage' in source:
        contract.fail(f'{SETTINGS_UI_HEADER} now filters page messages itself, which Parc\'s reset '
                      'guard would replace')
    constructor = source.find('SettingsUI::SettingsUI(content::WebUI* web_ui)')
    body = source[constructor:constructor + 800] if constructor >= 0 else ''
    if 'content::WebUIDataSource::CreateAndAdd(' not in body or 'chrome::kChromeUISettingsHost' not in body:
        contract.fail(f'{SETTINGS_UI} no longer creates the settings data source in its constructor')


def check_reset(contract: Contract, values_source: str):
    handler = contract.text(RESET_HANDLER)
    if not re.search(r'"performResetProfileSettings",\s*base::BindRepeating\(\s*'
                     r'&ResetSettingsHandler::HandleResetProfileSettings', handler):
        contract.fail(f'{RESET_HANDLER} no longer handles performResetProfileSettings')
    if ('CHECK_EQ(3U, args.size());' not in handler
            or 'const bool& send_settings = args[1].GetBool();' not in handler):
        contract.fail(f'{RESET_HANDLER} no longer reads the report choice as the second of three '
                      'arguments, which Parc\'s reset guard turns off')
    if 'if (send_feedback && setting_snapshot_) {' not in handler:
        contract.fail(f'{RESET_HANDLER} no longer sends the settings report only when asked')
    if 'kResetProfileSettings[] = "performResetProfileSettings";' not in values_source:
        contract.fail('Parc\'s reset guard no longer names performResetProfileSettings')
    if not re.search(r'performResetProfileSettings\(\s*this\.\$\.sendSettings\.checked,',
                     contract.text(RESET_DIALOG)):
        contract.fail(f'{RESET_DIALOG} no longer sends the report choice from #sendSettings')
    if not re.search(r'<div slot="footer">\s*<cr-checkbox id="sendSettings"',
                     contract.text(RESET_DIALOG_HTML)):
        contract.fail(f'{RESET_DIALOG_HTML} moved the report checkbox out of the footer Parc hides')


def check_enhanced(contract: Contract, rows: dict, applied: bool):
    if any(('id', ENHANCED_ROW[1:], None) in selector_parts(selector)
           for selector in rows.get('settings-security-page', [])):
        contract.fail(f'Parc\'s settings-security-page list hides {ENHANCED_ROW}, which leaves Security '
                      'with nothing selected for people on Enhanced protection')
    if not re.search(r'<settings-radio-group id="safeBrowsingRadioGroup" no-set-pref\s+'
                     r'pref-key="generated\.safe_browsing"', contract.text(SECURITY_PAGE_HTML)):
        contract.fail(f'{SECURITY_PAGE_HTML} no longer binds its radio group to generated.safe_browsing')
    radio = (r'<settings-collapse-radio-button id="safeBrowsingEnhanced"\s+'
             r'name="\$\{SafeBrowsingSetting\.ENHANCED\}"')
    if not re.search(radio, contract.text(SECURITY_PAGE_HTML)):
        contract.fail(f'{SECURITY_PAGE_HTML} no longer renders the Enhanced radio Parc shows only '
                      'while it is chosen')
    elif applied and not re.search(radio + r'\s+' + re.escape(ENHANCED_SHOWN),
                                   contract.text(SECURITY_PAGE_HTML)):
        contract.fail(f'{SECURITY_PAGE_HTML} binds Parc\'s Enhanced visibility to some other element')
    if ('#include=cr-shared-style-lit' not in contract.text(SECURITY_PAGE_CSS)
            or '#include=cr-hidden-style-lit' not in contract.text(SHARED_STYLE)
            or not re.search(r'\[hidden\],\s*:host\(\[hidden\]\) \{\s*display: none !important;',
                             contract.text(HIDDEN_STYLE))):
        contract.fail(f'{SECURITY_PAGE_CSS} no longer hides [hidden] radios')
    page = contract.text(SECURITY_PAGE)
    if ("'generated.safe_browsing': 'safeBrowsingPref_'" not in page
            or 'safeBrowsingPref_: {type: Object}' not in page):
        contract.fail(f'{SECURITY_PAGE} no longer keeps the Safe Browsing choice in safeBrowsingPref_')
    if "radio.matches(':not([disabled]):not([hidden])')" not in contract.text(RADIO_GROUP):
        contract.fail(f'{RADIO_GROUP} no longer skips hidden radios, so the keyboard could pick '
                      'a hidden Enhanced radio')


def check_brand(contract: Contract, values_source: str):
    if 'extern const char* g_brand_for_testing;' not in contract.text(BRAND_HEADER):
        contract.fail(f'{BRAND_HEADER} no longer exposes the brand override Parc clears')
    mac = contract.text(BRAND_MAC)
    internal = mac.find('std::string GetBrandInternal() {')
    getter = re.search(r'bool GetBrand\(std::string\* brand\) \{\s*if \(g_brand_for_testing\) \{\s*'
                       r'\*brand = g_brand_for_testing;\s*return true;\s*\}', mac)
    call = mac.find('GetBrandInternal()', internal + len('std::string GetBrandInternal() {'))
    if (internal < 0 or not getter or mac.count('GetBrandInternal(') != 2
            or not getter.end() <= call < mac.find('\n}\n', getter.end())):
        contract.fail(f'{BRAND_MAC} no longer reads the brand files only after the override Parc sets')
    elif any(not internal < match.start() < getter.start()
             for match in re.finditer(r'Brand\.plist', mac)):
        contract.fail(f'{BRAND_MAC} reads Chrome\'s brand files outside the override Parc sets')
    if not re.search(r'bool GetRlzBrand\(std::string\* brand\) \{(?:(?!\n\}).)*#else\s*'
                     r'return GetBrand\(brand\);', contract.text(BRAND_SOURCE), re.S):
        contract.fail(f'{BRAND_SOURCE} no longer takes the RLZ brand from GetBrand')
    if not re.search(r'google_brand::GetBrand\(&brandcode_\);\s*if \(brandcode_\.empty\(\)\) \{\s*'
                     r'return;\s*\}\s*config_fetcher_ = std::make_unique<BrandcodeConfigFetcher>',
                     contract.text(RESETTER)):
        contract.fail(f'{RESETTER} no longer skips the brand code download when there is no brand')
    if NO_BRAND not in values_source:
        contract.fail('Parc no longer clears the brand code')


def run(chromium: Path, values_path: Path, startup_policy: Path, applied: bool) -> Contract:
    contract = Contract(chromium)
    contract.read_paths.add(values_path)
    values = load_values(values_path)
    flags = {key: value for key, value in values.items() if key not in (VISIBILITY_KEY, ROWS_KEY)}
    check_patch(contract, applied)
    check_visibility(contract, values[VISIBILITY_KEY], applied)
    check_rows(contract, values.get(ROWS_KEY, {}))
    check_flags(contract, flags)
    check_features(contract, startup_policy)
    check_mechanism(contract)
    values_source = values_path.read_text(encoding='utf-8')
    check_reset(contract, values_source)
    check_enhanced(contract, values.get(ROWS_KEY, {}), applied)
    check_brand(contract, values_source)
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
