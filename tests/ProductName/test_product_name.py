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
# Chrome in any form or script a translation gives the browser, in lower case
# outside URLs, and Google's devices and operating system wrongly renamed.
CHROME = re.compile(r"[CС]hrom(?!ebook|ebox|ebit|ecast|e\s?OS|ium)|(?<![\w/:.-])chrom(?!ium|e[\w/:.-])|"
                    r"(?<![^\W\d_])hrome|क्रोम|ক্রোম|குரோம|ක්\u200dරෝම")
DEVICE = re.compile(r"Parc(?:book|box|bit|cast|\s?OS)")
# The English says Chrome, other than for Google's devices and operating system.
SAYS_CHROME = re.compile(r"Chrome(?!book|box|bit|cast|\s?OS)")
# The macOS engine's grit defines that are true.
MAC_DEFINES = {
    "chrome_root_store_cert_management_ui", "enable_cef", "enable_compose", "enable_dice_support",
    "enable_extensions", "enable_extensions_core", "enable_hangout_services_extension",
    "enable_pdf", "enable_pdf_ink2", "enable_pdf_save_to_drive", "enable_plugins",
    "enable_print_preview", "enable_printing", "enable_private_insights",
    "enable_pseudolocales", "enable_screen_ai_service", "enable_screen_capture",
    "enable_supervised_users", "enable_webui_certificate_viewer",
    "enable_webui_contextual_tasks_composebox", "enable_webui_ntp", "optimize_webui",
    "toolkit_views", "use_blink", "use_titlecase",
}

# Messages whose English Chrome stays, by why it is still true. Every message
# the macOS engine compiles whose English says Chrome is here or in
# parc_branding.CHROME_MEANS_PARC.
CHROME_KEPT = {
    "Google product or service": frozenset({
        # The Chrome Web Store.
        "IDS_EXTENSIONS_BLOCKLISTED_CWS_POLICY_VIOLATION",
        "IDS_EXTENSIONS_DISABLED_PUBLISHED_IN_STORE_REQUIRED_BY_POLICY",
        "IDS_EXTENSIONS_DISABLED_UNSUPPORTED_DEVELOPER_MODE",
        "IDS_EXTENSIONS_DISABLED_UNSUPPORTED_DEVELOPER_MODE_DETAILS",
        "IDS_EXTENSIONS_INSTALL_LOCATION_UNKNOWN",
        "IDS_EXTENSIONS_ITEM_CHROME_WEB_STORE",
        "IDS_EXTENSIONS_ITEM_SOURCE_WEBSTORE",
        "IDS_EXTENSIONS_MV2_DEPRECATION_MESSAGE_WARNING_SUBTITLE",
        "IDS_EXTENSIONS_MV2_DEPRECATION_PANEL_WARNING_SUBTITLE",
        "IDS_EXTENSIONS_NO_INSTALLED_ITEMS",
        "IDS_EXTENSIONS_SC_POLICY_VIOLATION_OFF",
        "IDS_EXTENSIONS_SC_POLICY_VIOLATION_ON",
        "IDS_EXTENSIONS_SIDEBAR_DISCOVER_MORE",
        "IDS_EXTENSIONS_SUBMENU_CHROME_WEBSTORE_ITEM",
        "IDS_EXTENSION_WEB_STORE_TITLE",
        "IDS_NTP_CUSTOMIZE_CHROME_WEBSTORE_LABEL",
        "IDS_NTP_WEBSTORE_TOAST_MESSAGE",
        "IDS_OPEN_WEB_STORE_BUTTON_TEXT",
        "IDS_POLICY_OFF_CWS_URL_ERROR",
        "IDS_SAFETY_CHECK_EXTENSIONS_POLICY_VIOLATION",
        "IDS_SETTINGS_ACCESSIBILITY_WEB_STORE",
        # Chrome Apps.
        "IDS_APP_PAUSE_HEADING_FOR_WEB_APPS",
        "IDS_DEPRECATED_APPS_LEARN_MORE_AX_LABEL",
        "IDS_DEPRECATED_APPS_MONITOR_RENDERER",
        "IDS_EXTENSIONS_APPS_TITLE",
        "IDS_FORCE_INSTALLED_DEPRECATED_APPS_CONTENT",
        "IDS_FORCE_INSTALLED_PREINSTALLED_DEPRECATED_APPS_CONTENT",
        "IDS_QUIT_WITH_APPS_EXPLANATION",
        "IDS_QUIT_WITH_APPS_QUIT_LABEL",
        # Chrome sign-in and sync, and what is built on them.
        "IDS_ACCESS_CODE_CAST_ERROR_PROFILE_SYNC",
        "IDS_ACC_OMNIBOX_PEDAL_MANAGE_SYNC_SUFFIX_UPDATED",
        "IDS_ACC_OMNIBOX_PEDAL_MANAGE_SYNC_UPDATED",
        "IDS_COLLABORATION_CHROME_OUT_OF_DATE_ERROR_DIALOG_CONTINUE_BODY",
        "IDS_COLLABORATION_CHROME_OUT_OF_DATE_ERROR_DIALOG_HEADER",
        "IDS_COLLABORATION_CHROME_OUT_OF_DATE_ERROR_DIALOG_UPDATE_BUTTON",
        "IDS_COLLABORATION_ENTREPRISE_SIGNIN_DISABLED_BODY",
        "IDS_COLLABORATION_ENTREPRISE_SIGNIN_DISABLED_SYNC_HISTORY_BODY",
        "IDS_COLLABORATION_JOIN_BUTTON_CHROME_OUT_OF_DATE_ERROR_DIALOG_BODY",
        "IDS_COLLABORATION_SHARED_TAB_GROUPS_PANEL_OUT_OF_DATE_MESSAGE_CELL_TEXT",
        "IDS_COLLABORATION_SHARE_BUTTON_CHROME_OUT_OF_DATE_ERROR_DIALOG_BODY",
        "IDS_COLLABORATION_SIGNED_OUT_BODY",
        "IDS_COLLABORATION_SIGNIN_BOTTOM_SHEET_TITLE",
        "IDS_COLLABORATION_SIGNIN_DESCRIPTION",
        "IDS_COMPOSEBOX_DRIVE_CONTEXT_MENU_OPTION_SIGNIN_PROMO_TITLE",
        "IDS_DATA_SHARING_NEED_SIGN_IN_AND_SYNC_HISTORY_BODY",
        "IDS_DATA_SHARING_ORGANIZATION_DISALLOW_SIGN_IN_BODY",
        "IDS_DATA_SHARING_SIGNED_OUT_BODY",
        "IDS_DEL_GOOGLE_COOKIES_SIGNOUT_LINK",
        "IDS_ENTERPRISE_PROXY_AUTHN_ERROR_HEADING",
        "IDS_MANAGEMENT_EXTENSION_REPORT_USERNAME",
        "IDS_OMNIBOX_PEDAL_MANAGE_SYNC_SUGGESTION_CONTENTS_UPDATED",
        "IDS_PASSWORDS_SAVE_PRIMING_PROMO_BODY_NOT_SIGNED_IN",
        "IDS_PASSWORDS_SAVE_PRIMING_PROMO_SCREENREADER",
        "IDS_PASSWORD_MANAGER_UI_SHARE_PASSWORD_ERROR_DESCRIPTION",
        "IDS_PASSWORD_MANAGER_UI_SHARE_PASSWORD_MEMBER_UNAVAILABLE",
        "IDS_SEND_TAB_TO_SELF_NO_TARGET_DEVICE_LABEL",
        "IDS_SEND_TAB_TO_SELF_POST_SEND_SUCCESS_TOAST",
        "IDS_SEND_TAB_TO_SELF_POST_SEND_SUCCESS_TOAST_ANDROID",
        "IDS_SEND_TAB_TO_SELF_POST_SEND_SUCCESS_TOAST_NO_EMAIL_ANDROID",
        "IDS_SEND_TAB_TO_SELF_POST_SEND_THROTTLED_TOAST",
        "IDS_SEND_TAB_TO_SELF_POST_SEND_THROTTLED_TOAST_ANDROID",
        "IDS_SEND_TAB_TO_SELF_SIGN_IN_PROMO_LABEL",
        "IDS_SETTINGS_ENCRYPT_WITH_SYNC_PASSPHRASE_LABEL",
        "IDS_SETTINGS_PEOPLE_SIGN_IN_PROMPT",
        "IDS_SYNC_UNAVAILABLE_FOR_NON_GOOGLE_ACCOUNT",
        "IDS_TAB_GROUP_DELETION_DIALOG_MISSING_EMAIL",
        "IDS_TIPS_NOTIFICATIONS_RECENT_TABS_SUBTITLE",
        "IDS_TIPS_NOTIFICATIONS_SIGNIN_TITLE",
        "IDS_TOOLBAR_BUTTON_SEND_TAB_TO_SELF_BUTTON_HINT_TEXT",
        "IDS_TUTORIAL_SEND_TAB_TO_SELF_SUCCESS_BODY",
        # Chrome Enterprise and Google's admin console.
        "IDS_CHROME_ENTERPRISE_RELEASE_NOTES",
        "IDS_ENTERPRISE_CONTENT_ANALYSIS_COPY_KEPT_IN_MANAGED_CHROME_MESSAGE",
        "IDS_MANAGEMENT_BANNER_PROMOTION_BTN",
        "IDS_MANAGEMENT_BANNER_PROMOTION_DESC",
        "IDS_MANAGEMENT_ENTERPRISE_REPORTING_VISIBLE_DATA",
        "IDS_MANAGEMENT_EXTENSION_TELEMETRY_VISIBLE_DATA",
        "IDS_MANAGEMENT_THREAT_PROTECTION",
        "IDS_MANAGEMENT_THREAT_PROTECTION_DESCRIPTION",
        "IDS_MANAGEMENT_THREAT_PROTECTION_DESCRIPTION_BY",
        "IDS_MANAGEMENT_THREAT_PROTECTION_MORE",
        "IDS_POLICY_BANNER_PROMOTION_BTN",
        "IDS_POLICY_BANNER_PROMOTION_DESC",
        "IDS_POLICY_CLOUD_MANAGEMENT_ENROLLMENT_ONLY_ERROR",
        "IDS_POLICY_IGNORED_UNAFFILIATED",
        # The Chrome Root Store and Root Program.
        "IDS_SETTINGS_CERTIFICATE_MANAGER_V2_CRS_CERTIFICATES",
        "IDS_SETTINGS_CERTIFICATE_MANAGER_V2_CRS_CERTIFICATES_DESCRIPTION",
        "IDS_SETTINGS_CERTIFICATE_MANAGER_V2_CRS_LEARN_MORE_LINK_ARIA_LABEL",
        # Google Chrome on other devices.
        "IDS_DOWNLOAD_CHROME",
        "IDS_IOS_DESKTOP_ADDRESS_PROMO_BUBBLE_FOOTER_DESCRIPTION_QR",
        "IDS_IOS_DESKTOP_PAYMENT_PROMO_BUBBLE_FOOTER_DESCRIPTION_QR",
        "IDS_NTP_MOBILE_PROMO_DESCRIPTION",
        "IDS_NTP_MOBILE_PROMO_HEADER",
        "IDS_PASSWORD_MANAGER_UI_WEB_PROMO_CARD_DESCRIPTION",
        # Google Chrome's own builds, which show these instead of the ones Parc
        # shows.
        "IDS_PASSWORD_MANAGER_RELAUNCH_CHROME_BUBBLE_ACCEPT_BUTTON_BRANDED",
        "IDS_PASSWORD_MANAGER_RELAUNCH_CHROME_BUBBLE_DESCRIPTION_BRANDED",
        # Chrome for Testing, Chrome Labs, Google's Chrome tips and help sites, Chrome's
        # Terms of Service and Google Family Link.
        "IDS_ACC_OMNIBOX_PEDAL_SEE_CHROME_TIPS",
        "IDS_ACC_OMNIBOX_PEDAL_SEE_CHROME_TIPS_SUFFIX",
        "IDS_CHROMELABS",
        "IDS_CHROME_FOR_TESTING_DISCLAIMER",
        "IDS_OMNIBOX_PEDAL_SEE_CHROME_TIPS_HINT",
        "IDS_OMNIBOX_PEDAL_SEE_CHROME_TIPS_SUGGESTION_CONTENTS",
        "IDS_SKIP_PARENT_PERMISSION_EXTENSION_INFORMATION",
        "IDS_TOS_NOTIFICATION_TITLE",
    }),
    "What Google does that Parc doesn't": frozenset({
        # Google Safe Browsing; Parc has no Google API key, so it is inert.
        "IDS_CHROME_NO_LONGER_SHOW_WARNINGS_NOTIFICATION_BODY",
        "IDS_DOWNLOAD_LOCAL_DECRYPTION_PROMPT_ALERT",
        "IDS_EXTENSIONS_BLOCKLISTED_POTENTIALLY_UNWANTED",
        "IDS_HARMFUL_V3_EXPLANATION_PARAGRAPH",
        "IDS_MALWARE_V3_EXPLANATION_PARAGRAPH",
        "IDS_PAGE_INFO_SUSPICIOUS_SITE_DETAILS",
        "IDS_PHISHING_V4_EXPLANATION_PARAGRAPH",
        "IDS_RESET_PASSWORD_LEARN_MORE",
        "IDS_RESET_PASSWORD_WARNING_EXPLANATION_PARAGRAPH_V2",
        "IDS_SAFE_BROWSING_ENHANCED_PROTECTION_MESSAGE",
        "IDS_SETTINGS_SAFETY_HUB_SB_ON_ENHANCED_SUBHEADER",
        "IDS_TAILORED_SECURITY_CONSENTED_ENABLE_MESSAGE_DESCRIPTION",
        "IDS_TAILORED_SECURITY_DIALOG_SETTINGS_BUTTON",
        "IDS_TAILORED_SECURITY_DISABLED_DIALOG_MAIN_TEXT",
        "IDS_TAILORED_SECURITY_ENABLED_DIALOG_MAIN_TEXT",
        "IDS_TAILORED_SECURITY_UNCONSENTED_MESSAGE_TITLE",
        "IDS_TAILORED_SECURITY_UNCONSENTED_MODAL_BODY",
        "IDS_TAILORED_SECURITY_UNCONSENTED_MODAL_TITLE",
        "IDS_TIPS_NOTIFICATIONS_ENHANCED_SAFE_BROWSING_TITLE",
        # Google Account features, which need Google sign-in.
        "IDS_AUTOFILL_ADDRESS_HOME_AND_WORK_RECORD_TYPE_NOTICE",
        "IDS_AUTOFILL_GMAIL_OTP_FILLING_TOGGLE_DESCRIPTION",
        "IDS_AUTOFILL_SAVE_CARD_CONFIRMATION_FAILURE_DESCRIPTION_TEXT",
        "IDS_AUTOFILL_SAVE_CARD_PROMPT_UPLOAD_EXPLANATION_AND_CARDHOLDER_NAME_TOOLTIP",
        "IDS_AUTOFILL_SAVE_CARD_PROMPT_UPLOAD_EXPLANATION_TOOLTIP",
        "IDS_AUTOFILL_SAVE_CARD_TO_WALLET_CONFIRMATION_FAILURE_DESCRIPTION_TEXT",
        "IDS_AUTOFILL_SAVE_IBAN_CONFIRMATION_FAILURE_DESCRIPTION_TEXT",
        "IDS_AUTOFILL_SAVE_IBAN_CONFIRMATION_FAILURE_HIT_MAX_STRIKE_DESCRIPTION_TEXT",
        "IDS_AUTOFILL_SAVE_IBAN_TO_WALLET_CONFIRMATION_FAILURE_DESCRIPTION_TEXT",
        "IDS_AUTOFILL_SAVE_IBAN_TO_WALLET_CONFIRMATION_FAILURE_HIT_MAX_STRIKE_DESCRIPTION_TEXT",
        "IDS_AUTOFILL_SYNCABLE_PROFILE_MIGRATION_PROMPT_NOTICE",
        "IDS_AUTOFILL_WALLET_REMINDER_NOTICE_TITLE",
        "IDS_CLEAR_BROWSING_DATA_HISTORY_NOTICE",
        "IDS_CLEAR_BROWSING_DATA_HISTORY_NOTICE_TITLE",
        "IDS_PAYMENTS_CARD_AND_ADDRESS_SETTINGS_SIGNED_IN",
        "IDS_PROFILES_DASHER_FEATURE_DISABLED_TITLE",
        "IDS_SAVE_TO_DRIVE_FOLDER_NAME",
        "IDS_SETTINGS_PASSWORD_CHANGE_SUBLABEL",
        # Google's updater; Parc updates itself.
        "IDS_ABOUT_CHROME_AUTOUPDATE_ALL",
        "IDS_ACC_OMNIBOX_PEDAL_UPDATE_CHROME",
        "IDS_ACC_OMNIBOX_PEDAL_UPDATE_CHROME_SUFFIX",
        "IDS_OMNIBOX_PEDAL_UPDATE_CHROME_HINT",
        "IDS_OMNIBOX_PEDAL_UPDATE_CHROME_SUGGESTION_CONTENTS",
        "IDS_UPDATER_HELP_CENTER_TOOLTIP",
        # Reports, surveys and other data sent to Google, Google's translation and
        # shopping services, and Google's tips notifications.
        "IDS_CHROME_FINDS_NOTIFICATIONS_HELPFUL_BUTTON_TEXT",
        "IDS_MEDIA_ROUTER_FEEDBACK_PRIVACY_DATA_USAGE",
        "IDS_OMNIBOX_TRACK_PRICE_DIALOG_TITLE_FIRST_RUN",
        "IDS_SAFE_BROWSING_HATS_CUSTOM_INVITATION",
        "IDS_SETTINGS_ACCESSIBLE_IMAGE_LABELS_SUBTITLE",
        "IDS_SETTINGS_CAPTIONS_MANAGE_LANGUAGES_SUBTITLE",
        "IDS_SETTINGS_ENABLE_LOGGING_PREF",
        "IDS_SETTINGS_SYSTEM_FEATURE_NOTIFICATIONS_LABEL",
        "IDS_TIPS_NOTIFICATIONS_HELPFUL_BUTTON_TEXT",
    }),
    "Feature Parc excludes": frozenset({
        # Gemini and Chrome's other AI features.
        "IDS_ACTOR_EXPERIMENTAL_TRIGGERING_NOTIFICATION_BODY",
        "IDS_ACTOR_EXPERIMENTAL_TRIGGERING_NOTIFICATION_BODY_FALLBACK",
        "IDS_ACTOR_NOTIFICATION_BODY_COMPLETE",
        "IDS_ACTOR_NOTIFICATION_BUTTON_GO_TO_CHROME",
        "IDS_AUTOFILL_AI_ENTITY_SUPPRESSION_CONFIRMATION_BODY",
        "IDS_AUTOFILL_AI_ENTITY_SUPPRESSION_CONFIRMATION_TITLE",
        "IDS_AUTOFILL_AI_LOCAL_SAVE_NOTIFICATION_DESCRIPTION",
        "IDS_AUTOFILL_AT_MEMORY_SEARCH_AFFORDANCE_TITLE",
        "IDS_AUTOFILL_AT_MEMORY_UNSUPPORTED_QUERY_DESCRIPTION",
        "IDS_COMPARE_HISTORY_INFO",
        "IDS_CONTEXTUAL_CUEING_SETTINGS_CONSIDER_1_NON_PRIVATE",
        "IDS_CONTEXTUAL_CUEING_SETTINGS_CONSIDER_1_PRIVATE",
        "IDS_CONTEXTUAL_CUEING_SETTINGS_CONSIDER_2",
        "IDS_CONTEXTUAL_CUEING_SETTINGS_WHEN_ON_2",
        "IDS_EDUCATIONAL_TIP_GLIC_DESCRIPTION",
        "IDS_EDUCATIONAL_TIP_GLIC_TITLE",
        "IDS_GLIC_EXPERIMENTAL_OPT_IN_TITLE",
        "IDS_GLIC_INELIGIBLE_ACCOUNT_NOTICE_HEADER",
        "IDS_GLIC_LOCATION_MISMATCH_NOTICE",
        "IDS_GLIC_LOCATION_MISMATCH_NOTICE_HEADER",
        "IDS_GLIC_SETTING_LABEL",
        "IDS_GLIC_SHORTCUT_IPH_TEXT",
        "IDS_GLIC_TRYIT_BODY",
        "IDS_HISTORY_CRITICAL_ACTION_APP_MENU_IPH_BODY",
        "IDS_HISTORY_EMBEDDINGS_ANSWERS_PROMO_BODY",
        "IDS_PEEK_STATE_ACCESSIBLE_LABEL",
        "IDS_PEEK_STATE_CLOSE_BUTTON_DESCRIPTION",
        "IDS_SETTINGS_AI_PAGE_MAIN_SUBLABEL_3",
        "IDS_SETTINGS_AI_PAGE_MAIN_TITLE",
        "IDS_SETTINGS_AI_PAGE_TITLE",
        "IDS_SETTINGS_GLIC_EXPERIMENTAL_TRIGGERING_CONSIDER_2",
        "IDS_SETTINGS_GLIC_EXPERIMENTAL_TRIGGERING_SUB_LABEL",
        "IDS_SETTINGS_GLIC_EXPERIMENTAL_TRIGGERING_SUB_LABEL_V2",
        "IDS_SETTINGS_GLIC_EXPERIMENTAL_TRIGGERING_WHEN_ON_1",
        "IDS_SETTINGS_GLIC_INLINE_CUE_MENU_PREVIEW_TEXT",
        "IDS_SETTINGS_GLIC_PERMISSIONS_CHROME_WEB_ACTUATION_TOGGLE",
        "IDS_SETTINGS_GLIC_PERMISSIONS_CHROME_WEB_ACTUATION_TOGGLE_LEARN_MORE_ARIA_LABEL",
        "IDS_SETTINGS_GLIC_PERMISSIONS_CHROME_WEB_ACTUATION_TOGGLE_SUBLABEL",
        "IDS_SETTINGS_GLIC_PERMISSIONS_CHROME_WEB_ACTUATION_TOGGLE_SUBLABEL_V2",
        "IDS_SETTINGS_HISTORY_SEARCH_WITH_ANSWERS_CONSIDER_DATA_ENCRYPTED",
        "IDS_SETTINGS_PRIVACY_GUIDE_COMPLETION_CARD_AI_SETTINGS_LABEL",
        "IDS_SETTINGS_SUGGESTIONS_FROM_GEMINI_WHEN_USED_1",
        "IDS_SKILLS_DISABLED_ERROR_PAGE_DESCRIPTION",
        "IDS_SKILLS_ERROR_PAGE_DESCRIPTION",
        "IDS_SKILLS_SIDEBAR_FOOTER_BRANDING",
        "IDS_SKILLS_SIGN_IN_TO_CHROME",
        "IDS_STS_IPH_DEFAULT_ON_BODY",
        "IDS_STS_IPH_PROMPT_FIRST_TIME_ADDING_CONTEXT_MESSAGE_BODY",
        "IDS_STS_IPH_TRY_IT_BODY",
        "IDS_STS_SETTINGS_OPTION_1_CHOOSE_HOW_RELEVANT_OPEN_TABS_CAN_BE_USED_V3",
        # Other platforms.
        "IDS_IOS_ACC_OMNIBOX_PEDAL_SET_CHROME_AS_DEFAULT_BROWSER",
        "IDS_IOS_ACC_OMNIBOX_PEDAL_SET_CHROME_AS_DEFAULT_BROWSER_SUFFIX",
        "IDS_IOS_OMNIBOX_PEDAL_PLAY_CHROME_DINO_GAME_HINT",
        "IDS_IOS_OMNIBOX_PEDAL_RUN_CHROME_SAFETY_CHECK_HINT",
        "IDS_IOS_OMNIBOX_PEDAL_SET_CHROME_AS_DEFAULT_BROWSER_HINT",
        "IDS_IOS_OMNIBOX_PEDAL_SET_CHROME_AS_DEFAULT_BROWSER_SUGGESTION_CONTENTS",
        "IDS_IOS_OMNIBOX_PEDAL_VIEW_CHROME_HISTORY_HINT",
        "IDS_SUPPORT_TOOL_CHROMEOS_CHROME_USER_LOGS",
        "IDS_WEB_APP_INSTALL_CHROME_APPS_LOCATION",
    }),
}


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


class MacDefines(dict):
    """The macOS engine's grit defines, with every other define false."""

    def __init__(self):
        super().__init__(dict.fromkeys(MAC_DEFINES, True), safe_browsing_mode=1,
                         _google_chrome=False)

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
    def test_translations_name_parc(self):
        source = engine_source()
        sys.path.insert(0, str(source / "tools/grit"))
        from grit import grd_reader
        from grit.node import message
        branding = load_branding()
        kept = frozenset().union(*CHROME_KEPT.values())
        failures, unchanged, says_chrome = [], set(), set()
        for grd in STRING_GRDS:
            root = grd_reader.Parse(str(source / grd), defines=MacDefines(),
                                    target_platform="darwin", translate_genders=True)
            root.SetOutputLanguage("en")
            root.RunGatherers()
            for node in root.ActiveDescendants():
                if not isinstance(node, message.MessageNode) or not node.clique:
                    continue
                name, english = node.NameOrOffset(), node.clique.GetMessage()
                if SAYS_CHROME.search(branding._Text(english)):
                    says_chrome.add(name)
                if name in branding.UNCHANGED:
                    unchanged.add(name)
                    continue
                english_text = branding._Text(english)
                chrome_is_parc = name in branding.CHROME_MEANS_PARC or (
                    "Chromium" in english_text and "Chrome" not in english_text)
                # A translation's Chromium there is the translator's Chrome.
                kept_as_is = name in kept and "Chromium" not in english_text
                translations = [(("en", ""), english), *node.clique.clique.items()]
                for (language, gender), translation in translations:
                    text = branding.Rename(name, language, english, translation)
                    original = translation.GetRealContent()
                    if name in kept and (text != original if kept_as_is else
                                         CHROME.findall(text) != CHROME.findall(original)):
                        failures.append(f"{grd} {name} {language} {gender} changed: {text[:100]}")
                    if kept_as_is:
                        continue
                    text = text.replace(project_link(branding, translation), "")
                    text = OPERATING_SYSTEM.sub("", text)
                    endings = branding._ENDINGS.get(language, {})
                    if (CHROMIUM.search(text) or DEVICE.search(text) or
                            (chrome_is_parc and CHROME.search(text)) or
                            any(endings.get(m.group(2), m.group(2)) != m.group(2)
                                for m in branding._ENDING.finditer(text))):
                        failures.append(f"{grd} {name} {language} {gender}: {text[:100]}")
        self.assertEqual(failures, [])
        self.assertEqual(unchanged, branding.UNCHANGED)
        self.assertEqual(sum(map(len, CHROME_KEPT.values())), len(kept))
        self.assertFalse(kept & branding.CHROME_MEANS_PARC)
        self.assertEqual(sorted(says_chrome ^ (kept | branding.CHROME_MEANS_PARC)), [])


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
    "Engine/ParcNative/native_engine_entry.mm": {
        '"Native application must implement Chromium\'s sendEvent protocol"',
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
