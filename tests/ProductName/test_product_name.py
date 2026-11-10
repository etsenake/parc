"""Parc's UI names Parc, not Chromium, as the product.

The engine check runs every translation of every string the macOS engine
compiles through parc_branding.Rename, as grit does when it builds the
engine. It needs an engine workspace: PARC_ENGINE_WORKSPACE, or the main
checkout's work/engine.
"""
import importlib.util
import os
from pathlib import Path
import re
import subprocess
import sys
import unittest

REPO = Path(__file__).resolve().parents[2]

# Every translated string bundle the macOS engine compiles.
STRING_GRDS = (
    "chrome/app/chromium_strings.grd",
    "chrome/app/generated_resources.grd",
    "chrome/app/resources/locale_settings.grd",
    "chrome/app/resources/locale_settings_mac.grd",
    "components/components_chromium_strings.grd",
    "components/components_locale_settings.grd",
    "components/components_strings.grd",
    "components/components_variant_public_strings.grd",
    "components/guest_view/browser/slim_web_view/strings/slim_web_view_strings.grd",
    "components/omnibox/resources/omnibox_pedal_synonyms.grd",
    "components/policy/resources/policy_templates.build.grd",
    "components/privacy_sandbox_strings.grd",
    "device/bluetooth/bluetooth_strings.grd",
    "device/fido/fido_strings.grd",
    "extensions/strings/extensions_strings.grd",
    "services/services_strings.grd",
    "third_party/blink/public/strings/blink_strings.grd",
    "third_party/blink/public/strings/permission_element_strings.grd",
    "third_party/libaddressinput/chromium/address_input_strings.grd",
    "ui/accessibility/extensions/strings/accessibility_extensions_strings.grd",
    "ui/strings/app_locale_settings.grd",
    "ui/strings/auto_image_annotation_strings.grd",
    "ui/strings/ax_strings.grd",
    "ui/strings/ui_strings.grd",
)
# Chromium's letters, with a mnemonic, an h or u more or less or o and r
# swapped, as translators have spelt it, and its Hindi transliteration.
CHROMIUM = re.compile(r"C&?h?&?(?:r&?o&?u?|o&?r)&?m&?(?:i|u&?i)|क्रोमियम")
# Chromium OS keeps its name.
OPERATING_SYSTEM = re.compile(r"Chromium\s?OS")
# Chrome renamed inside the name of one of Google's devices.
DEVICE = re.compile(r"Parc(?:book|box|bit|cast|\s?OS)")


def engine_source():
    workspace = os.environ.get("PARC_ENGINE_WORKSPACE")
    if not workspace:
        common = subprocess.run(["git", "rev-parse", "--path-format=absolute", "--git-common-dir"],
                                cwd=REPO, capture_output=True, text=True, check=True).stdout
        workspace = Path(common.strip()).parent / "work/engine"
    source = Path(workspace) / "chromium/src"
    return source if (source / "tools/grit/grit").is_dir() else None


def load_branding():
    spec = importlib.util.spec_from_file_location(
        "parc_branding", REPO / "Engine/ParcHost/integration/parc_branding.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class ChromiumDefines(dict):
    """Chromium's branding, with every other grit define false."""

    def __init__(self):
        super().__init__(_google_chrome=False)

    def __contains__(self, name):
        return True

    def __missing__(self, name):
        return False


def project_link(branding, translation):
    """The start of the translation's link to the Chromium project, if any."""
    return "".join(part if isinstance(part, str) else part.GetOriginal()
                   for part, in_link in branding._Parts(translation) if in_link)


@unittest.skipUnless(engine_source(), "needs an engine workspace (PARC_ENGINE_WORKSPACE)")
class EngineStringsTests(unittest.TestCase):
    def test_no_translation_names_chromium(self):
        source = engine_source()
        sys.path.insert(0, str(source / "tools/grit"))
        from grit import grd_reader
        from grit.node import message
        branding = load_branding()
        failures, unchanged = [], set()
        for grd in STRING_GRDS:
            root = grd_reader.Parse(str(source / grd), defines=ChromiumDefines(), translate_genders=True)
            root.SetOutputLanguage("en")
            root.RunGatherers()
            for node in root:
                if not isinstance(node, message.MessageNode) or not node.clique:
                    continue
                name, english = node.NameOrOffset(), node.clique.GetMessage()
                if name in branding.UNCHANGED:
                    unchanged.add(name)
                    continue
                english_text = branding._Text(english)
                chrome_is_product = "Chromium" in english_text and "Chrome" not in english_text
                translations = [(("en", ""), english), *node.clique.clique.items()]
                for (language, gender), translation in translations:
                    text = branding.Rename(name, english, translation)
                    text = text.replace(project_link(branding, translation), "")
                    text = OPERATING_SYSTEM.sub("", text)
                    if (CHROMIUM.search(text) or DEVICE.search(text) or
                            (chrome_is_product and branding.CHROME.search(text))):
                        failures.append(f"{grd} {name} {language} {gender}: {text[:100]}")
        self.assertEqual(failures, [])
        self.assertEqual(unchanged, branding.UNCHANGED)


# Parc's own source and resources, which may name Chromium only where it is
# the engine, its project, another browser or an identifier.
SOURCE_ROOTS = ("Sources", "Resources", "Engine/ParcNative", "Engine/ParcRenderer",
                "Engine/ParcImport", "Engine/ParcInternalExtension",
                "Engine/ParcHost/native", "Engine/ParcHost/integration")
CODE = {".swift", ".m", ".mm", ".h", ".cc", ".c", ".js", ".ts"}
TEXT = {".html", ".css", ".json", ".strings", ".plist", ".sdef", ".svg", ".txt"}
LITERAL = re.compile(r"\"(?:[^\"\\\n]|\\.)*\"|'(?:[^'\\\n]|\\.)*'")
ALLOWED = {
    # The engine's version, its project and its open source credits.
    "Sources/ParcApp/AboutParcWindow.swift": {
        '"ParcChromiumVersion"',
        '"Chromium Engine Version \\(info.chromium)"',
        '"Parc is made possible by the Chromium open source project, Chromium’s open source software, and WebKit."',
        '"Chromium open source project"',
        '"Chromium’s open source software"',
    },
    "Sources/ParcApp/BrowserWindowController.swift": {
        '"Chromium Embedded Framework.framework"',
        '"Chromium Engine Version \\(engine)"',
    },
    # The engine framework's path.
    "Sources/ParcApp/AppDelegate.swift": {'"/Chromium Embedded Framework.framework"'},
    "Sources/ParcHelper/main.cc": {
        '"/../../../Chromium Embedded Framework.framework/"',
        '"Chromium Embedded Framework"',
    },
    # Parc's existing engine data directory.
    "Sources/ParcCore/BrowserStore.swift": {'"Chromium-v1"'},
    # The Chromium browser's own folders, Keychain item and name, to import
    # from it and share its native messaging hosts.
    "Sources/ParcCore/NativeMessagingHosts.swift": {'"Chromium"'},
    "Engine/ParcNative/native_import_discovery.mm": {
        '"org.chromium.Chromium"',
        '"Chromium"',
        '"Library/Application Support/Chromium"',
        '"Chromium Safe Storage"',
    },
    # Keychain items earlier Parc builds stored passwords under.
    "Engine/ParcNative/native_keychain_namespace.h": {
        '"Parc (Chromium compatibility)"',
        '"Chromium Safe Storage"',
        '"Chromium"',
    },
    # A user-agent token sites send.
    "Engine/ParcRenderer/parc_safari_identity.h": {'"Chromium/"'},
}


def chromium_strings(path):
    """Every string in |path| that names Chromium, with its line number."""
    text = path.read_text(errors="replace")
    for number, line in enumerate(text.splitlines(), 1):
        if "Chromium" not in line:
            continue
        if path.suffix in TEXT:
            yield number, line.strip()
        elif not line.strip().startswith(("//", "*", "/*", "#")):
            yield from ((number, literal) for literal in LITERAL.findall(line) if "Chromium" in literal)


class ParcSourceTests(unittest.TestCase):
    def test_parc_names_chromium_only_where_allowed(self):
        unexpected, seen = [], {}
        for root in SOURCE_ROOTS:
            for path in sorted((REPO / root).rglob("*")):
                if not path.is_file() or path.suffix not in CODE | TEXT:
                    continue
                relative = path.relative_to(REPO).as_posix()
                for number, string in chromium_strings(path):
                    if string in ALLOWED.get(relative, ()):
                        seen.setdefault(relative, set()).add(string)
                    else:
                        unexpected.append(f"{relative}:{number}: {string}")
        self.assertEqual(unexpected, [])
        self.assertEqual(seen, ALLOWED)


if __name__ == "__main__":
    unittest.main()
