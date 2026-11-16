'use strict';
(() => {
  const WORDS = {
    sslHeading: 'This connection isn’t private',
    sslLede: ['Parc can’t confirm this is really ', 'host',
              '. Someone could be trying to read what you send, like passwords, messages or card numbers. Parc stopped before sending anything.'],
    sslBack: 'Go back',
    sslRetry: 'Try again',
    dangerHeading: 'This site is dangerous',
    phishingLede: ['Google Safe Browsing caught this site pretending to be another site to steal passwords and card numbers. Parc kept it from loading.'],
    harmfulLede: ['Google Safe Browsing found this site pushing harmful software that can steal your information or mess with your Mac. Parc kept it from loading.'],
    dangerBack: 'Go back to safety',
    formHeading: 'This form isn’t secure',
    thisSite: 'this site',
  };

  function parc(value) {
    return String(value == null ? '' : value).split('chrome://').join('parc://');
  }

  function rewrite(root) {
    const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
    for (let node = walker.nextNode(); node; node = walker.nextNode()) {
      if (node.nodeValue.includes('chrome://')) {
        node.nodeValue = parc(node.nodeValue);
      }
    }
  }

  function visible(element) {
    return !!element && !element.classList.contains('hidden');
  }

  function lede(parts, host) {
    const paragraph = document.createElement('p');
    paragraph.className = 'parc-lede';
    for (const part of parts) {
      if (part === 'host') {
        const strong = document.createElement('strong');
        strong.textContent = host;
        paragraph.append(strong);
      } else {
        paragraph.append(part);
      }
    }
    return paragraph;
  }

  function retell(heading, parts, host) {
    const title = document.querySelector('#main-message h1');
    const original = document.querySelector('#main-message > p');
    const details = document.getElementById('details');
    const detailsButton = document.getElementById('details-button');
    if (!title || !original || !details || !visible(detailsButton)) {
      return false;
    }
    title.textContent = heading;
    title.after(lede(parts, host));
    details.prepend(original);
    return true;
  }

  function relabel(label) {
    const primary = document.getElementById('primary-button');
    if (primary && label) {
      primary.textContent = label;
    }
  }

  function setUp() {
    const data = window.loadTimeDataRaw || {};
    const ssl = data.type === 'SSL' && !data.bad_clock && 'is_qwac_enabled' in data;
    const danger = data.type === 'SAFEBROWSING' && !data.billing;
    if (ssl) {
      const strong = document.querySelector('#main-message > p strong');
      if (retell(WORDS.sslHeading, WORDS.sslLede, strong ? strong.textContent : WORDS.thisSite)) {
        relabel(data.overridable ? WORDS.sslBack : WORDS.sslRetry);
      }
    } else if (danger) {
      if (retell(WORDS.dangerHeading, data.phishing ? WORDS.phishingLede : WORDS.harmfulLede, '')) {
        relabel(WORDS.dangerBack);
      }
    } else if (data.type === 'INSECURE_FORM') {
      const title = document.querySelector('#main-message h1');
      if (title) {
        title.textContent = WORDS.formHeading;
      }
    }
    const theme = document.querySelector('meta[name=theme-color]');
    if (theme) {
      theme.setAttribute('content', getComputedStyle(document.body).getPropertyValue('--paper').trim() || '#FFFCEC');
    }
    rewrite(document.body);
    document.title = parc(document.title);
    document.addEventListener('keydown', (event) => {
      if (event.key !== 'Enter' || event.repeat || event.metaKey || event.ctrlKey || event.altKey) {
        return;
      }
      const target = event.target;
      if (target && target.closest && target.closest('button, a, input, select, textarea, label, [role="button"]')) {
        return;
      }
      const primary = document.getElementById('primary-button');
      if (visible(primary)) {
        event.preventDefault();
        primary.click();
      }
    });
  }

  document.addEventListener('DOMContentLoaded', setUp);
})();
