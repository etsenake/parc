'use strict';
(() => {
  const FAMILIES = {
    offline: ['ERR_INTERNET_DISCONNECTED', 'DNS_PROBE_FINISHED_NO_INTERNET'],
    notFound: ['ERR_NAME_NOT_RESOLVED', 'ERR_NAME_RESOLUTION_FAILED', 'ERR_ICANN_NAME_COLLISION',
               'DNS_PROBE_POSSIBLE', 'DNS_PROBE_STARTED', 'DNS_PROBE_FINISHED_INCONCLUSIVE',
               'DNS_PROBE_FINISHED_NXDOMAIN'],
    dnsSettings: ['DNS_PROBE_FINISHED_BAD_CONFIG', 'DNS_PROBE_FINISHED_BAD_SECURE_CONFIG'],
    timedOut: ['ERR_TIMED_OUT', 'ERR_CONNECTION_TIMED_OUT'],
    refused: ['ERR_CONNECTION_REFUSED'],
    dropped: ['ERR_CONNECTION_RESET', 'ERR_CONNECTION_CLOSED', 'ERR_CONNECTION_ABORTED', 'ERR_NETWORK_CHANGED'],
    unreachable: ['ERR_CONNECTION_FAILED', 'ERR_ADDRESS_UNREACHABLE', 'ERR_FAILED',
                  'ERR_PROXY_CONNECTION_FAILED', 'ERR_TUNNEL_CONNECTION_FAILED'],
    empty: ['ERR_EMPTY_RESPONSE'],
    garbled: ['ERR_INVALID_RESPONSE'],
    redirects: ['ERR_TOO_MANY_REDIRECTS'],
    secure: ['ERR_SSL_PROTOCOL_ERROR', 'ERR_SSL_VERSION_OR_CIPHER_MISMATCH'],
    fileMissing: ['ERR_FILE_NOT_FOUND'],
    fileDenied: ['ERR_ACCESS_DENIED'],
    extension: ['ERR_BLOCKED_BY_CLIENT'],
    admin: ['ERR_BLOCKED_BY_ADMINISTRATOR'],
    framed: ['ERR_BLOCKED_BY_RESPONSE'],
    resubmit: ['ERR_CACHE_MISS'],
    badAddress: ['ERR_INVALID_URL', 'ERR_UNKNOWN_URL_SCHEME', 'ERR_DISALLOWED_URL_SCHEME'],
  };

  const H = {host: true};

  const COPY = {
    offline: {art: 'plug', heading: ['You’re offline'],
              body: ['Your Mac isn’t connected to the internet. Check your Wi‑Fi or cable, and this page will reload by itself when you’re back.'],
              primary: 'reload'},
    dino: {art: 'plug', heading: ['Two plugs, one game'],
           body: ['Press Space to toss a spark from the plug to the socket. Land it while the socket is lined up.']},
    notFound: {art: 'signpost', heading: ['We can’t find ', {text: true}],
               body: ['No website answers to that name. Check the spelling, or the site may have packed up and moved.']},
    dnsSettings: {art: 'signpost', heading: ['We can’t find ', {text: true}],
                  body: ['Your DNS settings may be stopping Parc from looking it up. Check them, or ask whoever runs your network.']},
    timedOut: {art: 'snail', heading: ['That took too long'],
               body: [H, ' didn’t answer in time. The site may be swamped, or your connection is crawling. Give it another go.']},
    refused: {art: 'plane', heading: ['This page didn’t make it'],
              body: [H, ' turned the connection down. It might be restarting, or it isn’t letting anyone in right now.']},
    dropped: {art: 'plane', heading: ['This page didn’t make it'],
              body: ['The connection to ', H, ' dropped halfway. That’s usually a hiccup.']},
    unreachable: {art: 'plane', heading: ['This page didn’t make it'],
                  body: ['Parc couldn’t get through to ', H, '. It may be down for a moment, or something on your network is in the way.']},
    empty: {art: 'plane', heading: [{text: true}, ' sent nothing back'],
            body: ['It answered, but with an empty page. Try again in a moment.']},
    garbled: {art: 'plane', heading: ['This page came back garbled'],
              body: [H, ' sent something Parc couldn’t read. Trying again often sorts it out.']},
    redirects: {art: 'plane', heading: ['This page is going in circles'],
                body: [H, ' keeps sending Parc back and forth. Clearing this site’s cookies often fixes it.']},
    secure: {art: 'plane', heading: ['This page couldn’t connect securely'],
             body: [H, ' uses a security setup Parc can’t work with. It may be out of date, or something on your network is in the way.']},
    fileMissing: {art: 'signpost', heading: ['Parc can’t open this file'],
                  body: ['It may have been moved, renamed or deleted.']},
    fileDenied: {art: 'blocked', heading: ['Parc can’t open this file'],
                 body: ['Your Mac didn’t give Parc permission to read it. Check the file’s permissions, then try again.']},
    extension: {art: 'blocked', heading: ['An extension blocked this page'],
                body: ['One of your extensions stopped ', H, ' from loading. To see it anyway, pause that extension for this site.'],
                primary: 'back'},
    admin: {art: 'blocked', heading: ['Your organization blocked this site'],
            body: [H, ' is off-limits on this Mac. If you need it, ask your administrator.'], primary: 'back'},
    framed: {art: 'blocked', heading: [{text: true}, ' won’t show up here'],
             body: ['It refuses to open inside another page. Open it in its own tab to see it.'], primary: 'back'},
    resubmit: {art: 'plane', heading: ['Send that again?'],
               body: ['This page needs the information you entered before. Reload to send it again, but that repeats whatever happened the first time, like a purchase or a post.']},
    badAddress: {art: 'signpost', heading: ['Parc can’t open that address'],
                 body: [H, ' doesn’t lead anywhere Parc knows how to go.']},
    nothingHere: {art: 'signpost', heading: ['Nothing lives here'],
                  body: [H, ' doesn’t have a page at this address.'], primary: 'back'},
    keepOut: {art: 'blocked', heading: [{text: true}, ' won’t let you in'],
              body: ['You don’t have permission to see this page. Signing in, or asking the site’s owner, might help.'],
              primary: 'back'},
    struggling: {art: 'plane', heading: [{text: true}, ' is having a moment'],
                 body: ['The site couldn’t handle the request. It’s on their end; try again soon.']},
  };

  const WORDS = {
    reload: 'Try again',
    back: 'Go back',
    details: 'Details',
    hideDetails: 'Hide details',
    backOnline: 'Back online. Reloading…',
    hint: 'Waiting? Press Space to play catch with the plugs.',
    playing: (score, best, lives) => `${score} ${score === 1 ? 'spark' : 'sparks'} · best ${best} · ${'●'.repeat(lives)}${'○'.repeat(3 - lives)}`,
    over: (score, best) => `Game over: ${score} ${score === 1 ? 'spark' : 'sparks'}, best ${best}. Press Space to play again.`,
  };

  const subframe = window.top !== window.self;
  let data = null;
  let detailsOpen = false;
  let online = false;
  let primaryAction = null;
  let canGoBack = null;

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

  function familyOf(code, d) {
    for (const [name, codes] of Object.entries(FAMILIES)) {
      if (codes.includes(code)) {
        return name === 'resubmit' && d.reloadButton ? null : name;
      }
    }
    const http = /^HTTP ERROR (\d+)$/.exec(code);
    if (http) {
      const status = Number(http[1]);
      if (status === 404 || status === 410) {
        return 'nothingHere';
      }
      if (status === 401 || status === 403) {
        return 'keepOut';
      }
      if (status >= 500 && status <= 599) {
        return 'struggling';
      }
    }
    return null;
  }

  function isDino(d) {
    return !d.errorCode && d.iconClass === 'icon-offline';
  }

  function copyFor(d) {
    if (isDino(d)) {
      return COPY.dino;
    }
    if (d.isOfflineError) {
      return COPY.offline;
    }
    const family = familyOf(d.errorCode || '', d);
    return family ? COPY[family] : null;
  }

  function fallbackArt(d) {
    if (d.iconClass === 'icon-offline') {
      return 'plug';
    }
    return d.iconClass === 'icon-info' ? 'blocked' : 'plane';
  }

  function hostName(d) {
    return parc(d.title || '');
  }

  function fill(element, parts, d) {
    element.textContent = '';
    for (const part of parts) {
      if (typeof part === 'string') {
        element.append(part);
      } else if (part.host) {
        const strong = document.createElement('strong');
        strong.textContent = hostName(d);
        element.append(strong);
      } else if (part.text) {
        element.append(hostName(d));
      }
    }
  }

  function html(element, markup) {
    element.innerHTML = markup || '';
  }

  function placeArt(container, name) {
    if (container.dataset.art === name) {
      return;
    }
    const template = document.getElementById(`art-${name}`);
    container.textContent = '';
    container.dataset.art = name;
    if (template) {
      container.append(template.content.cloneNode(true));
    }
  }

  function controller() {
    return window.errorPageController;
  }

  function canReload(d) {
    return !!(d.reloadButton && d.reloadButton.msg) || (d.isOfflineError && !isDino(d) && !!controller());
  }

  function reload() {
    const pageController = controller();
    if (pageController) {
      pageController.reloadButtonClick();
    } else if (data && data.reloadButton && data.reloadButton.reloadUrl) {
      window.location.href = data.reloadButton.reloadUrl;
    }
  }

  function goBack() {
    window.history.back();
  }

  function hasDetails(d, copy) {
    const list = d.suggestionsSummaryList || [];
    const extra = d.suggestionsDetails || [];
    if (copy === COPY.offline || copy === COPY.dino) {
      return false;
    }
    return list.length > 0 || extra.length > 0 || (!!copy && !!(d.summary && d.summary.msg));
  }

  function buildDetails(d, copy) {
    const details = document.getElementById('details');
    details.textContent = '';
    if (copy && d.summary && d.summary.msg) {
      const summary = document.createElement('p');
      html(summary, d.summary.msg);
      details.append(summary);
    }
    const list = d.suggestionsSummaryList || [];
    if (list.length) {
      if (d.suggestionsSummaryListHeader) {
        const header = document.createElement('p');
        header.textContent = d.suggestionsSummaryListHeader;
        details.append(header);
      }
      const items = document.createElement('ul');
      for (const item of list) {
        const entry = document.createElement('li');
        html(entry, item.summary);
        items.append(entry);
      }
      details.append(items);
    }
    for (const item of d.suggestionsDetails || []) {
      const block = document.createElement('div');
      block.className = 'suggestion';
      const header = document.createElement('div');
      header.className = 'suggestion-header';
      html(header, item.header);
      const body = document.createElement('div');
      body.className = 'suggestion-body';
      html(body, item.body);
      block.append(header, body);
      details.append(block);
    }
  }

  function setButton(button, label, action) {
    button.hidden = !label;
    button.querySelector('.label').textContent = label || '';
    button.onclick = label ? action : null;
  }

  function renderButtons(d, copy) {
    const reloadable = canReload(d);
    const backable = canGoBack === null ? window.history.length > 1 : canGoBack;
    const reloadLabel = WORDS.reload;
    const actions = [];
    if (copy && copy.primary === 'back' && backable) {
      actions.push([WORDS.back, goBack]);
    }
    if (reloadable) {
      actions.push([reloadLabel, reload]);
    }
    if (isDino(d)) {
      actions.length = 0;
    }
    const [first, second] = actions;
    primaryAction = first ? first[1] : null;
    setButton(document.getElementById('primary'), first && first[0], first && first[1]);
    setButton(document.getElementById('secondary'), second && second[0], second && second[1]);
    const detailsButton = document.getElementById('details-button');
    const showDetails = hasDetails(d, copy);
    detailsButton.hidden = !showDetails;
    if (!showDetails) {
      detailsOpen = false;
    }
    detailsButton.setAttribute('aria-expanded', String(detailsOpen));
    detailsButton.querySelector('.label').textContent =
        detailsOpen ? (d.hideDetails || WORDS.hideDetails) : (d.details || WORDS.details);
    document.getElementById('details').hidden = !detailsOpen;
  }

  function setDetailsOpen(open) {
    detailsOpen = open;
    if (data) {
      renderButtons(data, copyFor(data));
    }
  }

  function render() {
    const d = data;
    if (!d) {
      return;
    }
    const copy = copyFor(d);
    document.title = parc(d.title || '');
    document.getElementById('code').textContent = parc(d.errorCode || '');
    if (subframe) {
      document.documentElement.classList.add('subframe');
      const frame = document.getElementById('frame-error');
      placeArt(frame.querySelector('.art'), copy ? copy.art : fallbackArt(d));
      const line = frame.querySelector('p');
      if (copy) {
        fill(line, copy.heading, d);
      } else {
        html(line, (d.summary && d.summary.msg) || (d.heading && d.heading.msg) || '');
      }
      frame.hidden = false;
      rewrite(frame);
      frame.title = line.textContent;
      return;
    }
    const art = copy ? copy.art : fallbackArt(d);
    if (art !== 'plug' && game.active()) {
      game.stop();
    }
    placeArt(document.getElementById('art'), art);
    const heading = document.getElementById('heading');
    const summary = document.getElementById('summary');
    if (copy) {
      fill(heading, copy.heading, d);
      if (copy === COPY.offline && online) {
        summary.textContent = WORDS.backOnline;
      } else {
        fill(summary, copy.body, d);
      }
    } else {
      html(heading, d.heading ? d.heading.msg : '');
      html(summary, d.summary ? d.summary.msg : '');
    }
    summary.hidden = !summary.textContent;
    buildDetails(d, copy);
    renderButtons(d, copy);
    const hint = document.getElementById('hint');
    hint.textContent = WORDS.hint;
    hint.hidden = !game.available() || game.active() || isDino(d);
    document.getElementById('page').hidden = false;
    rewrite(document.getElementById('page'));
  }

  const game = (() => {
    const state = {mode: 'off', score: 0, best: 0, lives: 3, phase: 0, speed: 2.4,
                   flight: 0.6, shot: null, last: 0, frame: 0, asked: false};
    const TOLERANCE = 6;

    function parts() {
      const svg = document.querySelector('#art svg');
      return svg && {
        right: svg.querySelector('.plug-right'),
        eyes: svg.querySelector('.plug-eyes'),
        dots: svg.querySelector('.plug-dots'),
        signal: svg.querySelector('.plug-signal'),
      };
    }

    function available() {
      return !!data && !subframe && data.iconClass === 'icon-offline' && !data.disabledEasterEgg &&
          !!document.querySelector('#art .plug-signal');
    }

    function status(text) {
      const element = document.getElementById('status');
      element.textContent = text;
      element.hidden = !text;
    }

    function replay(element, name) {
      element.classList.remove(name);
      void element.getBoundingClientRect();
      element.classList.add(name);
    }

    function start() {
      Object.assign(state, {mode: 'play', score: 0, lives: 3, phase: 0, speed: 2.4, flight: 0.6, shot: null});
      document.documentElement.classList.add('playing');
      document.getElementById('hint').hidden = true;
      const p = parts();
      p.dots.classList.remove('burst');
      p.dots.classList.add('gone');
      const pageController = controller();
      if (pageController && !state.asked) {
        state.asked = true;
        pageController.trackEasterEgg();
      }
      status(WORDS.playing(state.score, state.best, state.lives));
      state.last = performance.now();
      cancelAnimationFrame(state.frame);
      state.frame = requestAnimationFrame(tick);
    }

    function finish() {
      state.mode = 'over';
      state.shot = null;
      const reset = parts();
      if (reset && reset.right) {
        reset.right.setAttribute('transform', 'translate(0 0)');
      }
      if (state.score > state.best) {
        state.best = state.score;
        const pageController = controller();
        if (pageController) {
          pageController.updateEasterEggHighScore(state.best);
        }
      }
      status(WORDS.over(state.score, state.best));
      const p = parts();
      p.dots.classList.remove('gone', 'burst');
    }

    function land(socket) {
      const p = parts();
      p.signal.setAttribute('visibility', 'hidden');
      state.shot = null;
      if (Math.abs(socket) <= TOLERANCE) {
        state.score += 1;
        state.speed = Math.min(6, state.speed + 0.22);
        state.flight = Math.max(0.34, state.flight - 0.012);
        replay(p.eyes, 'blink');
        replay(p.dots, 'burst');
        status(WORDS.playing(state.score, state.best, state.lives));
        return;
      }
      state.lives -= 1;
      replay(p.right, 'shake');
      if (state.lives <= 0) {
        finish();
      } else {
        status(WORDS.playing(state.score, state.best, state.lives));
      }
    }

    function stop() {
      state.mode = 'off';
      state.shot = null;
      document.documentElement.classList.remove('playing');
      status('');
    }

    function tick(now) {
      const p = parts();
      if (state.mode === 'off') {
        return;
      }
      if (!p || !p.right || !p.signal) {
        stop();
        return;
      }
      const dt = Math.min(0.05, (now - state.last) / 1000);
      state.last = now;
      state.phase += state.speed * dt;
      const socket = state.mode === 'play' ? 14 * Math.sin(state.phase) : 0;
      p.right.setAttribute('transform', `translate(0 ${socket.toFixed(2)})`);
      if (state.shot) {
        state.shot.t = Math.min(1, state.shot.t + dt / state.flight);
        const u = state.shot.t;
        p.signal.setAttribute('cx', (30 + 60 * u).toFixed(2));
        p.signal.setAttribute('cy', (38 + 6 * u - 120 * u * (1 - u)).toFixed(2));
        if (u >= 1) {
          land(socket);
        }
      }
      if (state.mode === 'play' || state.shot) {
        state.frame = requestAnimationFrame(tick);
      }
    }

    function shoot() {
      if (state.shot || state.mode !== 'play') {
        return;
      }
      const p = parts();
      p.signal.setAttribute('visibility', 'visible');
      p.signal.setAttribute('cx', '30');
      p.signal.setAttribute('cy', '38');
      state.shot = {t: 0};
    }

    return {
      available,
      stop,
      active: () => state.mode !== 'off',
      press() {
        if (!available()) {
          return false;
        }
        if (state.mode === 'play') {
          shoot();
        } else {
          start();
        }
        return true;
      },
      best(score) {
        state.best = Math.max(state.best, Number(score) || 0);
        if (state.mode === 'play') {
          status(WORDS.playing(state.score, state.best, state.lives));
        } else if (state.mode === 'over') {
          status(WORDS.over(state.score, state.best));
        }
      },
    };
  })();

  function interactive(target) {
    return !!(target && target.closest && target.closest('button, a, input, select, textarea, summary, [contenteditable]'));
  }

  document.addEventListener('keydown', (event) => {
    if (event.metaKey || event.ctrlKey || event.altKey || interactive(event.target)) {
      return;
    }
    if (event.key === 'Enter' && primaryAction && !event.repeat) {
      event.preventDefault();
      primaryAction();
    } else if ((event.key === ' ' || event.code === 'Space') && !event.repeat) {
      if (game.press()) {
        event.preventDefault();
      }
    }
  });

  window.addEventListener('online', () => {
    online = true;
    render();
  });

  window.addEventListener('offline', () => {
    online = false;
    render();
  });

  function onLoad() {
    data = window.loadTimeDataRaw || null;
    if (!data) {
      return;
    }
    document.getElementById('details-button').addEventListener('click', () => {
      const pageController = controller();
      if (pageController) {
        pageController.detailsButtonClick();
      }
      setDetailsOpen(!detailsOpen);
    });
    document.getElementById('art').addEventListener('click', () => game.press());
    render();
  }

  Object.assign(window, {
    updateForDnsProbe(newData) {
      data = newData;
      render();
    },
    initializeEasterEggHighScore(score) {
      game.best(score);
    },
    toggleHelpBox() {
      setDetailsOpen(true);
      const details = document.getElementById('details');
      if (details.scrollIntoView) {
        details.scrollIntoView({block: 'nearest'});
      }
    },
    diagnoseErrors() {
      const pageController = controller();
      if (pageController) {
        pageController.diagnoseErrorsButtonClick();
      }
    },
    portalSignin() {
      const pageController = controller();
      if (pageController) {
        pageController.portalSigninButtonClick();
      }
    },
    parcSetCanGoBack(value) {
      canGoBack = !!value;
      if (data && !subframe) {
        renderButtons(data, copyFor(data));
      }
    },
    updateInitialInstruction() {},
    setAutoFetchState() {},
  });

  document.addEventListener('DOMContentLoaded', onLoad);
})();
