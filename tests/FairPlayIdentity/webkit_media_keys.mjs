// Runs the legacy EME script from Engine/ParcRenderer/parc_webkit_media_keys.h
// against a model of Chromium's Media Source and modern EME as a
// Safari-identity page sees them, with Parc's FairPlay CDM message formats.
// No browser; `node webkit_media_keys.mjs`.
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';

const header = readFileSync(fileURLToPath(new URL(
    '../../Engine/ParcRenderer/parc_webkit_media_keys.h', import.meta.url)), 'utf8');
const match = header.match(/R"PARC_WKMK_JS\(([\s\S]*)\)PARC_WKMK_JS"/);
if (!match) throw new Error('script not found in header');
const script = match[1];
// Blink runs it as a Latin-1 String.
if (/[^\x00-\x7f]/.test(script)) throw new Error('script must be ASCII');

let checks = 0;
function check(condition, message) {
  ++checks;
  if (!condition) {
    console.error('FAIL: ' + message);
    process.exit(1);
  }
}

// Chromium's Media Source on a Safari-identity page: MP4 and WebM, codec
// strings it parses, Dolby audio and Dolby Vision profile 5 included (the
// identity's gates in fairplay-identity-blink.patch). AV1, VP9, Opus and FLAC
// play there too, but not through FairPlay.
const MSE_CODECS = [
  /^avc[13]\.[0-9a-f]{6}$/i, /^(hvc1|hev1)\.[0-9a-z.]+$/i, /^(dvh1|dvhe)\.05\.\d\d$/i,
  /^av01\.[0-9.a-z]+$/i, /^vp09\.[0-9.]+$/, /^vp9$/, /^opus$/, /^flac$/,
  /^mp4a\.40\.\d+$/, /^mp4a\.6[678]$/, /^(ac-3|ec-3|mp4a\.a[56])$/i,
];
// A model of modern EME over Parc's FairPlay CDM: cenc and keyids sessions
// exchange JSON {keyID, payload} arrays, sinf sessions raw SPC and CKC, and
// "renew" asks for a renewal. `sinf` says whether the CDM takes sinf init data.
const text = (data) => Buffer.from(ArrayBuffer.isView(data) ?
    new Uint8Array(data.buffer, data.byteOffset, data.byteLength) : new Uint8Array(data)).toString('latin1');
const bytesOf = (value) => new Uint8Array(Buffer.from(value, 'latin1'));
function makeWorld({sinf = false, failSpc = 0} = {}) {
  const calls = [];
  const log = [];
  class MediaSource {
    static isTypeSupported(type) {
      calls.push(type);
      const [container, ...rest] = String(type).split(';');
      if (!/^(video|audio)\/(mp4|webm)$/i.test(container.trim())) return false;
      const parameter = rest.join(';').match(/codecs\s*=\s*(?:"([^"]*)"|([^;]*))/i);
      if (!parameter) return true;
      const codecs = (parameter[1] ?? parameter[2]).split(',').map((c) => c.trim());
      return codecs.every((codec) => MSE_CODECS.some((pattern) => pattern.test(codec)));
    }
  }
  class MediaKeyMessageEvent extends Event {
    #type; #message;
    constructor(type, init) { super(type); this.#type = init.messageType; this.#message = init.message; }
    get messageType() { return this.#type; }
    get message() { return this.#message; }
  }
  // The media pipeline's events are trusted; one a page builds isn't.
  class MediaEncryptedEvent extends Event {
    #type; #data; #trusted;
    constructor(type, init, trusted = false) {
      super(type); this.#type = init.initDataType; this.#data = init.initData; this.#trusted = trusted;
    }
    get isTrusted() { return this.#trusted; }
    get initDataType() { return this.#type; }
    get initData() { return this.#data; }
  }
  const spc = (keys, tag) => 'SPC(' + keys.certificate + ',' + tag + ')';
  class MediaKeySession extends EventTarget {
    #keys; #json = false; #lastKey = null;
    constructor(keys) { super(); this.#keys = keys; }
    send(type, entries) {
      const body = this.#json ? JSON.stringify(entries.map(([keyID, payload]) =>
          ({keyID, payload: Buffer.from(payload, 'latin1').toString('base64')}))) : entries[0][1];
      setTimeout(() => this.dispatchEvent(new MediaKeyMessageEvent('message',
          {messageType: type, message: bytesOf(body).buffer})));
    }
    generateRequest(type, data) {
      log.push(['generateRequest', type, text(data)]);
      if (type === 'sinf' && !sinf) {
        return Promise.reject(new DOMException('Unsupported initDataType', 'NotSupportedError'));
      }
      if (failSpc) {
        return Promise.reject(new DOMException('Rejected with system code (' + failSpc + ')', 'NotSupportedError'));
      }
      this.#json = type !== 'sinf';
      // Each pssh box in the model names one key; sinf names one.
      const keyIds = type === 'cenc' ? text(data).match(/pssh(\w+)/g).map((m) => m.slice(4)) : ['sinf-key'];
      this.#lastKey = keyIds[keyIds.length - 1];
      this.send('license-request', keyIds.map((id) => [id, spc(this.#keys, id)]));
      return Promise.resolve();
    }
    update(response) {
      const body = text(response);
      log.push(['update', body]);
      if (body === 'renew') {
        this.send('license-renewal', [[this.#lastKey, spc(this.#keys, 'renew:' + this.#lastKey)]]);
      }
      return Promise.resolve();
    }
    close() { log.push(['close']); return Promise.resolve(); }
  }
  class MediaKeys {
    certificate = null;
    setServerCertificate(certificate) {
      this.certificate = text(certificate);
      log.push(['setServerCertificate', this.certificate]);
      return Promise.resolve(true);
    }
    createSession(type) { log.push(['createSession', type]); return new MediaKeySession(this); }
  }
  class MediaKeySystemAccess {
    createMediaKeys() { log.push(['createMediaKeys']); return Promise.resolve(new MediaKeys()); }
  }
  class Navigator {
    requestMediaKeySystemAccess(keySystem, configurations) {
      log.push(['requestMediaKeySystemAccess', keySystem, configurations]);
      return Promise.resolve(new MediaKeySystemAccess());
    }
  }
  class HTMLMediaElement extends EventTarget {
    #keys = null; #paused = true; name;
    constructor(name = 'video') { super(); this.name = name; }
    get paused() { return this.#paused; }  // brand-checks like Blink's getter
    get mediaKeys() { return this.#keys; }
    setMediaKeys(keys) { log.push(['setMediaKeys', this.name, keys]); this.#keys = keys; return Promise.resolve(); }
  }
  class MediaError {}
  const context = {
    MediaSource, DOMException, Event, EventTarget, atob, btoa, setTimeout, TextDecoder,
    MediaKeyMessageEvent, MediaEncryptedEvent, MediaKeySession, MediaKeys,
    MediaKeySystemAccess, Navigator, navigator: new Navigator(), HTMLMediaElement, MediaError,
    calls, log,
  };
  context.window = context;
  vm.createContext(context);
  return context;
}
// Lets the script's tasks and promise chains run.
const settle = async () => { for (let i = 0; i < 20; ++i) await new Promise((r) => setTimeout(r, 0)); };
const run = (context, source) => vm.runInContext(source, context);
// Errors the script throws come from the context's realm (DOMException is
// shared), so TypeErrors are compared by name.
const thrown = (fn) => {
  try {
    fn();
  } catch (error) {
    return error;
  }
  return null;
};

// ---- Installation.
{
  const world = makeWorld();
  run(world, script);
  check(typeof world.WebKitMediaKeys === 'function', 'WebKitMediaKeys is installed');
  const descriptor = Object.getOwnPropertyDescriptor(world, 'WebKitMediaKeys');
  check(descriptor.writable && descriptor.configurable && !descriptor.enumerable,
        'installed like a WebIDL interface object (writable, configurable, not enumerable)');
  check(world.WebKitMediaKeys.name === 'WebKitMediaKeys', 'interface name');
  check(world.WebKitMediaKeys.length === 1 && world.WebKitMediaKeys.isTypeSupported.length === 1,
        'one required argument each, as WebIDL reports');

  // Netflix's akira client, exactly.
  check(run(world, '!!(window.WebKitMediaKeys && window.WebKitMediaKeys.isTypeSupported("com.apple.fps.2_0"))') === true,
        "Netflix's canPlayHTML5WithDRM check passes");
  check(run(world, '(() => { let a; return !!(null != (a = window.WebKitMediaKeys) && a.isTypeSupported("com.apple.fps.2_0")); })()') === true,
        "Netflix's capability observable passes");

  // Apple TV+'s MusicKit (mediakit~*.js), exactly: it probes only 1_0 and
  // must keep choosing standard EME.
  check(run(world, `(() => { const s = 'video/mp4; codecs="avc1.42E01E"', n = [];
      typeof window.WebKitMediaKeys?.isTypeSupported == "function" &&
          window.WebKitMediaKeys.isTypeSupported("com.apple.fps.1_0", s) === true && n.push("fairplay_legacy");
      return n.length; })()`) === 0, 'Apple TV+ hasWebKitMediaKeysSupport stays false');
  check(run(world, 'window.WebKitMediaKeys?.isTypeSupported(`com.apple.fps.1_0`, "audio/mp4")') === false,
        "Apple TV+'s media extension stays on standard EME");
}

// ---- Key systems: WebKit's legacy Media Source CDM only.
{
  const world = makeWorld();
  run(world, script);
  const supports = (...args) => world.WebKitMediaKeys.isTypeSupported(...args);
  for (const keySystem of ['com.apple.fps.2_0', 'com.apple.fps.3_0', 'com.apple.fps.2_1',
                           'com.apple.fps.3_0,1', 'COM.APPLE.FPS.3_0']) {
    check(supports(keySystem) === true, `${keySystem} is supported`);
  }
  for (const keySystem of ['com.apple.fps', 'com.apple.fps.1_0', 'com.apple.fps.4_0',
                           'com.apple.fps.2_', 'com.apple.fps.2_0,', 'com.apple.fps.2_0 ',
                           'com.widevine.alpha', 'org.w3c.clearkey', 'org.w3.clearkey',
                           'com.microsoft.playready', '', 'undefined']) {
    check(supports(keySystem) === false, `${JSON.stringify(keySystem)} is not supported`);
  }
  check(supports(undefined) === false, 'undefined key system is "undefined"');
  check(supports('com.apple.fps.3_0', undefined) === true, 'an undefined type is no type');
  check(supports('com.apple.fps.3_0', '') === true, 'an empty type is no type');
  check(supports('com.apple.fps.3_0', null) === false, 'a null type is "null"');
  check(thrown(() => supports())?.name === 'TypeError', 'isTypeSupported() needs a key system');
  check(thrown(() => supports(Symbol('fps')))?.name === 'TypeError', 'a Symbol is not a DOMString');
}

// ---- Content types: what Parc's FairPlay path plays.
{
  const world = makeWorld();
  run(world, script);
  const supports = (type) => world.WebKitMediaKeys.isTypeSupported('com.apple.fps.3_0', type);
  const yes = [
    'video/mp4',
    'audio/mp4',
    'video/mp4; codecs="avc1.640028"',
    'video/mp4; codecs="avc3.4d401f"',
    'VIDEO/MP4; CODECS="avc1.640028"',
    'video/mp4;codecs=avc1.640028',
    'video/mp4; codecs="hvc1.2.4.L153.B0"',
    'video/mp4; codecs="hev1.1.6.L93.B0"',
    'video/mp4; codecs="dvh1.05.06"',
    'video/mp4; codecs="dvhe.05.04"',
    'audio/mp4; codecs="mp4a.40.2"',
    'audio/mp4; codecs="mp4a.40.5"',
    'audio/mp4; codecs="mp4a.40.42"',
    'audio/mp4; codecs="ec-3"',
    'audio/mp4; codecs="ac-3"',
    'audio/mp4; codecs="mp4a.a6"',
    'video/mp4; codecs="avc1.640028, mp4a.40.2"',
  ];
  for (const type of yes) check(supports(type) === true, `FairPlay plays ${type}`);
  const no = [
    'video/mp4; codecs="av01.0.08M.08"',    // Media Source plays it, FairPlay's CDM doesn't list AV1
    'video/mp4; codecs="vp09.00.10.08"',
    'video/webm; codecs="vp9"',
    'video/webm',
    'audio/mp4; codecs="opus"',
    'audio/mp4; codecs="flac"',
    'audio/mp4; codecs="mp4a.6B"',          // MP3
    'video/mp4; codecs="dvhe.08.07"',       // profile 8 isn't offered
    'video/mp4; codecs="avc1.640028,opus"',
    'video/mp4; codecs="avc1.640028,"',
    'video/mp4; codecs=""',
    'video/mp4; codecs="avc1.zzz"',         // Media Source rejects it
    'application/x-mpegurl',
    'application/vnd.apple.mpegurl',
    'video/mp2t',
    'keyrelease',
    'mp4',
  ];
  for (const type of no) check(supports(type) === false, `FairPlay doesn't play ${type}`);
  check(world.WebKitMediaKeys.isTypeSupported('com.apple.fps.1_0', 'video/mp4') === false,
        'a type never makes an unsupported key system supported');
}

// ---- A page replacing MediaSource.isTypeSupported doesn't change the answers.
{
  const world = makeWorld();
  run(world, script);
  run(world, 'MediaSource.isTypeSupported = () => false;');
  check(world.WebKitMediaKeys.isTypeSupported('com.apple.fps.3_0', 'video/mp4; codecs="avc1.640028"') === true,
        "a page's MediaSource.isTypeSupported polyfill doesn't change the answer");
  run(world, 'MediaSource.isTypeSupported = () => true;');
  check(world.WebKitMediaKeys.isTypeSupported('com.apple.fps.3_0', 'video/mp4; codecs="avc1.zzz"') === false,
        "Chromium's own answer is used");
}

// ---- Without MediaSource only the key system can be answered.
{
  const context = { DOMException };
  vm.createContext(context);
  run(context, script);
  check(context.WebKitMediaKeys.isTypeSupported('com.apple.fps.2_0') === true, 'key system alone');
  check(context.WebKitMediaKeys.isTypeSupported('com.apple.fps.2_0', 'video/mp4') === false,
        'no type is playable without Media Source');
}

// ---- An existing WebKitMediaKeys is left alone.
{
  const world = makeWorld();
  run(world, 'globalThis.WebKitMediaKeys = function Existing() {};');
  run(world, script);
  check(world.WebKitMediaKeys.name === 'Existing', 'an existing WebKitMediaKeys is kept');
}

// ---- The constructor: WebKit's legacy Media Source CDM.
{
  const world = makeWorld();
  run(world, script);
  const construct = (...args) => thrown(() => new world.WebKitMediaKeys(...args));
  for (const keySystem of ['com.apple.fps.2_0', 'com.apple.fps.3_0', 'com.apple.fps.3_0,1',
                           'COM.APPLE.FPS.2_1']) {
    check(construct(keySystem) === null, `new WebKitMediaKeys(${keySystem}) succeeds`);
    check(new world.WebKitMediaKeys(keySystem).keySystem === keySystem, `${keySystem} keySystem`);
  }
  for (const keySystem of ['com.apple.fps', 'com.apple.fps.1_0', 'com.widevine.alpha',
                           'org.w3c.clearkey', 'com.apple.fps.4_0']) {
    const error = construct(keySystem);
    check(error instanceof DOMException && error.name === 'NotSupportedError',
          `new WebKitMediaKeys(${keySystem}) throws NotSupportedError`);
  }
  const empty = construct('');
  check(empty instanceof DOMException && empty.name === 'InvalidAccessError',
        'an empty key system throws InvalidAccessError');
  check(construct()?.name === 'TypeError', 'the constructor needs a key system');
  check(thrown(() => world.WebKitMediaKeys('com.apple.fps.2_0'))?.name === 'TypeError',
        'calling it without new throws TypeError');
  // Disney+'s native client (dwp bundle), exactly: 1_0 is native HLS, still
  // refused, and the failure stays inside its try.
  check(run(world, `((J = WebKitMediaKeys) => { try { new J("com.apple.fps.1_0"); return "made"; }
      catch (e) { return e.name; } })()`) === 'NotSupportedError', "Disney+'s native client catches it");
}

// ---- Without modern EME (an insecure context) no keys can be made.
{
  const context = { MediaSource: makeWorld().MediaSource, DOMException, Event, EventTarget };
  vm.createContext(context);
  run(context, script);
  check(context.WebKitMediaKeys.isTypeSupported('com.apple.fps.2_0') === true,
        "Netflix's check still answers");
  check(thrown(() => new context.WebKitMediaKeys('com.apple.fps.3_0'))?.name === 'NotSupportedError',
        'keys need modern EME underneath');
}

// ---- Interfaces.
{
  const world = makeWorld();
  run(world, script);
  for (const name of ['WebKitMediaKeys', 'WebKitMediaKeySession', 'WebKitMediaKeyError',
                      'WebKitMediaKeyMessageEvent', 'WebKitMediaKeyNeededEvent']) {
    const descriptor = Object.getOwnPropertyDescriptor(world, name);
    check(descriptor && descriptor.writable && descriptor.configurable && !descriptor.enumerable,
          `${name} is installed like a WebIDL interface object`);
    check(run(world, `Object.prototype.toString.call(${name}.prototype)`) === `[object ${name}]`,
          `${name} has its toStringTag`);
  }
  check(thrown(() => new world.WebKitMediaKeySession())?.name === 'TypeError',
        'WebKitMediaKeySession has no constructor');
  check(thrown(() => new world.WebKitMediaKeyError())?.name === 'TypeError',
        'WebKitMediaKeyError has no constructor');
  const codes = ['UNKNOWN', 'CLIENT', 'SERVICE', 'OUTPUT', 'HARDWARECHANGE', 'DOMAIN'];
  codes.forEach((code, index) => {
    check(world.WebKitMediaKeyError['MEDIA_KEYERR_' + code] === index + 1 &&
          world.WebKitMediaKeyError.prototype['MEDIA_KEYERR_' + code] === index + 1,
          `MEDIA_KEYERR_${code} is ${index + 1}`);
  });
  check(world.MediaError.MEDIA_ERR_ENCRYPTED === 5 && world.MediaError.prototype.MEDIA_ERR_ENCRYPTED === 5,
        'MediaError.MEDIA_ERR_ENCRYPTED is 5');
  const message = new Uint8Array([1, 2]);
  const event = new world.WebKitMediaKeyMessageEvent('webkitkeymessage', {message, destinationURL: 7});
  check(event.type === 'webkitkeymessage' && event.message === message && event.destinationURL === '7',
        'WebKitMediaKeyMessageEvent takes its init dictionary');
  const bare = new world.WebKitMediaKeyMessageEvent('x');
  check(bare.message === null && bare.destinationURL === '' && bare instanceof Event,
        'WebKitMediaKeyMessageEvent defaults');
  check(thrown(() => new world.WebKitMediaKeyMessageEvent('x', {message: [1]}))?.name === 'TypeError',
        'message must be a Uint8Array');
  check(new world.WebKitMediaKeyNeededEvent('webkitneedkey', {initData: message}).initData === message,
        'WebKitMediaKeyNeededEvent carries initData');
  check(new world.WebKitMediaKeyNeededEvent('webkitneedkey').initData === null, 'initData defaults to null');
  check(thrown(() => new world.WebKitMediaKeyNeededEvent())?.name === 'TypeError', 'event type required');
  const video = new world.HTMLMediaElement();
  check(video.webkitKeys === null, 'webkitKeys starts null');
  check(thrown(() => world.HTMLMediaElement.prototype.webkitSetMediaKeys.call({}, null))?.name === 'TypeError',
        'webkitSetMediaKeys checks its receiver');
  check(thrown(() => video.webkitSetMediaKeys({}))?.name === 'TypeError',
        'webkitSetMediaKeys takes WebKitMediaKeys or null');
  check(thrown(() => video.webkitSetMediaKeys())?.name === 'TypeError', 'webkitSetMediaKeys needs an argument');
  check(world.HTMLMediaElement.prototype.webkitSetMediaKeys.length === 1 &&
        world.HTMLMediaElement.prototype.addEventListener.length === 2, 'operation lengths');
}

// ---- Argument checks of createSession and update.
{
  const world = makeWorld();
  run(world, script);
  const keys = new world.WebKitMediaKeys('com.apple.fps.3_0');
  const data = new Uint8Array([1]);
  const name = (fn) => thrown(fn)?.name;
  check(name(() => keys.createSession('video/mp4')) === 'TypeError', 'createSession needs two arguments');
  check(name(() => keys.createSession('video/mp4', [1])) === 'TypeError', 'initData must be a Uint8Array');
  check(name(() => keys.createSession('', data)) === 'InvalidAccessError', 'an empty type');
  check(name(() => keys.createSession('video/mp4', new Uint8Array())) === 'InvalidAccessError', 'empty init data');
  check(name(() => keys.createSession('video/webm', data)) === 'NotSupportedError', 'a type FairPlay does not play');
  check(name(() => keys.createSession('KeyRelease', data)) === 'NotSupportedError', 'keyrelease is case-sensitive');
  check(name(() => world.WebKitMediaKeys.prototype.createSession.call({}, 'video/mp4', data)) === 'TypeError',
        'createSession checks its receiver');
  const session = keys.createSession('video/mp4; codecs="avc1.640028"', data);
  check(session instanceof world.WebKitMediaKeySession && session instanceof EventTarget, 'a session');
  check(session.sessionId === '' && session.error === null && session.keySystem === 'com.apple.fps.3_0',
        'a Media Source session has no ID until it has a report, as in WebKit');
  check(name(() => session.update()) === 'TypeError', 'update needs an argument');
  check(name(() => session.update(new Uint8Array())) === 'InvalidAccessError', 'update needs bytes');
  check(name(() => session.update('ckc')) === 'TypeError', 'update takes a Uint8Array');
}

// A pssh box naming one key in the model.
const pssh = (id) => {
  const body = Buffer.from('pssh' + id, 'latin1');
  const box = Buffer.alloc(4 + body.length);
  box.writeUInt32BE(box.length, 0);
  body.copy(box, 4);
  return box;
};
const encrypted = (world, element, initDataType, bytes) =>
    element.dispatchEvent(new world.MediaEncryptedEvent('encrypted',
        {initDataType, initData: new Uint8Array(bytes).buffer}, true));

// ---- com.apple.fps.3_0 over cenc init data: the whole protocol.
{
  const world = makeWorld();
  run(world, script);
  const video = new world.HTMLMediaElement();
  const needs = [];
  video.addEventListener('webkitneedkey', (event) => needs.push(event));
  const initData = Buffer.concat([pssh('A'), pssh('B')]);
  encrypted(world, video, 'cenc', initData);
  check(needs.length === 1 && needs[0] instanceof world.WebKitMediaKeyNeededEvent &&
        text(needs[0].initData) === initData.toString('latin1'),
        'webkitneedkey carries the encrypted event\'s init data');
  check(!needs[0].bubbles && !needs[0].cancelable, 'webkitneedkey neither bubbles nor cancels');
  encrypted(world, video, 'webm', Buffer.from('x'));
  check(needs.length === 1, 'no webkitneedkey for init data FairPlay never uses');

  const keys = new world.WebKitMediaKeys('com.apple.fps.3_0');
  video.webkitSetMediaKeys(keys);
  check(video.webkitKeys === keys, 'webkitKeys');
  video.webkitSetMediaKeys(keys);
  const session = keys.createSession('video/mp4', needs[0].initData);
  const events = [];
  session.addEventListener('webkitkeymessage', (event) => events.push(['message', text(event.message), event]));
  session.onwebkitkeyadded = () => events.push(['added']);
  session.addEventListener('webkitkeyerror', () => events.push(['error', session.error.code]));
  check(typeof session.onwebkitkeyadded === 'function' && session.onwebkitkeymessage === null, 'handlers');
  check(events.length === 0, 'the first message is a task');
  await settle();
  check(events.length === 1 && events[0][1] === 'certificate' && events[0][2].destinationURL === '' &&
        events[0][2] instanceof world.WebKitMediaKeyMessageEvent, 'the first message asks for the certificate');
  const access = world.log.find((entry) => entry[0] === 'requestMediaKeySystemAccess');
  check(access && access[1] === 'com.apple.fps' && access[2][0].initDataTypes.includes('cenc') &&
        access[2][0].sessionTypes[0] === 'temporary', 'the keys are modern FairPlay keys');
  const attached = world.log.find((entry) => entry[0] === 'setMediaKeys');
  check(attached && attached[1] === 'video' && attached[2] instanceof world.MediaKeys,
        'webkitSetMediaKeys attaches the modern keys');
  check(video.mediaKeys === null, 'legacy keys stay out of mediaKeys');
  check(world.log.filter((entry) => entry[0] === 'createMediaKeys').length === 1, 'one MediaKeys per WebKitMediaKeys');

  session.update(new Uint8Array(bytesOf('CERT')));
  await settle();
  const order = world.log.map((entry) => entry[0]).join(',');
  check(/setServerCertificate,createSession,generateRequest/.test(order), 'certificate, then the request');
  check(world.log.find((entry) => entry[0] === 'generateRequest')[1] === 'cenc', 'cenc init data');
  check(events.length === 3 && events[1][1] === 'SPC(CERT,A)' && events[2][1] === 'SPC(CERT,B)',
        'one SPC per key, unwrapped from the JSON message');

  session.update(new Uint8Array(bytesOf('CKC-A')));
  session.update(new Uint8Array(bytesOf('CKC-B')));
  await settle();
  const updates = world.log.filter((entry) => entry[0] === 'update').map((entry) => JSON.parse(entry[1]));
  check(updates.length === 2 && updates[0][0].keyID === 'A' && updates[1][0].keyID === 'B' &&
        Buffer.from(updates[0][0].payload, 'base64').toString() === 'CKC-A',
        'each CKC answers the oldest SPC, wrapped for the CDM');
  check(events.filter((e) => e[0] === 'added').length === 2, 'webkitkeyadded after each accepted CKC');

  session.update(new Uint8Array(bytesOf('renew')));
  await settle();
  check(world.log.some((entry) => entry[0] === 'update' && entry[1] === 'renew'), 'renew reaches the CDM');
  check(events[events.length - 1][1] === 'SPC(CERT,renew:B)', 'the renewal SPC is a message');
  session.update(new Uint8Array(bytesOf('CKC-R')));
  await settle();
  check(JSON.parse(world.log.filter((e) => e[0] === 'update').pop()[1])[0].keyID === 'B',
        'the renewal answer goes to the renewed key');

  const before = events.length;
  session.close();
  session.update(new Uint8Array(bytesOf('late')));
  await settle();
  check(world.log[world.log.length - 1][0] === 'close' && events.length === before,
        'close() closes the modern session and later updates are dropped');
  session.close();

  video.webkitSetMediaKeys(null);
  await settle();
  check(video.webkitKeys === null && world.log[world.log.length - 1][0] === 'setMediaKeys' &&
        world.log[world.log.length - 1][2] === null, 'webkitSetMediaKeys(null) detaches');
}

// ---- sinf init data: raw SPC and CKC once the CDM takes sinf; until then
// a DOMAIN error with the system code.
for (const sinf of [true, false]) {
  const world = makeWorld({sinf});
  run(world, script);
  const keys = new world.WebKitMediaKeys('com.apple.fps.3_0');
  const session = keys.createSession('video/mp4', new Uint8Array(bytesOf('{"sinf":["AAAA"]}')));
  const events = [];
  session.addEventListener('webkitkeymessage', (event) => events.push(text(event.message)));
  session.addEventListener('webkitkeyerror', () => events.push('error:' + session.error.code));
  session.addEventListener('webkitkeyadded', () => events.push('added'));
  await settle();
  session.update(new Uint8Array(bytesOf('CERT')));
  await settle();
  if (sinf) {
    check(world.log.find((entry) => entry[0] === 'generateRequest')[1] === 'sinf', 'sinf init data');
    check(events.join() === 'certificate,SPC(CERT,sinf-key)', 'the raw SPC');
    session.update(new Uint8Array(bytesOf('CKC')));
    await settle();
    check(world.log.filter((entry) => entry[0] === 'update').pop()[1] === 'CKC' &&
          events[events.length - 1] === 'added', 'the raw CKC');
  } else {
    check(events.join() === 'certificate,error:6' && session.error instanceof world.WebKitMediaKeyError,
          'a request the CDM refuses is a DOMAIN key error');
  }
}
{
  const world = makeWorld({failSpc: 42});
  run(world, script);
  const keys = new world.WebKitMediaKeys('com.apple.fps.3_0');
  const session = keys.createSession('video/mp4', new Uint8Array(pssh('A')));
  await settle();
  session.update(new Uint8Array(bytesOf('CERT')));
  await settle();
  check(session.error && session.error.code === 6 && session.error.systemCode === 42,
        "the CDM's system code reaches WebKitMediaKeyError.systemCode");
  const unknown = keys.createSession('video/mp4', new Uint8Array(bytesOf('not init data')));
  await settle();
  unknown.update(new Uint8Array(bytesOf('CERT')));
  await settle();
  check(unknown.error && unknown.error.code === 6, 'init data Parc cannot read is a DOMAIN key error');
}

// ---- com.apple.fps.2_0: the init data comes from the attached media.
{
  const world = makeWorld();
  run(world, script);
  const video = new world.HTMLMediaElement();
  const keys = new world.WebKitMediaKeys('com.apple.fps.2_0');
  video.webkitSetMediaKeys(keys);
  const session = keys.createSession('video/mp4', new Uint8Array(bytesOf('content-id')));
  const events = [];
  session.addEventListener('webkitkeymessage', (event) => events.push(text(event.message)));
  session.addEventListener('webkitkeyerror', () => events.push('error:' + session.error.code));
  await settle();
  session.update(new Uint8Array(bytesOf('CERT')));
  await settle();
  check(events.join() === 'certificate,error:1', 'no protected media yet: InvalidPlayerState');
  // The window sees encrypted events of elements in its tree; here the
  // element forwards once keys are set on it.
  encrypted(world, video, 'cenc', pssh('C'));
  const second = keys.createSession('video/mp4', new Uint8Array(bytesOf('content-id')));
  second.addEventListener('webkitkeymessage', (event) => events.push(text(event.message)));
  await settle();
  second.update(new Uint8Array(bytesOf('CERT')));
  await settle();
  check(world.log.find((entry) => entry[0] === 'generateRequest')?.[2] === pssh('C').toString('latin1'),
        "the request uses the media's init data");
  check(events.slice(-2).join() === 'certificate,SPC(CERT,C)', 'then the SPC');
}

// ---- keyrelease (secure stop): Parc keeps no expired-session reports.
{
  const world = makeWorld();
  run(world, script);
  const keys = new world.WebKitMediaKeys('com.apple.fps.3_0');
  const session = keys.createSession('keyrelease', new Uint8Array(bytesOf('CERT')));
  let error = null;
  session.onwebkitkeyerror = () => { error = session.error; };
  await settle();
  check(error && error.code === 2 && error.systemCode === 0x216d6f72,
        "keyrelease answers as WebKit does without reports ('!mor')");
  const other = keys.createSession('video/mp4', new Uint8Array(pssh('A')));
  await settle();
  other.update(new Uint8Array(bytesOf('acknowledged')));
  await settle();
  check(other.error && other.error.code === 1, 'acknowledged without a report: InvalidPlayerState');
  const closed = keys.createSession('video/mp4', new Uint8Array(pssh('A')));
  const messages = [];
  closed.onwebkitkeymessage = () => messages.push(1);
  closed.close();
  await settle();
  check(messages.length === 0, 'a session closed at once sends nothing');
}

// ---- skd init data (native HLS) in WebKit's legacy layout.
{
  const world = makeWorld();
  run(world, script);
  const audio = new world.HTMLMediaElement('audio');
  let initData = null;
  audio.addEventListener('webkitneedkey', (event) => { initData = event.initData; });
  encrypted(world, audio, 'skd', Buffer.from('skd://key-é', 'utf8'));
  const view = new DataView(initData.buffer, initData.byteOffset, initData.byteLength);
  const uri = 'skd://key-é';
  check(view.getUint32(0, true) === uri.length * 2 &&
        Buffer.from(initData.slice(4)).toString('utf16le') === uri,
        'webkitneedkey gets the skd URI as length + UTF-16');
}

// ---- Keys follow the last element; a page replacing the modern API after
// the script ran (Shaka's PatchedMediaKeysApple) doesn't reach the keys.
{
  const world = makeWorld();
  run(world, script);
  run(world, `
    navigator.requestMediaKeySystemAccess = () => { throw new Error('patched rMKSA'); };
    HTMLMediaElement.prototype.setMediaKeys = function() { throw new Error('patched setMediaKeys'); };
    MediaKeys.prototype.createSession = () => { throw new Error('patched createSession'); };`);
  const first = new world.HTMLMediaElement('first');
  const second = new world.HTMLMediaElement('second');
  const keys = new world.WebKitMediaKeys('com.apple.fps.3_0');
  first.webkitSetMediaKeys(keys);
  second.webkitSetMediaKeys(keys);
  await settle();
  const attaches = world.log.filter((entry) => entry[0] === 'setMediaKeys')
      .map((entry) => entry[1] + ':' + (entry[2] ? 'keys' : 'null'));
  check(attaches.join() === 'second:keys' || attaches.join() === 'first:null,second:keys',
        'the keys end on the second element, through the native setMediaKeys');
  check(first.webkitKeys === keys && second.webkitKeys === keys,
        'each element still reports the keys set on it, as in WebKit');
  const session = keys.createSession('video/mp4', new Uint8Array(pssh('A')));
  await settle();
  session.update(new Uint8Array(bytesOf('CERT')));
  await settle();
  check(world.log.some((entry) => entry[0] === 'generateRequest'), 'the native modern EME is used');
}

// ---- Only the pipeline's own encrypted events raise webkitneedkey, once each.
{
  const world = makeWorld();
  run(world, script);
  const video = new world.HTMLMediaElement();
  const needs = [];
  video.addEventListener('webkitneedkey', (event) => {
    needs.push(event);
    // Shaka's PatchedMediaKeysApple answers with a script-made encrypted event.
    video.dispatchEvent(new Event('encrypted'));
    video.dispatchEvent(new world.MediaEncryptedEvent('encrypted',
        {initDataType: 'cenc', initData: new Uint8Array(pssh('Z')).buffer}));
  });
  const event = new world.MediaEncryptedEvent('encrypted',
      {initDataType: 'cenc', initData: new Uint8Array(pssh('A')).buffer}, true);
  check(thrown(() => video.dispatchEvent(event)) === null, 'a script-made encrypted event throws nothing');
  check(needs.length === 1, "a page's own encrypted events raise no webkitneedkey (no loop)");
  video.dispatchEvent(event);
  check(needs.length === 1, 'an event raises webkitneedkey once');
}

// ---- An ordinary addEventListener still works on media elements.
{
  const world = makeWorld();
  run(world, script);
  const video = new world.HTMLMediaElement();
  let seen = 0;
  video.addEventListener('play', () => ++seen, {once: true});
  video.dispatchEvent(new Event('play'));
  video.dispatchEvent(new Event('play'));
  check(seen === 1, 'listener options pass through');
}

console.log(`webkit media keys: ${checks} checks passed`);
