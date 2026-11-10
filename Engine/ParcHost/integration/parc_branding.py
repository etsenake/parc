# Copyright 2026 Parc contributors.
'''Names Parc, not Chromium, in every string grit emits.

Grit renames the product in every translation, including inflected,
misspelt and transliterated forms, and where a translation says Chrome for
an English Chromium. Copyright notices and links to the Chromium project
keep Chromium's name.
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
# Chrome the browser, not Google's devices and operating system.
CHROME = re.compile(r'(?:Google\s)?Chrome(?!book|box|bit|cast|\s?OS)')


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


def Rename(name, english, translation):
  '''Returns |translation|'s text, naming Parc instead of Chromium.

  |english| and |translation| are the message's tclib messages.'''
  if name in UNCHANGED:
    return translation.GetRealContent()
  english_text = _Text(english)
  # Some translators wrote Chrome where the English says Chromium.
  chrome_is_product = ('Chromium' in english_text and
                       'Chrome' not in english_text)
  text = []
  for part, in_link in _Parts(translation):
    if not isinstance(part, str):
      part = part.GetOriginal()
    elif not in_link:
      part = _CHROMIUM.sub(_Product, part)
      if chrome_is_product:
        part = CHROME.sub(PRODUCT, part)
    text.append(part)
  return ''.join(text)
