# Copyright 2026 Parc contributors.
'''Names Parc, not Chromium or Chrome, in every string grit emits.

Grit renames Chromium in every translation, including inflected, misspelt
and transliterated forms. Chrome becomes Parc in the messages listed in
CHROME_MEANS_PARC, where it is the browser the user is running, and where a
translation says Chrome for an English Chromium. Every other Chrome names
Google's products and services, what Google does that Parc doesn't, or
features Parc excludes, and stays. Copyright notices and links to the
Chromium project keep Chromium's name.
'''

import re

PRODUCT = 'Parc'

# Their Chromium is the copyright holder or the open source project.
UNCHANGED = {
    'IDS_ABOUT_VERSION_COMPANY_NAME',
    'IDS_ABOUT_VERSION_COPYRIGHT',
    'IDS_SETTINGS_GLIC_INLINE_CUE_MENU_PREVIEW_TEXT',
}
PROJECT_LINK = ('BEGIN_LINK_CHROMIUM', 'END_LINK_CHROMIUM')

# Chromium, with a mnemonic anywhere in it; translators' misspellings and
# Welsh spelling; the Czech and Slovak case endings that replace its -um;
# its Hindi transliteration. Chromium OS, the operating system, keeps its
# name.
_CHROMIUM = re.compile(r'(?:C&?h&?r&?o&?m&?i&?u&?m|Chromiun|Chromimum|Chromeium|'
                       r'Chroumium|Chormium|Chromuim|Cromiwm|'
                       r'Chromi(a|u|em|om)\b|क्रोमियम)(?!\s?OS)')
_CASE_ENDING = {'a': 'u', 'u': 'u', 'em': 'em', 'om': 'om'}
# Chrome the browser, not Google's devices and operating system: as written,
# with a Cyrillic C, as a lower-case word outside URLs, or misspelt hrome,
# and Czech, Slovak and Slovenian declining its stem. Hindi, Nepali, Bengali,
# Tamil and Sinhala transliterate it.
_CHROME = re.compile(r'Chrom(u|a|em|ov[^\W\d_]*)\b|'
                     r'(?:Google\s)?[CС]hrome(?!book|box|bit|cast|\s?OS)|'
                     r'(?<![\w/:.-])chrome(?![\w/:.-])|'
                     r'(?<=-)hrome|क्रोम|ক্রোম|குரோம்|ක්\u200dරෝම්')
# The endings translators chose for the sound of Chrome or Chromium that
# Parc, said "park", takes differently. Tamil's also carry Chrome's final m.
_ENDINGS = {
    'az': {'u': 'ı', 'un': 'ın', 'um': 'ım', 'dur': 'dır', 'də': 'da'},
    'eu': {'k': 'ek', 'n': 'en', 'ko': 'eko', 'ren': 'en', 'ri': 'i',
           'rako': 'erako', 'rekin': 'ekin', 'tik': 'etik'},
    'fi': {'a': 'ia', 'n': 'in', 'en': 'iin', 'lle': 'ille', 'ssa': 'issa',
           'sta': 'ista'},
    'hu': {'mal': 'kal'},
    'kk': {'ге': 'қа', 'ға': 'қа', 'ді': 'ты', 'ды': 'ты', 'де': 'та',
           'да': 'та', 'дe': 'та', 'дегі': 'тағы', 'дағы': 'тағы',
           'мен': 'пен', 'нен': 'тан', 'нан': 'тан', 'нің': 'тың',
           'ның': 'тың'},
    'ko': {'을': '를', '이': '가', '은': '는', '으로': '로', '과': '와',
           '이나': '나'},
    'ky': {'ду': 'ты', 'дун': 'тын', 'га': 'ка', 'го': 'ка', 'да': 'та',
           'до': 'та', 'дан': 'тан', 'дон': 'тан', 'дагы': 'тагы',
           'суз': 'сыз'},
    'ta': {'மி': 'இ', 'மை': 'ஐ', 'மா': 'ஆ', 'மு': 'உ'},
    'tr': {'u': 'ı', 'un': 'ın', 'unuz': 'ınız', 'unuzu': 'ınızı',
           'da': 'ta', 'dan': 'tan', 'daki': 'taki'},
    'uz': {'ga': 'ka'},
}
_ENDING = re.compile(r"Parc(['’‘ʼ´-]?)(ம[ிைாு]|[^\W\d_]+)")
# Messages whose English Chrome is the browser the user is running.
CHROME_MEANS_PARC = frozenset({
    'IDS_ABH_PROMPT_SITE_ENGAGEMENT_PRIMARY_PARAGRAPH',
    'IDS_ABH_PROMPT_TYPICALLY_SECURE_BROWSING_PRIMARY_PARAGRAPH',
    'IDS_ACC_CHROME_TIP',
    'IDS_ACC_DISMISS_CHROME_TIP_BUTTON',
    'IDS_ACC_DISMISS_CHROME_TIP_FOCUSED_PREFIX',
    'IDS_ACC_DISMISS_CHROME_TIP_SUFFIX',
    'IDS_ACC_OMNIBOX_ACTION_HISTORY_CLUSTERS_SEARCH',
    'IDS_ACC_OMNIBOX_ACTION_HISTORY_CLUSTERS_SEARCH_SUFFIX',
    'IDS_ACC_OMNIBOX_IPH_LINK_SELECTED',
    'IDS_ACC_OMNIBOX_PEDAL_CLEAR_BROWSING_DATA',
    'IDS_ACC_OMNIBOX_PEDAL_CLEAR_BROWSING_DATA_SUFFIX',
    'IDS_ACC_OMNIBOX_PEDAL_CUSTOMIZE_CHROME_FONTS',
    'IDS_ACC_OMNIBOX_PEDAL_CUSTOMIZE_CHROME_FONTS_SUFFIX',
    'IDS_ACC_OMNIBOX_PEDAL_MANAGE_ADDRESSES',
    'IDS_ACC_OMNIBOX_PEDAL_MANAGE_ADDRESSES_SUFFIX',
    'IDS_ACC_OMNIBOX_PEDAL_MANAGE_CHROME_ACCESSIBILITY',
    'IDS_ACC_OMNIBOX_PEDAL_MANAGE_CHROME_ACCESSIBILITY_SUFFIX',
    'IDS_ACC_OMNIBOX_PEDAL_MANAGE_CHROME_DOWNLOADS',
    'IDS_ACC_OMNIBOX_PEDAL_MANAGE_CHROME_DOWNLOADS_SUFFIX',
    'IDS_ACC_OMNIBOX_PEDAL_MANAGE_CHROME_SETTINGS',
    'IDS_ACC_OMNIBOX_PEDAL_MANAGE_CHROME_SETTINGS_SUFFIX',
    'IDS_ACC_OMNIBOX_PEDAL_MANAGE_CHROME_THEMES',
    'IDS_ACC_OMNIBOX_PEDAL_MANAGE_COOKIES',
    'IDS_ACC_OMNIBOX_PEDAL_MANAGE_COOKIES_SUFFIX',
    'IDS_ACC_OMNIBOX_PEDAL_MANAGE_PASSWORDS',
    'IDS_ACC_OMNIBOX_PEDAL_MANAGE_PASSWORDS_SUFFIX',
    'IDS_ACC_OMNIBOX_PEDAL_MANAGE_SECURITY_SETTINGS',
    'IDS_ACC_OMNIBOX_PEDAL_MANAGE_SECURITY_SETTINGS_SUFFIX',
    'IDS_ACC_OMNIBOX_PEDAL_MANAGE_SITE_SETTINGS',
    'IDS_ACC_OMNIBOX_PEDAL_MANAGE_SITE_SETTINGS_SUFFIX',
    'IDS_ACC_OMNIBOX_PEDAL_MANAGE_SYNC',
    'IDS_ACC_OMNIBOX_PEDAL_MANAGE_SYNC_SUFFIX',
    'IDS_ACC_OMNIBOX_PEDAL_PLAY_CHROME_DINO_GAME',
    'IDS_ACC_OMNIBOX_PEDAL_PLAY_CHROME_DINO_GAME_SUFFIX',
    'IDS_ACC_OMNIBOX_PEDAL_RUN_CHROME_SAFETY_CHECK',
    'IDS_ACC_OMNIBOX_PEDAL_RUN_CHROME_SAFETY_CHECK_SUFFIX',
    'IDS_ACC_OMNIBOX_PEDAL_RUN_CHROME_SAFETY_CHECK_V2',
    'IDS_ACC_OMNIBOX_PEDAL_RUN_CHROME_SAFETY_CHECK_V2_SUFFIX',
    'IDS_ACC_OMNIBOX_PEDAL_SET_CHROME_AS_DEFAULT_BROWSER',
    'IDS_ACC_OMNIBOX_PEDAL_SET_CHROME_AS_DEFAULT_BROWSER_SUFFIX',
    'IDS_ACC_OMNIBOX_PEDAL_UPDATE_CREDIT_CARD',
    'IDS_ACC_OMNIBOX_PEDAL_UPDATE_CREDIT_CARD_SUFFIX',
    'IDS_ACC_OMNIBOX_PEDAL_VIEW_CHROME_HISTORY',
    'IDS_ACC_OMNIBOX_PEDAL_VIEW_CHROME_HISTORY_SUFFIX',
    'IDS_APP_HOME_REMOVE_APP',
    'IDS_APP_MANAGEMENT_INTENT_SHARING_BROWSER_OPEN',
    'IDS_APP_MENU_BUTTON_UPDATE_ALT3',
    'IDS_AUTOFILL_CHROME_LOGO_ACCESSIBLE_NAME',
    'IDS_AUTOFILL_CHURNED_USERS_CONFIRMATION_BUBBLE_DESCRIPTION',
    'IDS_AUTOFILL_MANDATORY_REAUTH_CONFIRMATION_EXPLANATION',
    'IDS_AUTOFILL_REMOVE_ACCOUNT_NAME_AND_EMAIL_PROFILE_SUGGESTION_CONFIRMATION_TITLE',
    'IDS_AUTOFILL_REMOVE_HOME_PROFILE_SUGGESTION_CONFIRMATION_TITLE',
    'IDS_AUTOFILL_REMOVE_VERIFIED_EMAIL_BODY',
    'IDS_AUTOFILL_REMOVE_WORK_PROFILE_SUGGESTION_CONFIRMATION_TITLE',
    'IDS_BAD_FLAGS_FROM_FILE_WARNING_MESSAGE',
    'IDS_CHROME_TIP',
    'IDS_CONNECTION_HELP_CONNECTION_NOT_PRIVATE_DETAILS',
    'IDS_CONTROLLED_BY_AUTOMATION',
    'IDS_DEV_TOOLS_CONNECTION_DIALOG_MESSAGE_PART_1',
    'IDS_DOWNLOAD_BUBBLE_ESB_PROMO',
    'IDS_EXTENSIONS_ZERO_STATE_CHIPS_IPH_DESCRIPTION',
    'IDS_EXTENSIONS_ZERO_STATE_CHIPS_WITH_LINK_IPH_DESCRIPTION',
    'IDS_EXTENSIONS_ZERO_STATE_PLAIN_LINK_IPH_DESCRIPTION',
    'IDS_EXTENSIONS_ZERO_STATE_PROMO_CUSTOM_ACTION_IPH_DESCRIPTION',
    'IDS_EXTENSION_EXTERNAL_INSTALL_ALERT_BUBBLE_HEADING_APP',
    'IDS_EXTENSION_EXTERNAL_INSTALL_ALERT_BUBBLE_HEADING_EXTENSION',
    'IDS_EXTENSION_EXTERNAL_INSTALL_ALERT_BUBBLE_HEADING_THEME',
    'IDS_EXTENSION_INSTALL_PROCESS_CRASHED',
    'IDS_GEOLOCATION_QUIET_PERMISSION_BUBBLE_PREDICTION_SERVICE_DESCRIPTION',
    'IDS_HARMFUL_V3_PRIMARY_PARAGRAPH',
    'IDS_HEAVY_AD_INTERVENTION_SUMMARY',
    'IDS_HTTPS_ONLY_MODE_FOR_TYPICALLY_SECURE_BROWSING_PRIMARY_PARAGRAPH',
    'IDS_HTTPS_ONLY_MODE_WITH_SITE_ENGAGEMENT_PRIMARY_PARAGRAPH',
    'IDS_INTENT_PICKER_BUBBLE_VIEW_STAY_IN_CHROME',
    'IDS_IWA_INSTALLER_VERIFICATION_ERROR_TITLE',
    'IDS_IWA_INSTALLER_VERIFICATION_TITLE',
    'IDS_MALWARE_V3_PRIMARY_PARAGRAPH',
    'IDS_MEDIA_ROUTER_LOCAL_DISCOVERY_PERMISSION_REJECTED_LABEL',
    'IDS_MEDIA_TAB_CAPTURE_NOTIFICATION_TEXT',
    'IDS_MEDIA_TAB_CAPTURE_WITH_AUDIO_NOTIFICATION_TEXT',
    'IDS_MITM_SOFTWARE_HEADING',
    'IDS_MULTISTEP_FILTER_IPH_BODY',
    'IDS_MULTISTEP_FILTER_IPH_BODY_SCREENREADER',
    'IDS_NEAR_OOM_REDUCTION_MESSAGE_DESCRIPTION',
    'IDS_NON_MILESTONE_UPDATE_TOAST_BODY',
    'IDS_NOTIFICATIONS_QUIET_PERMISSION_BUBBLE_PREDICTION_SERVICE_DESCRIPTION',
    'IDS_NTP_CUSTOMIZE_CHROME_RESET_TO_CLASSIC_CHROME_COMPLETE',
    'IDS_NTP_CUSTOMIZE_NO_BACKGROUND_LABEL',
    'IDS_NTP_MODULES_DRIVE_INFO',
    'IDS_NTP_MODULES_GOOGLE_CALENDAR_INFO',
    'IDS_NTP_MODULES_HISTORY_CLUSTERS_INFO',
    'IDS_NTP_MODULES_HISTORY_CLUSTERS_WITH_DISCOUNT_INFO',
    'IDS_NTP_MODULES_MICROSOFT_FILES_INFO',
    'IDS_NTP_MODULES_OUTLOOK_CALENDAR_INFO',
    'IDS_NTP_MODULES_SETUP_LIST_INFO',
    'IDS_NTP_MODULES_TAB_GROUPS_INFO',
    'IDS_NTP_MODULES_TAB_RESUMPTION_INFO',
    'IDS_OMNIBOX_ACTION_HISTORY_CLUSTERS_SEARCH_SUGGESTION_CONTENTS',
    'IDS_OMNIBOX_PEDAL_CLEAR_BROWSING_DATA_SUGGESTION_CONTENTS',
    'IDS_OMNIBOX_PEDAL_CUSTOMIZE_CHROME_FONTS_SUGGESTION_CONTENTS',
    'IDS_OMNIBOX_PEDAL_MANAGE_ADDRESSES_SUGGESTION_CONTENTS',
    'IDS_OMNIBOX_PEDAL_MANAGE_CHROME_ACCESSIBILITY_SUGGESTION_CONTENTS',
    'IDS_OMNIBOX_PEDAL_MANAGE_CHROME_DOWNLOADS_SUGGESTION_CONTENTS',
    'IDS_OMNIBOX_PEDAL_MANAGE_CHROME_SETTINGS_SUGGESTION_CONTENTS',
    'IDS_OMNIBOX_PEDAL_MANAGE_CHROME_THEMES_HINT',
    'IDS_OMNIBOX_PEDAL_MANAGE_COOKIES_SUGGESTION_CONTENTS',
    'IDS_OMNIBOX_PEDAL_MANAGE_PASSWORDS_SUGGESTION_CONTENTS',
    'IDS_OMNIBOX_PEDAL_MANAGE_SECURITY_SETTINGS_SUGGESTION_CONTENTS',
    'IDS_OMNIBOX_PEDAL_MANAGE_SITE_SETTINGS_SUGGESTION_CONTENTS',
    'IDS_OMNIBOX_PEDAL_MANAGE_SYNC_SUGGESTION_CONTENTS',
    'IDS_OMNIBOX_PEDAL_PLAY_CHROME_DINO_GAME_HINT',
    'IDS_OMNIBOX_PEDAL_PLAY_CHROME_DINO_GAME_SUGGESTION_CONTENTS',
    'IDS_OMNIBOX_PEDAL_RUN_CHROME_SAFETY_CHECK_SUGGESTION_CONTENTS',
    'IDS_OMNIBOX_PEDAL_RUN_CHROME_SAFETY_CHECK_V2_HINT',
    'IDS_OMNIBOX_PEDAL_RUN_CHROME_SAFETY_CHECK_V2_SUGGESTION_CONTENTS',
    'IDS_OMNIBOX_PEDAL_SET_CHROME_AS_DEFAULT_BROWSER_HINT',
    'IDS_OMNIBOX_PEDAL_SET_CHROME_AS_DEFAULT_BROWSER_SUGGESTION_CONTENTS',
    'IDS_OMNIBOX_PEDAL_UPDATE_CREDIT_CARD_SUGGESTION_CONTENTS',
    'IDS_OMNIBOX_PEDAL_VIEW_CHROME_HISTORY_HINT',
    'IDS_OMNIBOX_PEDAL_VIEW_CHROME_HISTORY_SUGGESTION_CONTENTS',
    'IDS_PAGE_INFO_CAMERA_SYSTEM_SETTINGS_DESCRIPTION',
    'IDS_PAGE_INFO_CLIPBOARD_SYSTEM_SETTINGS_DESCRIPTION',
    'IDS_PAGE_INFO_LOCATION_SYSTEM_SETTINGS_DESCRIPTION',
    'IDS_PAGE_INFO_MICROPHONE_SYSTEM_SETTINGS_DESCRIPTION',
    'IDS_PAGE_INFO_READER_MODE_PAGE',
    'IDS_PAGE_INFO_READER_MODE_PAGE_SECURE',
    'IDS_PASSWORD_MANAGER_DEFAULT_EXPORT_FILENAME',
    'IDS_PASSWORD_MANAGER_PASSKEY_FROM_CHROME_PROFILE',
    'IDS_PASSWORD_MANAGER_UI_MANAGE_PASSKEYS_FROM_PROFILE_LABEL',
    'IDS_PAYMENTS_CARD_AND_ADDRESS_SETTINGS_SIGNED_OUT',
    'IDS_PDF_SEARCHIFY_IPH_TITLE',
    'IDS_PHISHING_V4_PRIMARY_PARAGRAPH',
    'IDS_POLICY_COMMAND_LINE_FLAGS_WARNING',
    'IDS_POLICY_IGNORED_CHROME_PROFILE',
    'IDS_SERVICE_PROCESS_DOCUMENT_ANALYSIS_NAME',
    'IDS_SETTINGS_ANTI_ABUSE_WHEN_ON_SECTION_ONE',
    'IDS_SETTINGS_ANTI_ABUSE_WHEN_ON_SECTION_TWO',
    'IDS_SETTINGS_CAPTIONS_MANAGE_LANGUAGES_SUBTITLE_LIVE_CAPTION_ONLY',
    'IDS_SETTINGS_CERTIFICATE_MANAGER_V2_DELETE_SERVER_CERT_DESCRIPTION',
    'IDS_SETTINGS_CHROME_COLORS',
    'IDS_SETTINGS_HOME_ADDRESS_REMOVE_CONFIRMATION_DIALOG_TITLE',
    'IDS_SETTINGS_HOME_AND_WORK_ADDRESS_REMOVE',
    'IDS_SETTINGS_NAME_EMAIL_ADDRESS_REMOVE_CONFIRMATION_DIALOG_TITLE',
    'IDS_SETTINGS_RESET_AUTOMATED_DIALOG_V2_BODY',
    'IDS_SETTINGS_RESET_AUTOMATED_DIALOG_V2_TITLE',
    'IDS_SETTINGS_SEARCH_ENGINES_EXTENSION_ENGINES_EXPLANATION',
    'IDS_SETTINGS_SEARCH_ENGINES_SITE_SEARCH_EXPLANATION',
    'IDS_SETTINGS_SIDE_PANEL_ALIGNMENT_CHROME_PANELS',
    'IDS_SETTINGS_SITE_SETTINGS_BLOCK_AUTOPLAY',
    'IDS_SETTINGS_SITE_SETTINGS_PDF_DOWNLOAD_PDFS',
    'IDS_SETTINGS_WORK_ADDRESS_REMOVE_CONFIRMATION_DIALOG_TITLE',
    'IDS_SHOW_CUSTOMIZE_CHROME_SIDE_PANEL',
    'IDS_SUPPORT_TOOL_CHROME_SYSTEM_INFO',
    'IDS_TRIGGERED_RESET_PROFILE_SETTINGS_EXPLANATION',
    'IDS_TUTORIAL_CUSTOMIZE_CHROME_OPEN_SIDE_PANEL',
    'IDS_TUTORIAL_CUSTOMIZE_CHROME_START_TUTORIAL_IPH',
    'IDS_TUTORIAL_CUSTOMIZE_CHROME_SUCCESS_BODY',
    'IDS_UPDATED_CONNECTION_SECURITY_INDICATORS_PROMO',
    'IDS_UPDATER_VIEW_ALL_CHROME_POLICIES',
    'IDS_UTILITY_PROCESS_FILE_UTILITY_NAME',
    'IDS_WEBAUTHN_BLUETOOTH_PERMISSION',
    'IDS_WEBAUTHN_SOURCE_CHROME_PROFILE',
    'IDS_WEBAUTHN_YOUR_CHROME_PROFILE',
    'IDS_ZOOMLEVELS_CHROME_ERROR_PAGES_LABEL',
})


def _Product(match):
  if match.group(1):
    return PRODUCT + _CASE_ENDING[match.group(1)]
  return ('&' if '&' in match.group(0) else '') + PRODUCT


def _Parts(message):
  '''Yields each part of |message| and whether it is in the project link.'''
  in_link = False
  for part in message.GetContent():
    if not isinstance(part, str):
      in_link = part.GetPresentation() == PROJECT_LINK[0] or (
          in_link and part.GetPresentation() != PROJECT_LINK[1])
    yield part, in_link


def _Text(message):
  return ''.join(part for part, in_link in _Parts(message)
                 if isinstance(part, str) and not in_link)


def _Ending(language):
  endings = _ENDINGS.get(language, {})
  def ending(match):
    return PRODUCT + match.group(1) + endings.get(match.group(2),
                                                 match.group(2))
  return ending


def Rename(name, language, english, translation):
  '''Returns |translation|'s text, naming Parc as the product.

  |english| and |translation| are the message's tclib messages, and
  |language| is the translation's.'''
  if name in UNCHANGED:
    return translation.GetRealContent()
  english_text = _Text(english)
  says_chromium = 'Chromium' in english_text
  says_chrome = bool(_CHROME.search(english_text))
  # Translators sometimes wrote Chrome for Chromium or Chromium for Chrome;
  # the English says which is meant.
  chrome_is_parc = name in CHROME_MEANS_PARC or (says_chromium and
                                                 not says_chrome)
  chromium_is_parc = chrome_is_parc or says_chromium or not says_chrome
  text = []
  for part, in_link in _Parts(translation):
    if not isinstance(part, str):
      part = part.GetOriginal()
    elif not in_link:
      if chromium_is_parc:
        part = _CHROMIUM.sub(_Product, part)
      if chrome_is_parc:
        part = _CHROME.sub(PRODUCT + r'\1', part)
      if language in _ENDINGS:
        part = _ENDING.sub(_Ending(language), part)
    text.append(part)
  return ''.join(text)
