import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';

const header = readFileSync(fileURLToPath(new URL(
    '../../Engine/ParcRenderer/parc_webkit_presentation.h', import.meta.url)), 'utf8');
const match = header.match(/R"PARC_WKPM_JS\(([\s\S]*)\)PARC_WKPM_JS"/);
if (!match) throw new Error('script not found in header');
const script = match[1];
if (/[^\x00-\x7f]/.test(script)) throw new Error('script must be ASCII');

let checks = 0;
function check(condition, message) {
  ++checks;
  if (!condition) {
    console.error('FAIL: ' + message);
    process.exit(1);
  }
}

function makeWindow() {
  const log = [];
  const listeners = new WeakMap();
  const task = (fn) => setTimeout(fn, 0);
  const tasks = (count, fn) => (count ? task(() => tasks(count - 1, fn)) : fn());
  let global = null;
  class Event {
    #type; #bubbles; #cancelable; #composed;
    constructor(type, init = {}) {
      this.#type = `${type}`; this.#bubbles = !!init.bubbles;
      this.#cancelable = !!init.cancelable; this.#composed = !!init.composed;
      this.path = [];
    }
    get type() { return this.#type; }
    get bubbles() { return this.#bubbles; }
    get cancelable() { return this.#cancelable; }
    get composed() { return this.#composed; }
    get isTrusted() { return !!this.trusted; }
    composedPath() { return this.path.slice(); }
  }
  const parentOf = (node, event) => {
    if (node instanceof ShadowRoot) return event.composed ? node.host : null;
    if (node instanceof Document) return global;
    return node === global ? null : node.parentNode;
  };
  class EventTarget {
    addEventListener(type, listener, options) {
      if (!listeners.has(this)) listeners.set(this, []);
      const capture = options === true || !!(options && options.capture);
      listeners.get(this).push({type: `${type}`, listener, capture});
    }
    dispatchEvent(event) {
      const path = [];
      for (let node = this; node; node = parentOf(node, event)) path.push(node);
      event.path = path;
      const invoke = (node, capture) => {
        for (const entry of [...(listeners.get(node) || [])]) {
          if (entry.type === event.type && entry.capture === capture) {
            typeof entry.listener === 'function' ? entry.listener.call(node, event)
                : entry.listener.handleEvent(event);
          }
        }
      };
      for (let i = path.length - 1; i > 0; --i) invoke(path[i], true);
      invoke(path[0], true);
      invoke(path[0], false);
      if (event.bubbles) for (let i = 1; i < path.length; ++i) invoke(path[i], false);
      return true;
    }
  }
  class Node extends EventTarget {
    #document;
    constructor(ownerDocument) { super(); this.#document = ownerDocument; this.parentNode = null; }
    get ownerDocument() { return this.#document; }
    getRootNode() {
      let node = this;
      while (node.parentNode) node = node.parentNode;
      return node;
    }
    appendChild(child) { child.parentNode = this; return child; }
    remove() {
      const fullscreen = this.ownerDocument.state.fullscreen;
      this.parentNode = null;
      if (fullscreen === this) this.ownerDocument.leaveFullscreen(() => {});
    }
    get isConnected() { return this.getRootNode() instanceof Document; }
  }
  const retarget = (element, root) => {
    let node = element;
    while (node) {
      const nodeRoot = node.getRootNode();
      if (nodeRoot === root || !(nodeRoot instanceof ShadowRoot)) return node;
      node = nodeRoot.host;
    }
    return null;
  };
  class Document extends Node {
    state = {fullscreen: null, pictureInPicture: null};
    pipEnabled = true;
    constructor() { super(null); }
    get ownerDocument() { return null; }
    get fullscreenElement() { const e = this.state.fullscreen; return e ? retarget(e, this) : null; }
    get pictureInPictureElement() { const e = this.state.pictureInPicture; return e ? retarget(e, this) : null; }
    get pictureInPictureEnabled() { return this.pipEnabled; }
    get fullscreenEnabled() { return true; }
    leaveFullscreen(done) {
      tasks(window.slowFullscreenExit ? 6 : 1, () => {
        const element = this.state.fullscreen;
        this.state.fullscreen = null;
        log.push('exited fullscreen');
        done();
        task(() => (element.isConnected ? element : this).dispatchEvent(
            new Event('fullscreenchange', {bubbles: true, composed: true})));
      });
    }
    exitFullscreen() {
      log.push('exitFullscreen');
      if (!this.state.fullscreen) return Promise.reject(new TypeError('Document not active'));
      return new Promise((resolve) => this.leaveFullscreen(resolve));
    }
    exitPictureInPicture() {
      log.push('exitPictureInPicture');
      const element = this.state.pictureInPicture;
      if (!element) return Promise.reject(new Error('InvalidStateError'));
      return new Promise((resolve) => tasks(2, () => {
        this.state.pictureInPicture = null;
        log.push('left picture in picture');
        element.dispatchEvent(new Event('leavepictureinpicture', {bubbles: true}));
        resolve();
      }));
    }
  }
  class ShadowRoot extends Node {
    constructor(host) { super(host.ownerDocument); this.host = host; }
    get fullscreenElement() { const e = this.ownerDocument.state.fullscreen; return e && e.getRootNode() === this ? e : null; }
    get pictureInPictureElement() { const e = this.ownerDocument.state.pictureInPicture; return e && e.getRootNode() === this ? e : null; }
  }
  class UserActivation {
    active = false;
    get isActive() { return this.active; }
    consume() { const was = this.active; this.active = false; return was; }
  }
  const activation = new UserActivation();
  class Element extends Node {
    requestFullscreen() {
      log.push('requestFullscreen');
      const document = this.ownerDocument;
      if (window.failFullscreen || !activation.consume()) {
        task(() => this.dispatchEvent(new Event('fullscreenerror', {bubbles: true, composed: true})));
        return Promise.reject(new TypeError('Permissions check failed'));
      }
      return new Promise((resolve) => tasks(2, () => {
        document.state.fullscreen = this;
        log.push('entered fullscreen');
        resolve();
        if (document.state.pictureInPicture === this) document.exitPictureInPicture();
        task(() => this.dispatchEvent(new Event('fullscreenchange', {bubbles: true, composed: true})));
      }));
    }
    attachShadow() { const root = new ShadowRoot(this); return root; }
  }
  class HTMLMediaElement extends Element {
    #networkState = 0; #readyState = 0;
    hadGesture = false;
    play() { if (activation.active) this.hadGesture = true; return Promise.resolve(); }
    get networkState() { return this.#networkState; }
    get readyState() { return this.#readyState; }
    load(width = 640, height = 360) { this.#networkState = 1; this.#readyState = 1; this.width = width; this.height = height; }
    startLoading() { this.#networkState = 2; }
  }
  class HTMLVideoElement extends HTMLMediaElement {
    #brand = true;
    get videoWidth() { return this.#brand && this.readyState ? this.width : 0; }
    get videoHeight() { return this.#brand && this.readyState ? this.height : 0; }
    requestPictureInPicture() {
      window.lastPictureInPictureRequest = this.#requestPictureInPicture();
      return window.lastPictureInPictureRequest;
    }
    #requestPictureInPicture() {
      log.push('requestPictureInPicture');
      const document = this.ownerDocument;
      if (this.readyState === 0 || !this.videoWidth) return Promise.reject(new Error('InvalidStateError'));
      if (!document.state.pictureInPicture && !activation.consume() && !window.consumeToken()) {
        return Promise.reject(new Error('NotAllowedError'));
      }
      if (document.state.pictureInPicture === this) return Promise.resolve({});
      if (document.state.fullscreen === this) document.exitFullscreen();
      return new Promise((resolve) => tasks(3, () => {
        const previous = document.state.pictureInPicture;
        if (previous) {
          document.state.pictureInPicture = null;
          previous.dispatchEvent(new Event('leavepictureinpicture', {bubbles: true}));
        }
        document.state.pictureInPicture = this;
        log.push('entered picture in picture');
        this.dispatchEvent(new Event('enterpictureinpicture', {bubbles: true}));
        resolve({});
      }));
    }
  }
  class HTMLAudioElement extends HTMLMediaElement {}
  const document = new Document();
  const listenerTypes = (target) => (listeners.get(target) || []).map((entry) => entry.type);
  const window = {
    listenerTypes, WeakRef,
    Event, EventTarget, Node, Element, Document, ShadowRoot, HTMLMediaElement,
    HTMLVideoElement, HTMLAudioElement, UserActivation, WeakMap, setTimeout, DOMException,
    navigator: {userActivation: activation}, document, activation, log, failFullscreen: false,
    slowFullscreenExit: false, pipToken: false,
    consumeToken() { const had = window.pipToken; window.pipToken = false; return had; },
    native: {
      fire(target, type) {
        const event = new Event(type, {bubbles: false, cancelable: true});
        event.trusted = true;
        target.dispatchEvent(event);
      },
      mediaGesture(element) { return !!element.hadGesture; },
      allowPictureInPicture(element) { if (element.hadGesture) window.pipToken = true; },
    },
  };
  vm.createContext(window);
  global = vm.runInContext('globalThis', window);
  window.div = (parent = document) => parent.appendChild(new Element(document));
  window.video = (parent = document) => {
    const video = new HTMLVideoElement(document);
    if (parent) parent.appendChild(video);
    return video;
  };
  return window;
}
const install = (window, helpers = window.native) => vm.runInContext(script, window)(helpers);
const settle = async () => { for (let i = 0; i < 20; ++i) await new Promise((r) => setTimeout(r, 0)); };
const throwsType = (fn) => { try { fn(); return false; } catch (error) { return !!error && error.name === 'TypeError'; } };
function record(window, video, target = window.document) {
  const seen = [];
  video.addEventListener('webkitpresentationmodechanged', (event) => {
    seen.push('mode:' + video.webkitPresentationMode + (event.bubbles ? ':bubbles' : '') +
              (event.cancelable ? '' : ':not-cancelable') +
              (event.isTrusted === !!window.native ? '' : ':trust'));
  });
  for (const type of ['fullscreenchange', 'enterpictureinpicture', 'leavepictureinpicture']) {
    target.addEventListener(type, () => seen.push(type));
  }
  return seen;
}

{
  const window = makeWindow();
  install(window);
  const proto = window.HTMLVideoElement.prototype;
  for (const name of ['webkitSupportsPresentationMode', 'webkitSetPresentationMode']) {
    const d = Object.getOwnPropertyDescriptor(proto, name);
    check(d && typeof d.value === 'function' && d.writable && d.enumerable && d.configurable,
          name + ' is a WebIDL operation of HTMLVideoElement.prototype');
    check(d.value.length === 1, name + ' takes one argument');
    check(throwsType(() => new d.value('inline')), name + ' is not a constructor');
  }
  const mode = Object.getOwnPropertyDescriptor(proto, 'webkitPresentationMode');
  check(mode && mode.get && !mode.set && mode.enumerable && mode.configurable,
        'webkitPresentationMode is a read-only attribute');
  check(mode.get.name === 'get webkitPresentationMode', 'its getter has WebIDL\'s name');
  check(!('webkitSetPresentationMode' in window.HTMLAudioElement.prototype),
        'audio elements have no presentation mode');
  install(window);
  check(Object.getOwnPropertyDescriptor(proto, 'webkitPresentationMode').get === mode.get,
        'running the script again changes nothing');
  check(typeof vm.runInContext(script, window) === 'function',
        'the script evaluates to the function Blink calls');

  const video = window.video();
  check(video.webkitPresentationMode === 'inline', 'a new video is inline');
  check(throwsType(() => mode.get.call({})), 'the getter brand-checks');
  check(throwsType(() => proto.webkitSetPresentationMode.call(window.document, 'inline')),
        'webkitSetPresentationMode brand-checks');
  let message = '';
  try { video.webkitSupportsPresentationMode(); } catch (error) { message = error.message; }
  check(message === "Failed to execute 'webkitSupportsPresentationMode' on 'HTMLVideoElement': " +
        '1 argument required, but only 0 present.', 'a missing mode is a TypeError');
  try { video.webkitSetPresentationMode('pip'); } catch (error) { message = error.message; }
  check(message === "Failed to execute 'webkitSetPresentationMode' on 'HTMLVideoElement': " +
        "The provided value 'pip' is not a valid enum value of type VideoPresentationMode.",
        'an unknown mode is a TypeError, as WebIDL enums are');
  check(throwsType(() => video.webkitSupportsPresentationMode(Symbol('inline'))),
        'a symbol is not a mode');
}

{
  const window = makeWindow();
  install(window);
  const video = window.video();
  const supports = (mode) => video.webkitSupportsPresentationMode(mode);
  check(supports('inline') && !supports('fullscreen') && !supports('picture-in-picture'),
        'a video that never loaded supports only inline');
  video.startLoading();
  check(supports('fullscreen') && !supports('picture-in-picture'),
        'a loading video without metadata supports fullscreen, not picture in picture');
  video.load();
  check(supports('fullscreen') && supports('picture-in-picture'),
        'a video with metadata and video supports all three');
  window.document.pipEnabled = false;
  check(!supports('picture-in-picture'), 'no picture in picture where Parc offers none');
  window.document.pipEnabled = true;
  const audioOnly = window.video();
  audioOnly.load(0, 0);
  check(audioOnly.webkitSupportsPresentationMode('fullscreen') &&
        !audioOnly.webkitSupportsPresentationMode('picture-in-picture'),
        'audio-only media supports fullscreen but not picture in picture');
}

{
  const window = makeWindow();
  install(window);
  const video = window.video();
  video.load();
  const seen = record(window, video);
  video.webkitSetPresentationMode('picture-in-picture');
  await settle();
  check(!window.log.includes('requestPictureInPicture') && video.webkitPresentationMode === 'inline',
        'without a user gesture picture in picture is ignored');
  window.activation.active = true;
  video.webkitSetPresentationMode('picture-in-picture');
  check(window.log.includes('requestPictureInPicture'), 'it asks Chromium for picture in picture');
  check(video.webkitPresentationMode === 'inline', 'the mode is still inline during the call');
  await new Promise((r) => setTimeout(r, 0));
  check(video.webkitPresentationMode === 'picture-in-picture' &&
        window.document.pictureInPictureElement === null,
        'it reports picture in picture before the platform has entered it');
  video.webkitSetPresentationMode('inline');
  await settle();
  check(!window.log.includes('exitPictureInPicture'),
        'a change in progress ignores webkitSetPresentationMode');
  check(seen.join() === 'mode:picture-in-picture,enterpictureinpicture',
        'one cancelable, non-bubbling webkitpresentationmodechanged, before enterpictureinpicture: ' + seen);
  check(window.document.pictureInPictureElement === video, 'the standard API agrees');

  seen.length = 0;
  video.webkitSetPresentationMode('inline');
  check(window.log.includes('exitPictureInPicture') && video.webkitPresentationMode === 'inline',
        'inline leaves picture in picture and reports inline at once');
  check(seen.length === 0, 'the event comes in a task');
  await settle();
  check(seen.join() === 'mode:inline,leavepictureinpicture', 'then leavepictureinpicture: ' + seen);
  video.webkitSetPresentationMode('inline');
  await settle();
  check(seen.length === 2, 'setting the current mode does nothing');
}

{
  const window = makeWindow();
  install(window);
  const video = window.video();
  video.load();
  const seen = record(window, video);
  window.activation.active = true;
  video.webkitSetPresentationMode('fullscreen');
  check(window.log.includes('requestFullscreen'), 'fullscreen asks for element fullscreen');
  await settle();
  check(seen.join() === 'mode:fullscreen,fullscreenchange', 'fullscreen events: ' + seen);
  check(video.webkitPresentationMode === 'fullscreen' && window.document.fullscreenElement === video,
        'the mode and document.fullscreenElement agree');
  seen.length = 0;
  video.webkitSetPresentationMode('inline');
  check(window.log.includes('exitFullscreen'), 'inline exits fullscreen without a gesture');
  check(video.webkitPresentationMode === 'fullscreen', 'until the document leaves fullscreen');
  await settle();
  check(seen.join() === 'mode:inline,fullscreenchange', 'exit events: ' + seen);

  window.failFullscreen = true;
  window.activation.active = true;
  video.webkitSetPresentationMode('fullscreen');
  await settle();
  check(seen.length === 2 && video.webkitPresentationMode === 'inline', 'a refused fullscreen request changes nothing');
  window.failFullscreen = false;
  window.activation.active = true;
  video.webkitSetPresentationMode('fullscreen');
  await settle();
  check(video.webkitPresentationMode === 'fullscreen', 'and the next request proceeds');
}

{
  const window = makeWindow();
  install(window);
  const video = window.video();
  video.load();
  window.activation.active = true;
  video.webkitSetPresentationMode('fullscreen');
  await settle();
  const seen = record(window, video);
  window.activation.active = true;
  video.webkitSetPresentationMode('picture-in-picture');
  await settle();
  check(seen.filter((e) => e.startsWith('mode:')).join() === 'mode:picture-in-picture',
        'fullscreen to picture in picture is one change: ' + seen);
  check(window.document.fullscreenElement === null && window.document.pictureInPictureElement === video,
        'Chromium left fullscreen and entered picture in picture');
  seen.length = 0;
  window.activation.active = true;
  video.webkitSetPresentationMode('fullscreen');
  await settle();
  check(seen.filter((e) => e.startsWith('mode:')).join() === 'mode:fullscreen',
        'picture in picture to fullscreen is one change: ' + seen);
  check(window.document.fullscreenElement === video && window.document.pictureInPictureElement === null,
        'Chromium ended picture in picture once fullscreen');
}

{
  const window = makeWindow();
  install(window);
  const video = window.video();
  video.load();
  window.activation.active = true;
  video.webkitSetPresentationMode('fullscreen');
  await settle();
  const seen = record(window, video);
  window.slowFullscreenExit = true;
  window.activation.active = true;
  video.webkitSetPresentationMode('picture-in-picture');
  await settle();
  check(seen.join() === 'mode:picture-in-picture,enterpictureinpicture,fullscreenchange',
        'picture in picture first, fullscreen exit later, is one change: ' + seen);
  check(video.webkitPresentationMode === 'picture-in-picture' &&
        window.document.fullscreenElement === null, 'it settles in picture in picture');
  seen.length = 0;
  video.webkitSetPresentationMode('inline');
  await settle();
  check(seen.join() === 'mode:inline,leavepictureinpicture', 'and leaves it normally: ' + seen);
}

{
  const window = makeWindow();
  install(window);
  const first = window.video();
  const second = window.video();
  first.load();
  second.load();
  const firstSeen = [];
  const secondSeen = [];
  window.document.addEventListener('webkitpresentationmodechanged', (event) => {
    (event.composedPath()[0] === first ? firstSeen : secondSeen).push(event.composedPath()[0].webkitPresentationMode);
  }, true);
  window.document.addEventListener('enterpictureinpicture', (event) => {
    (event.composedPath()[0] === first ? firstSeen : secondSeen).push('enter');
  });
  window.activation.active = true;
  first.requestPictureInPicture();
  await settle();
  check(firstSeen.join() === 'picture-in-picture,enter',
        'the standard request reports, before enterpictureinpicture: ' + firstSeen);
  second.webkitSetPresentationMode('picture-in-picture');
  await settle();
  check(window.document.pictureInPictureElement === second,
        'picture in picture needs no gesture while the document has a picture-in-picture element');
  check(firstSeen.join() === 'picture-in-picture,enter,inline' &&
        secondSeen.join() === 'picture-in-picture,enter',
        'both videos report: ' + firstSeen + ' / ' + secondSeen);
  window.document.exitPictureInPicture();
  await settle();
  check(secondSeen.join() === 'picture-in-picture,enter,inline', 'the standard exit reports');
}

{
  const window = makeWindow();
  install(window);
  const host = window.div();
  const root = host.attachShadow();
  const video = window.video(root);
  video.load();
  const seen = [];
  video.addEventListener('webkitpresentationmodechanged', () => seen.push(video.webkitPresentationMode));
  window.activation.active = true;
  video.requestPictureInPicture();
  await settle();
  check(seen.join() === 'picture-in-picture', 'a shadow-tree video reports: ' + seen);
  check(video.webkitPresentationMode === 'picture-in-picture' &&
        window.document.pictureInPictureElement === host,
        'the document sees its host, the video reports its own mode');

  const plain = window.video();
  plain.load();
  window.activation.active = true;
  plain.webkitSetPresentationMode('fullscreen');
  await settle();
  const plainSeen = [];
  plain.addEventListener('webkitpresentationmodechanged', () => plainSeen.push(plain.webkitPresentationMode));
  plain.remove();
  await settle();
  check(plainSeen.join() === 'inline', 'a fullscreen video removed from the document reports inline: ' + plainSeen);
}

{
  const window = makeWindow();
  install(window);
  const proto = window.HTMLVideoElement.prototype;
  for (const name of ['webkitEnterFullscreen', 'webkitExitFullscreen',
                      'webkitEnterFullScreen', 'webkitExitFullScreen']) {
    const d = Object.getOwnPropertyDescriptor(proto, name);
    check(d && typeof d.value === 'function' && d.writable && d.enumerable && d.configurable &&
          d.value.length === 0 && d.value.name === name,
          name + ' is a WebIDL operation of HTMLVideoElement.prototype');
  }
  check(proto.webkitEnterFullScreen !== proto.webkitEnterFullscreen,
        'the FullScreen spellings are operations of their own');
  for (const name of ['webkitSupportsFullscreen', 'webkitDisplayingFullscreen']) {
    const d = Object.getOwnPropertyDescriptor(proto, name);
    check(d && d.get && !d.set && d.enumerable && d.configurable && d.get.name === 'get ' + name,
          name + ' is a read-only attribute');
    check(throwsType(() => d.get.call(window.document)), name + ' brand-checks');
  }
  check(throwsType(() => proto.webkitEnterFullscreen.call({})), 'webkitEnterFullscreen brand-checks');
  check(!('webkitEnterFullscreen' in window.HTMLAudioElement.prototype), 'audio elements have none');
}

{
  const window = makeWindow();
  install(window);
  const video = window.video();
  const seen = record(window, video);
  for (const type of ['webkitbeginfullscreen', 'webkitendfullscreen']) {
    video.addEventListener(type, (event) => seen.push(type + (event.bubbles ? ':bubbles' : '')));
  }
  const errorName = (fn) => { try { fn(); return 'none'; } catch (error) { return error.name; } };
  window.activation.active = true;
  check(!video.webkitSupportsFullscreen && errorName(() => video.webkitEnterFullscreen()) === 'InvalidStateError',
        'a video that never loaded can\'t enter fullscreen');
  video.load();
  check(video.webkitSupportsFullscreen, 'a loaded video supports fullscreen');
  window.activation.active = false;
  check(errorName(() => video.webkitEnterFullScreen()) === 'InvalidStateError' &&
        !window.log.includes('requestFullscreen'),
        'without a user gesture webkitEnterFullScreen throws InvalidStateError');
  window.activation.active = true;
  check(errorName(() => video.webkitEnterFullscreen()) === 'none' && window.log.includes('requestFullscreen'),
        'with one it asks for element fullscreen');
  window.activation.active = true;
  check(errorName(() => video.webkitEnterFullscreen()) === 'InvalidStateError',
        'a second call while the change is in progress throws');
  check(!video.webkitDisplayingFullscreen, 'not displaying fullscreen until it is');
  await settle();
  check(video.webkitDisplayingFullscreen && video.webkitPresentationMode === 'fullscreen',
        'displaying fullscreen once the document is');
  window.activation.active = false;
  check(errorName(() => video.webkitEnterFullscreen()) === 'none', 'entering again does nothing');
  check(seen.join() === 'mode:fullscreen,fullscreenchange', 'no webkitbeginfullscreen on macOS: ' + seen);
  seen.length = 0;
  video.webkitExitFullScreen();
  check(window.log.includes('exitFullscreen'), 'webkitExitFullScreen exits fullscreen');
  video.webkitExitFullscreen();
  await settle();
  check(window.log.filter((entry) => entry === 'exitFullscreen').length === 1,
        'a second exit while changing is ignored');
  check(seen.join() === 'mode:inline,fullscreenchange' && !video.webkitDisplayingFullscreen,
        'no webkitendfullscreen on leaving element fullscreen: ' + seen);
  video.webkitExitFullscreen();
  await settle();
  check(window.log.filter((entry) => entry === 'exitFullscreen').length === 1,
        'exiting an inline video does nothing');
}

{
  const window = makeWindow();
  install(window);
  const video = window.video();
  video.load();
  const seen = record(window, video);
  for (const type of ['webkitbeginfullscreen', 'webkitendfullscreen']) {
    video.addEventListener(type, (event) => seen.push(type + (event.bubbles ? ':bubbles' : '')));
  }
  window.activation.active = true;
  video.webkitEnterFullscreen();
  await settle();
  seen.length = 0;
  window.activation.active = true;
  video.webkitSetPresentationMode('picture-in-picture');
  await settle();
  check(seen.join() === 'mode:picture-in-picture,webkitendfullscreen,fullscreenchange,enterpictureinpicture',
        'fullscreen to picture in picture: ' + seen);
  check(video.webkitDisplayingFullscreen, 'picture in picture displays fullscreen');
  window.activation.active = true;
  video.webkitEnterFullscreen();
  await settle();
  check(window.log.filter((entry) => entry === 'requestFullscreen').length === 1,
        'webkitEnterFullscreen in picture in picture does nothing');
  seen.length = 0;
  video.webkitExitFullscreen();
  check(window.log.includes('exitPictureInPicture') && !video.webkitDisplayingFullscreen,
        'webkitExitFullscreen leaves picture in picture, reporting inline at once');
  await settle();
  check(seen.join() === 'mode:inline,leavepictureinpicture', 'leaving picture in picture: ' + seen);
  check(!seen.some((entry) => entry.startsWith('webkitbeginfullscreen')), 'never webkitbeginfullscreen');
}

{
  const window = makeWindow();
  install(window);
  const video = window.video();
  video.load();
  const seen = record(window, video);
  window.document.addEventListener('fullscreenerror', () => seen.push('fullscreenerror'));
  video.webkitSetPresentationMode('picture-in-picture');
  await settle();
  check(!window.log.includes('requestPictureInPicture'), 'no gesture yet: ignored');
  window.activation.active = true;
  video.play();
  window.activation.active = false;
  video.webkitSetPresentationMode('picture-in-picture');
  await settle();
  check(window.document.pictureInPictureElement === video && !window.pipToken,
        'the lifted rule enters picture in picture, using the token: ' + seen);
  check(seen.join() === 'mode:picture-in-picture,enterpictureinpicture',
        'its events are trusted: ' + seen);
  video.webkitSetPresentationMode('inline');
  await settle();
  seen.length = 0;
  let thrown = 'none';
  try { video.webkitEnterFullscreen(); } catch (error) { thrown = error.name; }
  await settle();
  check(thrown === 'none' && window.log.includes('requestFullscreen'),
        'webkitEnterFullscreen no longer throws');
  check(seen.join() === 'fullscreenerror' && video.webkitPresentationMode === 'inline',
        'element fullscreen still needs transient activation: ' + seen);
}

{
  const window = makeWindow();
  install(window, null);
  const video = window.video();
  video.load();
  const seen = [];
  video.addEventListener('webkitpresentationmodechanged', (event) => seen.push(event.isTrusted));
  window.activation.active = true;
  video.webkitSetPresentationMode('picture-in-picture');
  await settle();
  check(seen.join() === 'false' && video.webkitPresentationMode === 'picture-in-picture',
        'script-made events without the helpers: ' + seen);
}

{
  const window = makeWindow();
  install(window);
  const host = window.div();
  const video = window.video(host.attachShadow());
  video.load();
  const seen = [];
  video.addEventListener('webkitpresentationmodechanged', () => seen.push(video.webkitPresentationMode));
  check(!window.listenerTypes(video).some((type) => type.includes('fullscreen')),
        'no fullscreen listener of the script on a watched video: ' + window.listenerTypes(video));
  window.activation.active = true;
  video.webkitEnterFullscreen();
  await settle();
  check(!window.listenerTypes(video).some((type) => type.includes('fullscreen')),
        'none after entering fullscreen either');
  check(seen.join() === 'fullscreen' && window.document.fullscreenElement === host,
        'a shadow-tree video reports fullscreen: ' + seen);
  video.webkitExitFullscreen();
  await settle();
  check(seen.join() === 'fullscreen,inline', 'and leaving it: ' + seen);
}

{
  const window = makeWindow();
  install(window);
  const proto = window.HTMLVideoElement.prototype;
  const d = Object.getOwnPropertyDescriptor(proto, 'requestPictureInPicture');
  check(d && typeof d.value === 'function' && d.writable && d.enumerable && d.configurable &&
        d.value.name === 'requestPictureInPicture' && d.value.length === 0,
        'requestPictureInPicture stays a WebIDL operation');
  const video = window.video();
  video.load();
  window.activation.active = true;
  video.webkitEnterFullscreen();
  await settle();
  const seen = record(window, video);
  video.addEventListener('webkitendfullscreen', () => seen.push('webkitendfullscreen'));
  window.activation.active = true;
  const promise = video.requestPictureInPicture();
  check(typeof promise.then === 'function' && promise !== window.lastPictureInPictureRequest &&
        window.log.filter((entry) => entry === 'requestPictureInPicture').length === 1,
        'Chromium makes the request; the page gets its own promise for it, so its refusals ' +
        'still report as unhandled when the page leaves them so');
  check(video.webkitPresentationMode === 'fullscreen', 'still fullscreen during the call');
  await new Promise((r) => setTimeout(r, 0));
  check(video.webkitPresentationMode === 'picture-in-picture',
        'picture in picture from the task after the call');
  await settle();
  check(seen.join() === 'mode:picture-in-picture,webkitendfullscreen,fullscreenchange,enterpictureinpicture',
        'WebKit\'s order: ' + seen);
  let resolvedWith = null;
  await promise.then((value) => { resolvedWith = value; });
  check(resolvedWith !== null && typeof resolvedWith === 'object', 'it resolves with Chromium\'s window');
  check(window.document.pictureInPictureElement === video && window.document.fullscreenElement === null,
        'the standard API agrees');

  video.webkitSetPresentationMode('inline');
  await settle();
  seen.length = 0;
  let refused = false;
  video.requestPictureInPicture().catch(() => { refused = true; });
  await settle();
  check(refused && seen.length === 0 && video.webkitPresentationMode === 'inline',
        'a refused request (no gesture) changes nothing: ' + seen);
}

console.log(`webkit_presentation: ${checks} checks passed`);
