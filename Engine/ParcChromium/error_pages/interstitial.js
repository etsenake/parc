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
    details: 'Details',
    hideDetails: 'Hide details',
    anyway: 'Continue anyway',
    visitAnyway: 'Visit this site anyway',
    clockHeading: 'Your Mac’s clock is off',
    clockLede: ['Secure sites check the date, and the one on your Mac is wrong, so Parc can’t safely connect to ', 'host',
                '. Set the right date and time, then try again.'],
    clockButton: 'Open Date & Time',
    portalHeading: 'This network wants you to sign in',
    portalLede: ['Cafés, hotels and airports often ask you to sign in before anything loads. Open the sign-in page, then come back and try again.'],
    portalButton: 'Open sign-in page',
    lookalikeLede: ['This address looks a lot like ', 'suggested', '. Copycat addresses are a common trick for stealing passwords and card numbers.'],
    fakeHeading: 'This site may be fake',
    fakeLede: ['Its address uses look-alike characters, a common trick for pretending to be a real site and stealing passwords.'],
    httpsLede: ['Anyone on your network could see or change what you send and receive there.'],
    blockHeading: 'Your organization blocked this site',
    blockLede: ['Your administrator doesn’t allow ', 'host', ' on this browser. If you need it, ask them.'],
    blockLedeAny: ['Your administrator doesn’t allow this site on this browser. If you need it, ask them.'],
    warnHeading: 'Your organization flagged this site',
    warnLede: ['Your administrator thinks ', 'host', ' might go against a policy. Go back, or continue if you’re sure you need it.'],
    warnLedeAny: ['Your administrator thinks this site might go against a policy. Go back, or continue if you’re sure you need it.'],
    softwareHeading: 'Software on your Mac is blocking secure connections',
    softwareLede: ['Security software on your Mac or network, like antivirus or a web filter, isn’t set up right, so Parc can’t safely connect. Details shows which app and how to fix it.'],
    watchedHeading: 'This connection is being monitored',
    watchedLede: ['A certificate installed on this Mac lets someone see what you type and view across the web, and change it. Parc stopped before sending anything.'],
    billingHeading: 'This page may try to charge you',
    billingLede: ['Charges could be one-time or recurring, and might not be obvious. Go back unless you expected to pay.'],
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

  function lede(parts, values) {
    const paragraph = document.createElement('p');
    paragraph.className = 'parc-lede';
    for (const part of parts) {
      if (part === 'host' || part === 'suggested') {
        const strong = document.createElement('strong');
        strong.textContent = values[part] || WORDS.thisSite;
        paragraph.append(strong);
      } else {
        paragraph.append(part);
      }
    }
    return paragraph;
  }

  function original() {
    return document.querySelector('#main-message > p');
  }

  function boldIn(element) {
    const strong = element && element.querySelector('strong');
    return strong ? strong.textContent : '';
  }

  function retell(heading, parts, values) {
    const title = document.querySelector('#main-message h1');
    const paragraph = original();
    const details = document.getElementById('details');
    const detailsButton = document.getElementById('details-button');
    if (!title || !paragraph || !details || !visible(detailsButton)) {
      return false;
    }
    title.textContent = heading;
    title.after(lede(parts, values));
    details.prepend(paragraph);
    return true;
  }

  function restate(heading, parts, values, keepNote) {
    const title = document.querySelector('#main-message h1');
    const paragraph = original();
    if (!title) {
      return false;
    }
    if (heading) {
      title.textContent = heading;
    }
    const replacement = lede(parts, values);
    title.after(replacement);
    if (paragraph && keepNote) {
      paragraph.classList.add('parc-note');
    } else if (paragraph) {
      for (const link of paragraph.querySelectorAll('a')) {
        replacement.append(' ', link);
      }
      paragraph.remove();
    }
    return true;
  }

  function relabel(label, id) {
    const button = document.getElementById(id || 'primary-button');
    if (button && label && visible(button)) {
      button.textContent = label;
    }
  }

  function labelDetails() {
    const button = document.getElementById('details-button');
    if (!button || !visible(button)) {
      return;
    }
    const apply = () => {
      button.textContent = button.getAttribute('aria-expanded') === 'true' ? WORDS.hideDetails : WORDS.details;
    };
    apply();
    button.addEventListener('click', apply);
  }

  function retellOthers(data) {
    switch (data.type) {
      case 'SSL':
        if (data.bad_clock) {
          if (retell(WORDS.clockHeading, WORDS.clockLede, {host: boldIn(original())})) {
            relabel(WORDS.clockButton);
          }
        } else if (data.hide_primary_button) {
          retell(WORDS.softwareHeading, WORDS.softwareLede, {});
        }
        break;
      case 'BLOCKED_INTERCEPTION':
        retell(WORDS.watchedHeading, WORDS.watchedLede, {});
        break;
      case 'CAPTIVE_PORTAL':
        restate(WORDS.portalHeading, WORDS.portalLede, {}, true);
        relabel(WORDS.portalButton);
        break;
      case 'LOOKALIKE': {
        const suggestion = document.getElementById('dont-proceed-link');
        if (suggestion) {
          restate(null, WORDS.lookalikeLede, {suggested: suggestion.textContent}, false);
        } else {
          restate(WORDS.fakeHeading, WORDS.fakeLede, {}, false);
          relabel(WORDS.dangerBack);
        }
        relabel(WORDS.visitAnyway, 'proceed-button');
        break;
      }
      case 'HTTPS_ONLY':
        restate(null, WORDS.httpsLede, {}, true);
        break;
      case 'ENTERPRISE_BLOCK':
      case 'ENTERPRISE_WARN': {
        const block = data.type === 'ENTERPRISE_BLOCK';
        const host = boldIn(original());
        restate(block ? WORDS.blockHeading : WORDS.warnHeading,
                host ? (block ? WORDS.blockLede : WORDS.warnLede) : (block ? WORDS.blockLedeAny : WORDS.warnLedeAny),
                {host}, !host);
        break;
      }
      case 'SAFEBROWSING':
        if (data.billing) {
          restate(WORDS.billingHeading, WORDS.billingLede, {}, false);
          relabel(WORDS.anyway, 'proceed-button');
        }
        break;
      default:
        break;
    }
  }

  function setUp() {
    const data = window.loadTimeDataRaw || {};
    const ssl = data.type === 'SSL' && !data.bad_clock && 'is_qwac_enabled' in data;
    const danger = data.type === 'SAFEBROWSING' && !data.billing;
    if (ssl) {
      if (retell(WORDS.sslHeading, WORDS.sslLede, {host: boldIn(original())})) {
        relabel(data.overridable ? WORDS.sslBack : WORDS.sslRetry);
      }
    } else if (danger) {
      if (retell(WORDS.dangerHeading, data.phishing ? WORDS.phishingLede : WORDS.harmfulLede, {})) {
        relabel(WORDS.dangerBack);
      }
    } else if (data.type === 'INSECURE_FORM') {
      const title = document.querySelector('#main-message h1');
      if (title) {
        title.textContent = WORDS.formHeading;
      }
    } else {
      retellOthers(data);
    }
    labelDetails();
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
