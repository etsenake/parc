// Copyright 2026 Parc contributors.

const WEB_STORE_HOST = 'chromewebstore.google.com';

const WEB_STORE_CSS = [
  'div[role="dialog"]:has(a[href*="google.com/chrome"])',
  'div[role="dialog"]:has(path[d="M11 7h2v2h-2zm0 4h2v6h-2z"])',
  'div[aria-label="Info"]:has(button[aria-label*="Chrome"])',
].join(',\n') + ' { display: none !important; }';

// Serialized into the page by chrome.scripting, so it must not capture
// anything outside its own body.
function presentWebStoreAsBrowser(browserName) {
  const LABEL = 'div > button > span';

  // The store keeps updating its own text nodes, so rewrite them in place
  // rather than replacing them.
  const rename = (label, observe) => {
    const walker = document.createTreeWalker(label, NodeFilter.SHOW_TEXT);
    for (let node = walker.nextNode(); node; node = walker.nextNode()) {
      if (node.data.includes('Chrome')) {
        node.data = node.data.replace(/Chrome/g, browserName);
      }
    }
    if (observe) {
      new MutationObserver(() => rename(label, false))
          .observe(label, {characterData: true, childList: true, subtree: true});
    }
  };

  const removeSwitchPrompts = () => {
    document.querySelector('div[role="dialog"] a[href*="google.com/chrome"]')
        ?.closest('div[role="dialog"]')
        ?.remove();
    document
        .querySelector(
            'div[role="dialog"] path[d="M11 7h2v2h-2zm0 4h2v6h-2z"]')
        ?.closest('div[role="dialog"]')
        ?.remove();
    for (const info of document.querySelectorAll('div[aria-label="Info"]')) {
      if (info.querySelector('button[aria-label*="Chrome"]')) {
        info.remove();
      }
    }
    const ownText = (element) =>
        [...element.childNodes]
            .filter((node) => node.nodeType === Node.TEXT_NODE)
            .map((node) => node.textContent)
            .join('')
            .trim();
    for (const label of document.querySelectorAll(LABEL)) {
      const container =
          label.parentElement?.parentElement?.parentElement?.parentElement;
      if (!container) {
        continue;
      }
      const notice =
          [...container.querySelectorAll('section > div > div > div > div')]
              .find((element) => ownText(element).includes('Chrome'));
      if (notice) {
        container.remove();
        break;
      }
    }
  };

  removeSwitchPrompts();
  for (const label of document.querySelectorAll(LABEL)) {
    rename(label, false);
  }

  if (window.parcWebStoreObserved) {
    return;
  }
  window.parcWebStoreObserved = true;

  const observe = () => {
    if (!document.body) {
      return;
    }
    removeSwitchPrompts();
    let sweeps = 0;
    const sweep = setInterval(() => {
      removeSwitchPrompts();
      if (++sweeps >= 10) {
        clearInterval(sweep);
      }
    }, 500);
    for (const label of document.querySelectorAll(LABEL)) {
      rename(label, true);
    }
    new MutationObserver((records) => {
      removeSwitchPrompts();
      for (const record of records) {
        if (record.type !== 'childList') {
          continue;
        }
        for (const node of record.addedNodes) {
          if (node.nodeType !== Node.ELEMENT_NODE) {
            continue;
          }
          if (node.matches(LABEL)) {
            rename(node, true);
          } else {
            for (const label of node.querySelectorAll(LABEL)) {
              rename(label, true);
            }
          }
        }
      }
    }).observe(document.body, {childList: true, subtree: true});
  };

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', observe, {once: true});
  } else {
    observe();
  }
}

function isWebStore(url) {
  try {
    return new URL(url).hostname === WEB_STORE_HOST;
  } catch {
    return false;
  }
}

chrome.tabs.onUpdated.addListener((tabId, changeInfo, tab) => {
  if (!tab.url || !isWebStore(tab.url)) {
    return;
  }
  // Injection rejects when the tab closes, navigates away or shows an error
  // page; the next update injects again.
  const target = {tabId};
  if (changeInfo.status === 'loading') {
    chrome.scripting.insertCSS({target, css: WEB_STORE_CSS}).catch(() => {});
  }
  if (changeInfo.status === 'loading' || changeInfo.status === 'complete') {
    chrome.scripting
        .executeScript({
          target,
          func: presentWebStoreAsBrowser,
          args: [chrome.runtime.getManifest().name.split(' ')[0]],
        })
        .catch(() => {});
  }
});
