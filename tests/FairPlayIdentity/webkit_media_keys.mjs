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
// `privateWindow` refuses persistent state, as Chromium's FairPlay selector
// does off the record; `reports` are the storage's expired-session reports for
// "first", `sessionReport` the one a legacy key session leaves for "session".
function makeWorld({sinf = true, failSpc = 0, privateWindow = false, reports = [],
                    sessionReport = null} = {}) {
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
  class MediaKeyStatusMap {
    #map;
    constructor(map) { this.#map = map; }
    forEach(callback) { for (const [keyId, status] of this.#map) callback(status, keyId, this); }
  }
  class MediaKeySession extends EventTarget {
    #keys; #json = false; #lastKey = null; #statuses = new Map();
    constructor(keys) { super(); this.#keys = keys; }
    get keyStatuses() { return new MediaKeyStatusMap(this.#statuses); }
    // The CDM reporting key statuses (keystatuseschange).
    setStatuses(entries) {
      this.#statuses = new Map(entries);
      this.dispatchEvent(new Event('keystatuseschange'));
    }
    send(type, entries) {
      const body = this.#json ? JSON.stringify(entries.map(([keyID, payload]) =>
          ({keyID, payload: Buffer.from(payload, 'latin1').toString('base64')}))) : entries[0][1];
      setTimeout(() => this.dispatchEvent(new MediaKeyMessageEvent('message',
          {messageType: type, message: bytesOf(body).buffer})));
    }
    #report = null;
    generateRequest(type, data) {
      log.push(['generateRequest', type, text(data)]);
      if (type === 'sinf' && JSON.parse(text(data)).legacySecureStop) {
        // Parc's CDM: WebKit's legacy secure stop (fairplay_key_session.mm).
        const operation = JSON.parse(text(data)).legacySecureStop;
        const none = () => Promise.reject(
            new DOMException('no expired-session report (560820082)', 'NotSupportedError'));
        if (!this.#keys.storage) return none();
        const report = operation === 'first' ? reports[0] : sessionReport;
        if (!report) return none();
        this.#report = report;
        setTimeout(() => this.dispatchEvent(new MediaKeyMessageEvent('message',
            {messageType: 'license-release', message: bytesOf(report).buffer})));
        return Promise.resolve();
      }
      if (type === 'sinf' && !sinf) {
        return Promise.reject(new DOMException('Unsupported initDataType', 'NotSupportedError'));
      }
      if (failSpc) {
        return Promise.reject(new DOMException('Rejected with system code (' + failSpc + ')', 'NotSupportedError'));
      }
      let innerType = type;
      let inner = text(data);
      if (type === 'skd') {
        // Parc's skd extension for the legacy AVFoundation player: the key
        // URI and the SPC's content ID.
        const json = JSON.parse(inner);
        this.#json = false;
        this.#lastKey = 'skd:' + json.skd + ':' + Buffer.from(json.contentId, 'base64').toString();
        this.send('license-request', [[this.#lastKey, spc(this.#keys, this.#lastKey)]]);
        return Promise.resolve();
      }
      if (type === 'keyids') {
        // Blink's SanitizeInitData rebuilds keyids init data from its key IDs
        // alone, so nothing else in it reaches the CDM.
        let json;
        try {
          json = JSON.parse(inner);
        } catch (error) {
        }
        if (!json || !Array.isArray(json.kids) || !json.kids.length) {
          return Promise.reject(new TypeError('Invalid keyids init data'));
        }
        inner = JSON.stringify({kids: json.kids});
      }
      if (innerType === 'sinf' && !sinf) {
        return Promise.reject(new DOMException('Unsupported initDataType', 'NotSupportedError'));
      }
      this.#json = innerType !== 'sinf';
      // Each pssh box in the model names one key; sinf names one.
      const keyIds = innerType === 'cenc' ? inner.match(/pssh(\w+)/g).map((m) => m.slice(4)) : ['sinf-key'];
      this.#lastKey = keyIds[keyIds.length - 1];
      this.send('license-request', keyIds.map((id) => [id, spc(this.#keys, id)]));
      return Promise.resolve();
    }
    update(response) {
      const body = text(response);
      log.push(['update', body]);
      if (body === 'acknowledged') {
        if (!this.#report) return Promise.reject(new TypeError('nothing to acknowledge'));
        log.push(['acknowledge', this.#report]);
        return Promise.resolve();
      }
      if (body === 'renew') {
        this.send('license-renewal', [[this.#lastKey, spc(this.#keys, 'renew:' + this.#lastKey)]]);
      }
      // A CKC AVFoundation rejects.
      const ckc = this.#json && body.startsWith('[') ?
          JSON.parse(body).map((entry) => Buffer.from(entry.payload, 'base64').toString('latin1')).join() : body;
      if (ckc === 'BAD-CKC') return Promise.reject(new TypeError('license response rejected'));
      return Promise.resolve();
    }
    close() { log.push(['close']); return Promise.resolve(); }
  }
  class MediaKeys {
    certificate = null;
    storage;
    constructor(storage) { this.storage = storage; }
    setServerCertificate(certificate) {
      this.certificate = text(certificate);
      log.push(['setServerCertificate', this.certificate]);
      return Promise.resolve(true);
    }
    createSession(type) {
      const session = new MediaKeySession(this);
      log.push(['createSession', type, session]);
      return session;
    }
  }
  class MediaKeySystemAccess {
    #configuration;
    constructor(configuration) { this.#configuration = configuration; }
    getConfiguration() { return this.#configuration; }
    createMediaKeys() {
      log.push(['createMediaKeys']);
      return Promise.resolve(new MediaKeys(
          this.#configuration.sessionTypes.includes('persistent-usage-record')));
    }
  }
  class Navigator {
    requestMediaKeySystemAccess(keySystem, configurations) {
      log.push(['requestMediaKeySystemAccess', keySystem, configurations]);
      const chosen = configurations.find(
          (configuration) => !(privateWindow && configuration.persistentState === 'required'));
      return Promise.resolve(new MediaKeySystemAccess(chosen));
    }
  }
  class HTMLMediaElement extends EventTarget {
    #keys = null; #paused = true; name;
    constructor(name = 'video') { super(); this.name = name; }
    get paused() { return this.#paused; }  // brand-checks like Blink's getter
    get mediaKeys() { return this.#keys; }
    // Blink refuses a setMediaKeys while another on the element is pending.
    #attaching = false;
    setMediaKeys(keys) {
      if (this.#attaching) {
        log.push(['setMediaKeys refused', this.name, keys]);
        return Promise.reject(new DOMException('Another request is in progress.', 'InvalidStateError'));
      }
      this.#attaching = true;
      log.push(['setMediaKeys', this.name, keys]);
      return new Promise((resolve) => setTimeout(() => {
        this.#keys = keys; this.#attaching = false; resolve();
      }));
    }
  }
  class MediaError {}
  const context = {
    MediaSource, DOMException, Event, EventTarget, atob, btoa, setTimeout, TextDecoder,
    TextEncoder, crypto,
    MediaKeyMessageEvent, MediaEncryptedEvent, MediaKeySession, MediaKeyStatusMap, MediaKeys,
    MediaKeySystemAccess, Navigator, navigator: new Navigator(), HTMLMediaElement, MediaError,
    calls, log,
  };
  context.window = context;
  vm.createContext(context);
  return context;
}
// Lets the script's tasks and promise chains run.
const settle = async () => { for (let i = 0; i < 20; ++i) await new Promise((r) => setTimeout(r, 0)); };
// The browser's AVAssetMIMETypeCache::canDecodeType answer as AVFoundation
// gave it on macOS 27.2 (AVURLAsset.audiovisualMIMETypes, then
// isPlayableExtendedMIMEType for the codecs; case-sensitive, avc3, hev1 and
// dvhe answer no). Blink gives it to the script's hook
// (parc_webkit_need_key.h); run() does the same here.
const AVFOUNDATION_TYPES = new Set((
    'application/mp4 application/ogg application/ttml+xml ' +
    'application/vnd.apple.mpegurl application/x-mpegurl audio/3gpp audio/3gpp2 ' +
    'audio/amr audio/amr-wb audio/aac audio/aacp audio/aiff audio/basic audio/flac ' +
    'audio/mp3 audio/mp4 audio/mpa audio/mpeg audio/mpeg3 audio/mpegurl audio/mpg ' +
    'audio/ogg audio/scpls audio/usac audio/vnd.wave audio/wav audio/wave audio/x-aac ' +
    'audio/x-aiff audio/x-caf audio/x-m4a audio/x-m4b audio/x-m4p audio/x-m4r ' +
    'audio/x-mp3 audio/x-mpeg audio/x-mpeg3 audio/x-mpegurl audio/x-mpg ' +
    'audio/x-quicktime audio/x-scpls audio/x-wav text/scc text/vtt video/3gpp ' +
    'video/3gpp2 video/avi video/dv video/m2ts video/mp1s video/mp2p video/mp2t ' +
    'video/mp4 video/mpeg video/mpeg2 video/mpg video/msvideo video/quicktime ' +
    'video/vnd.avi video/x-dv video/x-m2ts video/x-m4v video/x-mp1s video/x-mp2p ' +
    'video/x-mp2t video/x-mpeg video/x-mpeg2 video/x-mpg video/x-msvideo').split(' '));
const AVFOUNDATION_CODECS = [
  /^avc1(?:\.|$)/, /^hvc1(?:\.|$)/, /^dvh1(?:\.|$)/, /^av01(?:\.|$)/, /^mp4v(?:\.|$)/,
  /^mp4a\.(?:40(?:\.\d+)?|67)$/,
  /^(?:ac-3|ec-3|alac|fLaC|Opus|ulaw|alaw|wvtt)$/,
];
const avFoundationAsked = [];
function canPlayAVFoundationType(type) {
  avFoundationAsked.push(type);
  const container = String(type).split(';')[0].trim().toLowerCase();
  if (!AVFOUNDATION_TYPES.has(container)) return false;
  const parameter = /;\s*codecs\s*=\s*(?:"([^"]*)"|([^;]*))/i.exec(type);
  if (!parameter) return true;
  const list = parameter[1] !== undefined ? parameter[1] : parameter[2];
  const codecs = list.split(',').map((codec) => codec.trim()).filter((codec) => codec);
  return codecs.every((codec) => AVFOUNDATION_CODECS.some((pattern) => pattern.test(codec)));
}
const run = (context, source) => {
  const value = vm.runInContext(source, context);
  if (source === script && typeof value === 'function') {
    value.canPlayAVFoundationType = canPlayAVFoundationType;
  }
  return value;
};
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

  // Apple TV+'s MusicKit (mediakit~*.js), exactly: it probes only 1_0, and
  // gets Safari's answer now that native HLS plays it.
  check(run(world, `(() => { const s = 'video/mp4; codecs="avc1.42E01E"', n = [];
      typeof window.WebKitMediaKeys?.isTypeSupported == "function" &&
          window.WebKitMediaKeys.isTypeSupported("com.apple.fps.1_0", s) === true && n.push("fairplay_legacy");
      return n.length; })()`) === 1, "Apple TV+ hasWebKitMediaKeysSupport is true, as in Safari");
  check(run(world, 'window.WebKitMediaKeys?.isTypeSupported(`com.apple.fps.1_0`, "audio/mp4")') === true,
        "Apple TV+'s media extension sees Safari's 1_0 answer");
}

// ---- Key systems: WebKit's legacy Media Source CDM's (the AVFoundation
// player's com.apple.fps, 1_0 and org.w3c.clearkey are checked below).
{
  const world = makeWorld();
  run(world, script);
  const supports = (...args) => world.WebKitMediaKeys.isTypeSupported(...args);
  for (const keySystem of ['com.apple.fps.2_0', 'com.apple.fps.3_0', 'com.apple.fps.2_1',
                           'com.apple.fps.3_0,1', 'COM.APPLE.FPS.3_0']) {
    check(supports(keySystem) === true, `${keySystem} is supported`);
  }
  for (const keySystem of ['com.apple.fps.4_0',
                           'com.apple.fps.2_', 'com.apple.fps.2_0,', 'com.apple.fps.2_0 ',
                           'com.widevine.alpha', 'org.w3.clearkey',
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

// ---- Content types: what Media Source plays, as WebKit's legacy Media Source
// CDM answers (LegacyCDMPrivateAVFObjC::supportsKeySystemAndMimeType).
{
  const world = makeWorld();
  run(world, script);
  const supports = (type) => world.WebKitMediaKeys.isTypeSupported('com.apple.fps.3_0', type);
  const yes = [
    'video/mp4', 'audio/mp4', 'video/webm',
    'video/mp4; codecs="avc1.640028"',
    'VIDEO/MP4; CODECS="avc1.640028"',
    'video/mp4;codecs=avc1.640028',
    'video/mp4; codecs="hvc1.2.4.L153.B0"',
    'video/mp4; codecs="dvh1.05.06"',
    'audio/mp4; codecs="ec-3"',
    'video/mp4; codecs="av01.0.08M.08"',
    'video/webm; codecs="vp9"',
    'audio/mp4; codecs="opus"',
    'video/mp4; codecs="avc1.640028, mp4a.40.2"',
    'keyrelease', 'KeyRelease',
  ];
  for (const type of yes) check(supports(type) === true, `${type} is supported`);
  const no = [
    'audio/mp4; codecs="mp4a.6B"',          // Media Source doesn't play it
    'video/mp4; codecs="dvhe.08.07"',
    'video/mp4; codecs="avc1.640028,"',
    'video/mp4; codecs=""',
    'video/mp4; codecs="avc1.zzz"',
    'application/x-mpegurl',
    'application/vnd.apple.mpegurl',
    'video/mp2t',
    'mp4',
  ];
  for (const type of no) check(supports(type) === false, `${type} is not supported`);
  check(world.WebKitMediaKeys.isTypeSupported('com.apple.fps.4_0', 'video/mp4') === false,
        'a type never makes an unsupported key system supported');
  const keys = new world.WebKitMediaKeys('com.apple.fps.3_0');
  check(thrown(() => keys.createSession('KeyRelease', new Uint8Array([1])))?.name === 'NotSupportedError' &&
        thrown(() => keys.createSession('keyrelease', new Uint8Array([1]))) === null &&
        thrown(() => keys.createSession('video/webm', new Uint8Array([1]))) === null,
        'createSession: keyrelease case-sensitively, then what Media Source plays');
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
  for (const keySystem of ['com.widevine.alpha', 'org.w3.clearkey', 'com.apple.fps.4_0']) {
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
  // Disney+'s native client (dwp bundle), exactly: 1_0 is native HLS, which
  // Parc plays, so the keys are made as in Safari.
  check(run(world, `((J = WebKitMediaKeys) => { try { new J("com.apple.fps.1_0"); return "made"; }
      catch (e) { return e.name; } })()`) === 'made', "Disney+'s native client gets its keys");
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
  check(world.HTMLMediaElement.prototype.webkitSetMediaKeys.length === 1, 'operation length');
  check(!Object.prototype.hasOwnProperty.call(world.HTMLMediaElement.prototype, 'addEventListener'),
        'media elements keep EventTarget\'s own addEventListener, as in Safari');
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
  check(name(() => keys.createSession('video/mp2t', data)) === 'NotSupportedError', 'a type Media Source does not play');
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
// Blink's side of webkitneedkey (parc_webkit_need_key.h): the script's
// completion value is its hook; Blink calls it with the element, the init
// data and where it comes from, and queues the event it returns at the
// element (trusted, before `encrypted`). Here the event is dispatched at once.
const needKey = (hook, element, bytes, kind) => {
  const event = hook(element, new Uint8Array(bytes), kind);
  if (event) element.dispatchEvent(event);
  return event;
};
// WebKit's legacy skd init data, as Blink builds it (ParcWebKitSkdInitData).
const skdInitData = (uri) => {
  const data = Buffer.alloc(4 + uri.length * 2);
  data.writeUInt32LE(uri.length * 2, 0);
  data.write(uri, 4, 'utf16le');
  return data;
};

// ---- com.apple.fps.3_0 over cenc init data: the whole protocol.
{
  const world = makeWorld();
  const hook = run(world, script);
  const video = new world.HTMLMediaElement();
  const needs = [];
  video.addEventListener('webkitneedkey', (event) => needs.push(event));
  const initData = Buffer.concat([pssh('A'), pssh('B')]);
  needKey(hook, video, initData, 'media-source');
  check(needs.length === 1 && needs[0] instanceof world.WebKitMediaKeyNeededEvent &&
        text(needs[0].initData) === initData.toString('latin1'),
        'webkitneedkey carries the init data Blink gives');
  check(!needs[0].bubbles && !needs[0].cancelable, 'webkitneedkey neither bubbles nor cancels');

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
  check(access && access[1] === 'com.apple.fps' && access[2][0].initDataTypes.includes('sinf') &&
        access[2][0].persistentState === 'required' &&
        access[2][0].sessionTypes[0] === 'persistent-usage-record' &&
        access[2][1].sessionTypes[0] === 'temporary',
        'the keys are modern FairPlay keys, with storage first as WebKit\'s legacy sessions keep reports');
  check(world.log.some((entry) => entry[0] === 'createSession' && entry[1] === 'persistent-usage-record') ||
        !world.log.some((entry) => entry[0] === 'createSession'),
        'their sessions are persistent-usage-record ones');
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
  session.update(new Uint8Array(bytesOf('BAD-CKC')));
  await settle();
  check(events.filter((e) => e[0] === 'added').length === 3 && !events.some((e) => e[0] === 'error'),
        "a CKC AVFoundation rejects is still added, as WebKit's legacy key session has no failure callback");

  session.update(new Uint8Array(bytesOf('renew')));
  await settle();
  check(world.log.some((entry) => entry[0] === 'update' && entry[1] === 'renew'), 'renew reaches the CDM');
  check(events[events.length - 1][1] === 'SPC(CERT,renew:B)', 'the renewal SPC is a message');
  session.update(new Uint8Array(bytesOf('CKC-R')));
  await settle();
  check(JSON.parse(world.log.filter((e) => e[0] === 'update').pop()[1])[0].keyID === 'B',
        'the renewal answer goes to the renewed key');

  const before = events.length;
  const logged = world.log.length;
  session.close();
  session.update(new Uint8Array(bytesOf('late')));
  await settle();
  // WebKit's close() is releaseKeys(): the key session expires and its
  // expired-session report is looked for, so the CDM is asked for it after
  // the modern session closes.
  const after = world.log.slice(logged);
  check(after[0] && after[0][0] === 'close' &&
        !after.some((entry) => entry[0] === 'update') && events.length === before,
        'close() closes the modern session and later updates are dropped');
  check(after.some((entry) => entry[0] === 'generateRequest' &&
                              JSON.parse(entry[2]).legacySecureStop === 'session'),
        "then the closed keys' expired-session report is asked for");
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
// ---- Init data of no form Parc's CDM reads goes to AVFoundation unchanged
// (CDMSessionAVContentKeySession::update), as sinf JSON's legacyInitData.
{
  const world = makeWorld();
  run(world, script);
  const keys = new world.WebKitMediaKeys('com.apple.fps.3_0');
  const session = keys.createSession('video/mp4', new Uint8Array(bytesOf('opaque init data')));
  const events = [];
  session.addEventListener('webkitkeymessage', (event) => events.push(text(event.message)));
  session.addEventListener('webkitkeyerror', () => events.push('error:' + session.error.code));
  await settle();
  session.update(new Uint8Array(bytesOf('CERT')));
  await settle();
  const request = world.log.find((entry) => entry[0] === 'generateRequest');
  check(request && request[1] === 'sinf' &&
        Buffer.from(JSON.parse(request[2]).legacyInitData, 'base64').toString() === 'opaque init data' &&
        !events.some((event) => event.startsWith('error')),
        'unrecognized init data reaches the CDM as it is, with no key error');
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

// ---- com.apple.fps.2_0: the init data is the source buffer's sinf.
{
  const world = makeWorld();
  const hook = run(world, script);
  const sinfOf = (tag) => Buffer.from(JSON.stringify({sinf: [Buffer.from(tag).toString('base64')]}));
  const tagOf = (entry) => Buffer.from(JSON.parse(entry[2]).sinf[0], 'base64').toString();
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
  needKey(hook, video, sinfOf('C'), 'media-source');
  const second = keys.createSession('video/mp4', new Uint8Array(bytesOf('content-id')));
  second.addEventListener('webkitkeymessage', (event) => events.push(text(event.message)));
  await settle();
  second.update(new Uint8Array(bytesOf('CERT')));
  await settle();
  const request = world.log.find((entry) => entry[0] === 'generateRequest');
  const json = request && request[1] === 'sinf' && JSON.parse(request[2]);
  check(json && tagOf(request) === 'C' && Buffer.from(json.contentId, 'base64').toString() === 'content-id',
        "the request is the source buffer's sinf, the SPC named by the page's identifier");
  check(events.slice(-2).join() === 'certificate,SPC(CERT,sinf-key)', 'then the raw SPC');

  // A session keeps the first source buffer init data it is given: the
  // renderer's latest when it becomes the renderer's session, else the next.
  const third = keys.createSession('video/mp4', new Uint8Array(bytesOf('content-id')));
  needKey(hook, video, sinfOf('D'), 'media-source');
  await settle();
  third.update(new Uint8Array(bytesOf('CERT')));
  await settle();
  check(tagOf(world.log.filter((entry) => entry[0] === 'generateRequest').pop()) === 'C',
        'init data arriving later does not replace a session\'s first');

  // Keys attached after their session was created hand it the element's.
  const other = new world.HTMLMediaElement('other');
  needKey(hook, other, sinfOf('E'), 'media-source');
  const late = new world.WebKitMediaKeys('com.apple.fps.2_0');
  const lateSession = late.createSession('video/mp4', new Uint8Array(bytesOf('content-id')));
  await settle();
  other.webkitSetMediaKeys(late);
  lateSession.update(new Uint8Array(bytesOf('CERT')));
  await settle();
  check(tagOf(world.log.filter((entry) => entry[0] === 'generateRequest').pop()) === 'E',
        "attaching the keys gives their latest session the element's init data");

  // A new load: WebKit's new player has no renderer session or init data, so
  // the next title's session waits for its own init data.
  needKey(hook, video, [], 'load');
  const nextTitle = keys.createSession('video/mp4', new Uint8Array(bytesOf('content-id')));
  const nextEvents = [];
  nextTitle.addEventListener('webkitkeymessage', (event) => nextEvents.push(text(event.message)));
  nextTitle.addEventListener('webkitkeyerror', () => nextEvents.push('error:' + nextTitle.error.code));
  await settle();
  nextTitle.update(new Uint8Array(bytesOf('CERT')));
  await settle();
  check(nextEvents.join() === 'certificate,error:1',
        "after a new load the previous title's init data is gone: InvalidPlayerState");
  check(needKey(hook, video, [], 'load') === null, 'a load raises no event');
}

// ---- Secure stop (CDMSessionAVContentKeySession: keyrelease, acknowledged,
// the report on close).
{
  // keyrelease: the first report for the certificate, acknowledged away.
  const world = makeWorld({reports: ['REPORT-1', 'REPORT-2']});
  run(world, script);
  const keys = new world.WebKitMediaKeys('com.apple.fps.3_0');
  const release = keys.createSession('keyrelease', new Uint8Array(bytesOf('CERT')));
  const events = [];
  release.addEventListener('webkitkeymessage', (event) => events.push('message:' + text(event.message)));
  release.addEventListener('webkitkeyadded', () => events.push('added'));
  release.addEventListener('webkitkeyerror', () => events.push('error:' + release.error.code));
  await settle();
  const request = world.log.find((entry) => entry[0] === 'generateRequest');
  check(request && request[1] === 'sinf' && JSON.parse(request[2]).legacySecureStop === 'first' &&
        world.log.some((entry) => entry[0] === 'setServerCertificate' && entry[1] === 'CERT'),
        'keyrelease asks the CDM for the first report, with the certificate from its init data');
  check(events.join() === 'message:REPORT-1', 'the report is the message');
  release.update(new Uint8Array(bytesOf('acknowledged')));
  await settle();
  check(world.log.some((entry) => entry[0] === 'acknowledge' && entry[1] === 'REPORT-1') &&
        events.pop() === 'added', 'acknowledged removes it and the key counts as added');
  release.update(new Uint8Array(bytesOf('other')));
  await settle();
  // (The check above popped 'added'.) WebKit's KeyRelease mode returns
  // false for anything else, with no event.
  check(events.join() === 'message:REPORT-1', 'a keyrelease session takes nothing else');
}
for (const options of [{reports: []}, {privateWindow: true, reports: ['REPORT-1']}]) {
  // No report, or no storage (a private window): KeySystemNotSupported '!mor'.
  const world = makeWorld(options);
  run(world, script);
  const keys = new world.WebKitMediaKeys('com.apple.fps.3_0');
  const session = keys.createSession('keyrelease', new Uint8Array(bytesOf('CERT')));
  let error = null;
  session.onwebkitkeyerror = () => { error = session.error; };
  await settle();
  check(error && error.code === 2 && error.systemCode === 0x216d6f72,
        `keyrelease without ${options.privateWindow ? 'storage' : 'a report'}: CLIENT, '!mor'`);
  const other = keys.createSession('video/mp4', new Uint8Array(pssh('A')));
  await settle();
  other.update(new Uint8Array(bytesOf('acknowledged')));
  await settle();
  check(other.error && other.error.code === 1, 'acknowledged without a report: InvalidPlayerState');
}
{
  // The report a legacy session's key session leaves arrives after close().
  const world = makeWorld({sessionReport: 'SESSION-REPORT'});
  run(world, script);
  const keys = new world.WebKitMediaKeys('com.apple.fps.3_0');
  const session = keys.createSession('video/mp4', new Uint8Array(pssh('A')));
  const messages = [];
  session.addEventListener('webkitkeymessage', (event) => messages.push(text(event.message)));
  await settle();
  session.update(new Uint8Array(bytesOf('CERT')));
  await settle();
  session.update(new Uint8Array(bytesOf('CKC')));
  await settle();
  session.close();
  await settle();
  const stop = world.log.filter((entry) => entry[0] === 'generateRequest').pop();
  check(JSON.parse(stop[2]).legacySecureStop === 'session', 'closing asks for the key session\'s report');
  check(messages.pop() === 'SESSION-REPORT', 'which arrives as a message on the closed session');
  check(world.log[world.log.length - 1][0] === 'close', 'and the session that fetched it closes');
  session.update(new Uint8Array(bytesOf('acknowledged')));
  await settle();
  check(!world.log.some((entry) => entry[0] === 'acknowledge'),
        'a closed session ignores updates, as WebKit drops them');

  // Sessions sharing keys: only the last one's close asks.
  const two = makeWorld({sessionReport: 'R'});
  run(two, script);
  const shared = new two.WebKitMediaKeys('com.apple.fps.3_0');
  const a = shared.createSession('video/mp4', new Uint8Array(pssh('A')));
  const b = shared.createSession('video/mp4', new Uint8Array(pssh('B')));
  await settle();
  a.update(new Uint8Array(bytesOf('CERT')));
  b.update(new Uint8Array(bytesOf('CERT')));
  await settle();
  a.close();
  await settle();
  const asked = () => two.log.filter((entry) => entry[0] === 'generateRequest' &&
                                                entry[2].includes('legacySecureStop')).length;
  check(asked() === 0, 'another open session keeps the key session');
  b.close();
  await settle();
  check(asked() === 1, 'the last close asks');
}
{
  // A private window has no storage: temporary sessions, nothing on close.
  const world = makeWorld({privateWindow: true, sessionReport: 'R'});
  run(world, script);
  const keys = new world.WebKitMediaKeys('com.apple.fps.3_0');
  const session = keys.createSession('video/mp4', new Uint8Array(pssh('A')));
  await settle();
  session.update(new Uint8Array(bytesOf('CERT')));
  await settle();
  session.close();
  await settle();
  check(world.log.some((entry) => entry[0] === 'createSession' && entry[1] === 'temporary') &&
        !world.log.some((entry) => entry[0] === 'generateRequest' && entry[2].includes('legacySecureStop')),
        'temporary sessions and no report request without storage');
}

// ---- The key-needed hook: what Blink calls for each key a media element
// needs (HTMLMediaElement::mediaPlayerKeyNeeded).
{
  const world = makeWorld();
  const hook = run(world, script);
  check(typeof hook === 'function', "the script's completion value is the hook");
  check(!Object.getOwnPropertyNames(world).some((name) => world[name] === hook), 'no global holds the hook');
  const audio = new world.HTMLMediaElement('audio');
  const seen = [];
  audio.addEventListener('webkitneedkey', (event) => seen.push(event));
  const layout = skdInitData('skd://key-\u00e9\u{1F511}');
  const event = hook(audio, new Uint8Array(layout), 'skd');
  check(seen.length === 0, 'the hook makes the event; Blink queues it');
  check(event instanceof world.WebKitMediaKeyNeededEvent && event.type === 'webkitneedkey' &&
        !event.bubbles && !event.cancelable && !event.composed, 'a WebKitMediaKeyNeededEvent');
  check(Buffer.from(event.initData).equals(layout) && event.initData === event.initData,
        'initData is the bytes Blink passed, the same array each read');
  audio.dispatchEvent(event);
  check(seen.length === 1 && seen[0] === event, 'dispatched at the element');
  check(hook({}, new Uint8Array(1), 'skd') === null && hook(audio, [1], 'skd') === null &&
        hook(audio) === null, 'only a media element and a Uint8Array');
  // Changing the event's initData doesn't change what 2_N keys use, and
  // only Media Source init data reaches them.
  const video = new world.HTMLMediaElement();
  const keys = new world.WebKitMediaKeys('com.apple.fps.2_0');
  video.webkitSetMediaKeys(keys);
  const sinfK = Buffer.from(JSON.stringify({sinf: [Buffer.from('K').toString('base64')]}));
  needKey(hook, video, sinfK, 'media-source').initData.fill(0);
  needKey(hook, video, skdInitData('skd://x'), 'skd');
  needKey(hook, video, bytesOf('kid'), 'clearkey');
  const session = keys.createSession('video/mp4', new Uint8Array(bytesOf('id')));
  await settle();
  session.update(new Uint8Array(bytesOf('CERT')));
  await settle();
  const request = world.log.find((entry) => entry[0] === 'generateRequest');
  check(request && request[1] === 'sinf' &&
        Buffer.from(JSON.parse(request[2]).sinf[0], 'base64').toString() === 'K',
        'the keys keep their own copy of the Media Source init data');
  // The constructor's dictionary, as WebIDL converts it.
  run(world, 'Object.defineProperty(Object.prototype, "initData", {get() { throw new Error("read"); }, configurable: true});');
  check(thrown(() => new world.WebKitMediaKeyNeededEvent('webkitneedkey')) === null &&
        thrown(() => new world.WebKitMediaKeyNeededEvent('webkitneedkey', null)) === null &&
        thrown(() => hook(audio, new Uint8Array(1), 'media-source')) === null,
        'an absent dictionary is read from nothing');
  check(thrown(() => run(world, 'new WebKitMediaKeyNeededEvent("webkitneedkey", {})'))?.message === 'read',
        'a given dictionary is read');
  run(world, 'delete Object.prototype.initData;');
  check(thrown(() => new world.WebKitMediaKeyNeededEvent('x', 5))?.name === 'TypeError',
        'a dictionary must be an object');
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

// ---- `encrypted` events raise no webkitneedkey in script: Blink raises it,
// before `encrypted`, for every element in or out of the tree. A page's own
// encrypted event (Shaka's PatchedMediaKeysApple dispatches one from
// webkitneedkey) can't loop.
{
  const world = makeWorld();
  run(world, script);
  const video = new world.HTMLMediaElement();
  const needs = [];
  video.addEventListener('webkitneedkey', (event) => needs.push(event));
  encrypted(world, video, 'sinf', bytesOf('{"sinf":["AAAA"]}'));
  encrypted(world, video, 'skd', bytesOf('skd://a'));
  video.dispatchEvent(new world.MediaEncryptedEvent('encrypted',
      {initDataType: 'cenc', initData: new Uint8Array(pssh('Z')).buffer}));
  check(needs.length === 0, 'no webkitneedkey from encrypted events');
}

// ---- WebKit's AVFoundation player key systems (native HLS).
{
  const world = makeWorld();
  const hook = run(world, script);
  const supports = (...args) => world.WebKitMediaKeys.isTypeSupported(...args);
  check(supports('com.apple.fps') && supports('com.apple.fps.1_0') && supports('COM.APPLE.FPS.1_0'),
        'com.apple.fps and 1_0 (ignoring case)');
  check(supports('com.apple.fps.1_0', 'application/vnd.apple.mpegurl') &&
        supports('com.apple.fps', 'application/x-mpegURL') &&
        supports('com.apple.fps.1_0', 'video/mp4; codecs="avc1.640028,mp4a.40.2"') &&
        supports('com.apple.fps.1_0', 'video/mp2t') &&
        supports('com.apple.fps.1_0', 'audio/mp4; codecs="ec-3"'),
        'types AVFoundation decodes');
  check(!supports('com.apple.fps.1_0', 'video/webm') &&
        !supports('com.apple.fps.1_0', 'video/mp4; codecs="hev1.1.6.L93.B0"') &&
        !supports('com.apple.fps.1_0', 'video/mp4; codecs="vp09.00.10.08"') &&
        !supports('com.apple.fps.1_1') && !supports('com.apple.fps.2_0', 'application/vnd.apple.mpegurl'),
        'types and key systems it does not');
  check(avFoundationAsked.includes('video/mp2t') &&
        avFoundationAsked.includes('video/mp4; codecs="hev1.1.6.L93.B0"'),
        "each type is the browser's AVFoundation answer");

  const keys = new world.WebKitMediaKeys('com.apple.fps.1_0');
  const hlsInitData = (uri, contentId, certificate) => {
    const length = (n) => { const b = Buffer.alloc(4); b.writeUInt32LE(n); return b; };
    const u = Buffer.from(uri, 'utf16le');
    const c = Buffer.from(contentId, 'utf16le');
    const k = Buffer.from(certificate, 'latin1');
    return new Uint8Array(Buffer.concat([length(u.length), u, length(c.length), c, length(k.length), k]));
  };
  const loose = keys.createSession('application/vnd.apple.mpegurl', hlsInitData('skd://a', 'asset', 'CERT'));
  let looseEvents = 0;
  loose.addEventListener('webkitkeymessage', () => ++looseEvents);
  loose.addEventListener('webkitkeyerror', () => ++looseEvents);
  await settle();
  loose.update(new Uint8Array(bytesOf('CKC')));
  await settle();
  check(looseEvents === 0 && loose.sessionId === '', 'without an attached player the session does nothing');
  check(thrown(() => keys.createSession('video/webm', hlsInitData('skd://a', 'a', 'C')))?.name === 'NotSupportedError',
        'createSession checks the type against AVFoundation');

  const video = new world.HTMLMediaElement();
  video.webkitSetMediaKeys(keys);
  let needed = null;
  video.addEventListener('webkitneedkey', (event) => { needed = event.initData; });
  needKey(hook, video, skdInitData('skd://key1'), 'skd');
  check(needed && Buffer.from(needed.slice(4)).toString('utf16le') === 'skd://key1', 'webkitneedkey for the key URI');
  const session = keys.createSession('application/vnd.apple.mpegurl', hlsInitData('skd://key1', 'asset-9', 'CERT'));
  check(/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(session.sessionId),
        'an AVFoundation player session has a UUID');
  const events = [];
  session.addEventListener('webkitkeymessage', (event) => events.push(text(event.message)));
  session.addEventListener('webkitkeyadded', () => events.push('added'));
  session.addEventListener('webkitkeyerror', () => events.push('error:' + session.error.code));
  await settle();
  const request = world.log.find((entry) => entry[0] === 'generateRequest');
  const json = request && JSON.parse(request[2]);
  check(request && request[1] === 'skd' && json.skd === 'skd://key1' &&
        Buffer.from(json.contentId, 'base64').toString() === 'asset-9',
        'the skd request names the URI and the content ID');
  check(world.log.some((entry) => entry[0] === 'setServerCertificate' && entry[1] === 'CERT'),
        'with the certificate from the init data');
  check(events.join() === 'SPC(CERT,skd:skd://key1:asset-9)', 'the SPC is the first message');
  session.update(new Uint8Array(bytesOf('CKC')));
  await settle();
  check(world.log.filter((entry) => entry[0] === 'update').pop()[1] === 'CKC' && events.pop() === 'added',
        'the raw CKC answers the request and the key is added');
  session.update(new Uint8Array(bytesOf('renew')));
  await settle();
  check(world.log.filter((entry) => entry[0] === 'update').pop()[1] === 'CKC' && events.pop() === 'added' &&
        !events.some((event) => event.includes('renew')),
        'every update is an answer for the AVFoundation player, which never renews');
  const modern = world.log.filter((entry) => entry[0] === 'createSession').pop()[2];
  modern.setStatuses([['skd://key1', 'output-restricted']]);
  await settle();
  check(events.pop() === 'error:6' && session.error.systemCode === 0x48444350,
        "an obscured output is WebKit's HDCP key error (DOMAIN, systemCode 'HDCP')");
  modern.setStatuses([['skd://key1', 'output-restricted']]);
  modern.setStatuses([['skd://key1', 'usable']]);
  await settle();
  check(!events.some((event) => event.startsWith('error')), 'once per change into an obscured output');
  modern.setStatuses([['skd://key1', 'output-restricted']]);
  await settle();
  check(events.pop() === 'error:6', 'and again when the output is obscured again');

  const taken = keys.createSession('application/vnd.apple.mpegurl', hlsInitData('skd://key1', 'asset-9', 'CERT'));
  const unknown = keys.createSession('application/vnd.apple.mpegurl', hlsInitData('skd://other', 'x', 'CERT'));
  const broken = keys.createSession('application/vnd.apple.mpegurl', new Uint8Array([1, 2, 3]));
  await settle();
  check(taken.error?.code === 1 && unknown.error?.code === 1 && broken.error?.code === 1,
        'a key URI no request holds (or already taken), or unreadable init data: UNKNOWN');
}

// ---- Legacy clear key for HLS (LegacyCDMPrivateClearKey, CDMSessionClearKey).
{
  const world = makeWorld();
  run(world, script);
  const supports = (...args) => world.WebKitMediaKeys.isTypeSupported(...args);
  check(supports('org.w3c.clearkey') && supports('ORG.W3C.CLEARKEY', 'application/x-mpegURL'),
        'clear key, for application/x-mpegurl');
  check(!supports('org.w3c.clearkey', 'application/vnd.apple.mpegurl') &&
        !supports('org.w3c.clearkey', 'video/mp4') && !supports('org.w3.clearkey'),
        'only that type, only that name');
  const keys = new world.WebKitMediaKeys('org.w3c.clearkey');
  check(thrown(() => keys.createSession('video/mp4', new Uint8Array([1])))?.name === 'NotSupportedError',
        'createSession takes the HLS type only');
  const session = keys.createSession('application/x-mpegurl', new Uint8Array(bytesOf('key-1')));
  check(/^[0-9a-f-]{36}$/.test(session.sessionId), 'clear key sessions have a UUID');
  const events = [];
  session.addEventListener('webkitkeymessage', (event) => events.push('message:' + text(event.message)));
  session.addEventListener('webkitkeyadded', () => events.push('added'));
  session.addEventListener('webkitkeyerror', () => events.push('error:' + session.error.code));
  await settle();
  check(events.join() === 'message:key-1', 'the key ID comes back as the message');
  const jwk = (entry) => new Uint8Array(Buffer.from(JSON.stringify({keys: [entry]})));
  const good = {kty: 'oct', alg: 'A128KW', kid: 'key-1', k: 'AAECAwQFBgcICQoLDA0ODw'};
  session.update(jwk({...good, k: 'AAECAwQFBgcICQoLDA0OD-_'}));
  session.update(jwk({...good, alg: 'dir'}));
  session.update(new Uint8Array(Buffer.from('{"keys":[]}')));
  session.update(new Uint8Array([0xff, 0xfe]));
  session.update(jwk(good));
  await settle();
  check(events.slice(1).join() === 'error:2,error:2,error:2,error:2,added',
        'a JWK set with a usable A128KW oct key is added; anything else is a CLIENT error');
  const broken = keys.createSession('application/x-mpegurl', new Uint8Array([0xc3]));
  await settle();
  check(broken.error?.code === 2, 'init data that is not UTF-8 is a CLIENT error');
  session.close();
  session.update(jwk(good));
  await settle();
  check(events.length === 6, 'nothing after close()');
}

// ---- Legacy clear key on the player side: the player's clearkey://
// requests get the page's keys (MediaPlayerPrivateAVFoundationObjC::
// shouldWaitForLoadingOfResource checks the element's keys first, keyAdded
// answers the held ones).
{
  const world = makeWorld();
  const hook = run(world, script);
  const video = new world.HTMLMediaElement('v');
  const provided = [];
  const provide = (keyId, key) => provided.push(keyId + '=' + Buffer.from(key).toString('hex'));
  const needs = [];
  video.addEventListener('webkitneedkey', (event) => needs.push(text(event.initData)));
  const request = (keyId) => {
    const event = hook(video, new Uint8Array(Buffer.from(keyId, 'utf8')), 'clearkey', provide);
    if (event) video.dispatchEvent(event);
    return event;
  };
  check(request('key-1') instanceof world.WebKitMediaKeyNeededEvent && needs.join() === 'key-1',
        'a request no keys can answer raises webkitneedkey with the key ID');
  const keys = new world.WebKitMediaKeys('org.w3c.clearkey');
  video.webkitSetMediaKeys(keys);
  const session = keys.createSession('application/x-mpegurl', new Uint8Array(bytesOf('key-1')));
  await settle();
  const jwk = (kid) => new Uint8Array(Buffer.from(JSON.stringify(
      {keys: [{kty: 'oct', alg: 'A128KW', kid, k: 'AAECAwQFBgcICQoLDA0ODw'}]})));
  session.update(jwk('key-1'));
  await settle();
  const key = '000102030405060708090a0b0c0d0e0f';
  check(provided.join() === 'key-1=' + key, 'the held request gets the key once the session has it');
  check(request('key-1') === null && provided.length === 2 && needs.length === 1,
        'a request for a key the keys have is answered at once, with no webkitneedkey');
  check(request('k\u00e9y-2') instanceof world.WebKitMediaKeyNeededEvent, 'another key ID is held');
  session.update(jwk('key-3'));
  await settle();
  check(provided.length === 2, 'keys for other IDs leave it held');
  session.update(jwk('k\u00e9y-2'));
  await settle();
  check(provided.length === 3 && provided[2] === 'k\u00e9y-2=' + key, 'then its key comes (UTF-8 key IDs)');
  session.update(jwk('k\u00e9y-2'));
  await settle();
  check(provided.length === 3, 'an answered request is no longer held');
  // Another element's requests wait for that element's own keys.
  const other = new world.HTMLMediaElement('o');
  const otherProvided = [];
  const event = hook(other, new Uint8Array(bytesOf('key-1')), 'clearkey',
                     (keyId) => otherProvided.push(keyId));
  check(event instanceof world.WebKitMediaKeyNeededEvent && otherProvided.length === 0,
        "an element without keys doesn't take another element's");
}

// ---- WebKitMediaKeys::setMediaElement: keys follow the last element they
// were set on, and clearing them on an element that still holds them
// detaches them from wherever they are.
{
  const world = makeWorld();
  const hook = run(world, script);
  const a = new world.HTMLMediaElement('a');
  const b = new world.HTMLMediaElement('b');
  const keys = new world.WebKitMediaKeys('com.apple.fps.3_0');
  const attached = (element) => {
    const sets = world.log.filter((entry) => entry[0] === 'setMediaKeys' && entry[1] === element.name);
    return sets.length ? sets[sets.length - 1][2] : null;
  };
  a.webkitSetMediaKeys(keys);
  await settle();
  b.webkitSetMediaKeys(keys);
  await settle();
  const modern = world.log.find((entry) => entry[0] === 'setMediaKeys' && entry[2])[2];
  check(b.mediaKeys === null && a.webkitKeys === keys && b.webkitKeys === keys,
        'both elements report the keys; mediaKeys hides them');
  check(attached(a) === null && attached(b) === modern, 'the modern keys moved from a to b');
  a.webkitSetMediaKeys(keys);
  await settle();
  check(attached(b) === modern && attached(a) === null,
        'setting the keys a still holds again changes nothing');
  a.webkitSetMediaKeys(null);
  await settle();
  check(attached(b) === null && a.webkitKeys === null && b.webkitKeys === keys,
        "clearing a's keys detaches them from b, which still reports them (WebKit)");
  b.webkitSetMediaKeys(null);
  b.webkitSetMediaKeys(keys);
  await settle();
  check(attached(b) === modern, 'b takes them again');
  // A page that has since given b its own MediaKeys keeps them.
  const own = new world.MediaKeys();
  world.HTMLMediaElement.prototype.setMediaKeys.call(b, own);
  const c = new world.HTMLMediaElement('c');
  c.webkitSetMediaKeys(keys);
  await settle();
  check(attached(b) === own && attached(c) === modern, "the page's MediaKeys stay on b");
  // Quick moves end on the last element alone.
  const d = new world.HTMLMediaElement('d');
  const e = new world.HTMLMediaElement('e');
  d.webkitSetMediaKeys(keys);
  e.webkitSetMediaKeys(keys);
  await settle();
  check(attached(c) === null && attached(d) === null && attached(e) === modern,
        'the keys end on the last element only');
  check(hook(e, new Uint8Array(1), 'media-source') instanceof world.WebKitMediaKeyNeededEvent,
        'the hook still answers');
}

// ---- Two keys on one element: the new keys attach after the old ones
// leave, whatever their modern MediaKeys' state (Blink refuses overlapping
// setMediaKeys calls).
{
  const world = makeWorld();
  run(world, script);
  const video = new world.HTMLMediaElement('v');
  const k1 = new world.WebKitMediaKeys('com.apple.fps.3_0');
  const k2 = new world.WebKitMediaKeys('com.apple.fps.3_0');
  video.webkitSetMediaKeys(k1);
  await settle();
  // k2's modern MediaKeys exist before it is set (a session made them).
  const early = k2.createSession('video/mp4', new Uint8Array(pssh('A')));
  await settle();
  early.update(new Uint8Array(bytesOf('CERT')));
  await settle();
  video.webkitSetMediaKeys(k2);
  await settle();
  const sets = world.log.filter((entry) => entry[0].startsWith('setMediaKeys') && entry[1] === 'v');
  check(!sets.some((entry) => entry[0] === 'setMediaKeys refused'), 'no overlapping setMediaKeys');
  check(sets.length === 3 && sets[1][2] === null && sets[2][2] instanceof world.MediaKeys &&
        sets[2][2] !== sets[0][2] && video.mediaKeys === null,
        "k1's keys leave, then k2's arrive");
}

// ---- The hook reaches no page code: a page that patches WeakMap, Set or
// Object.prototype changes nothing it does.
{
  const world = makeWorld();
  const hook = run(world, script);
  const audio = new world.HTMLMediaElement('audio');
  // The model shares Node's TextDecoder; put its decode back afterwards.
  const decode = TextDecoder.prototype.decode;
  run(world, `
    globalThis.reached = 0;
    WeakMap.prototype.get = function() { ++reached; return undefined; };
    WeakMap.prototype.set = function() { ++reached; return this; };
    Set.prototype.add = function() { ++reached; return this; };
    globalThis.Set = function() { ++reached; };
    Map.prototype.set = function() { ++reached; return this; };
    Map.prototype.get = function() { ++reached; };
    globalThis.Map = function() { ++reached; };
    TextDecoder.prototype.decode = function() { ++reached; return ''; };
    Object.defineProperty(Array.prototype, '0', {set() { ++reached; }, configurable: true});
    Object.defineProperty(Object.prototype, 'initData', {set() { ++reached; }, configurable: true});`);
  const event = hook(audio, new Uint8Array(skdInitData('skd://a')), 'skd');
  const source = hook(audio, new Uint8Array(pssh('A')), 'media-source');
  const clear = hook(audio, new Uint8Array(bytesOf('kid')), 'clearkey', () => {});
  run(world, 'delete Object.prototype.initData; delete Array.prototype[0];');
  TextDecoder.prototype.decode = decode;
  check(world.reached === 0 && event instanceof world.WebKitMediaKeyNeededEvent &&
        source instanceof world.WebKitMediaKeyNeededEvent &&
        clear instanceof world.WebKitMediaKeyNeededEvent, 'no page code runs inside the hook');
}

// ---- Without modern EME (an insecure context) media elements still have
// webkitSetMediaKeys and webkitKeys, and webkitneedkey still comes.
{
  const base = makeWorld();
  const context = { MediaSource: base.MediaSource, DOMException, Event, EventTarget,
                    HTMLMediaElement: base.HTMLMediaElement, MediaError: base.MediaError };
  vm.createContext(context);
  const hook = run(context, script);
  const video = new context.HTMLMediaElement();
  check(typeof context.HTMLMediaElement.prototype.webkitSetMediaKeys === 'function' &&
        video.webkitKeys === null, 'the members exist');
  check(thrown(() => video.webkitSetMediaKeys(null)) === null && video.webkitKeys === null,
        'null can be set');
  check(typeof hook === 'function' && hook(video, new Uint8Array(1), 'media-source').type === 'webkitneedkey',
        'the hook is there');
}

// ---- An existing WebKitMediaKeys: nothing installed, no hook.
{
  const world = makeWorld();
  run(world, 'globalThis.WebKitMediaKeys = function Existing() {};');
  check(run(world, script) === undefined, 'no hook when WebKitMediaKeys exists');
}

console.log(`webkit media keys: ${checks} checks passed`);
