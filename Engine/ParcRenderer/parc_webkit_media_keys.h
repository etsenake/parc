// Copyright 2026 Parc contributors.
// Safari's legacy prefixed EME for documents presenting Safari's identity
// (docs/fairplay-identity.md, docs/fairplay-safari-surface.md). Run in the
// main world before the page's own scripts. It adds what WebKit's legacy
// Media Source CDM offers (LegacyCDMPrivateAVFObjC, key systems
// `com.apple.fps.2_N` and `com.apple.fps.3_N`, CDMSessionAVContentKeySession),
// built on Parc's FairPlay CDM through the modern EME natives it captures
// before any page script can replace them:
// - `WebKitMediaKeys(keySystem)`: InvalidAccessError for an empty key system,
//   NotSupportedError for one WebKit's MSE CDM doesn't serve (`com.apple.fps`
//   and `com.apple.fps.1_0` belong to WebKit's AVFoundation player: native
//   HLS, see Engine/ParcNative/fairplay_chromium/NATIVE_HLS.md). `keySystem`,
//   `createSession(type, initData)`, and `isTypeSupported(keySystem, type)`
//   answering for those key systems by what Media Source plays, and true for
//   `keyrelease`, as LegacyCDMPrivateAVFObjC does.
// - `WebKitMediaKeySession` with WebKit's protocol: the first
//   `webkitkeymessage` is the bytes "certificate"; `update(certificate)` sets
//   the FairPlay certificate and sends the SPC; `update(ckc)` answers it and
//   fires `webkitkeyadded`; `update("renew")` sends a renewal SPC;
//   `webkitkeyerror` carries a `WebKitMediaKeyError`. Version 3 takes the init
//   data from `createSession`; version 2 takes the SPC's content identifier
//   there and the init data from the protected media the keys are attached to.
//   `keyrelease` sessions find no expired-session reports (Parc keeps none) and
//   answer as WebKit does then.
// - Clear key (`org.w3c.clearkey`, LegacyCDMPrivateClearKey and
//   CDMSessionClearKey) for HLS once native HLS is on: the message is the key
//   ID, `update` takes a JWK set whose keys the attached player's
//   `clearkey://` requests get.
// - WebKit's AVFoundation player key systems, `com.apple.fps` and
//   `com.apple.fps.1_0` (CDMSessionAVFoundationObjC), once Parc's native HLS
//   route is on: the init data names the key URI of a request the attached
//   player holds, the content ID and the certificate; the SPC is the first
//   message; every update answers the request and fires `webkitkeyadded`.
// - `HTMLMediaElement.webkitSetMediaKeys`/`webkitKeys`, `webkitneedkey`
//   (`WebKitMediaKeyNeededEvent`) raised from each `encrypted` event with its
//   init data (an skd URI in WebKit's legacy layout), the event and error
//   interfaces, and `MediaError.MEDIA_ERR_ENCRYPTED`.
// A media element using legacy keys reports `mediaKeys` null, as in Safari.
// tests/FairPlayIdentity/webkit_media_keys.mjs runs this exact script.
// Installed at third_party/blink/renderer/bindings/core/v8/parc_webkit_media_keys.h.
#ifndef THIRD_PARTY_BLINK_RENDERER_BINDINGS_CORE_V8_PARC_WEBKIT_MEDIA_KEYS_H_
#define THIRD_PARTY_BLINK_RENDERER_BINDINGS_CORE_V8_PARC_WEBKIT_MEDIA_KEYS_H_

namespace blink {

inline constexpr char kParcWebKitMediaKeysScript[] = R"PARC_WKMK_JS(
(() => {
  'use strict';
  const g = globalThis;
  if ('WebKitMediaKeys' in g) {
    return;
  }
  const define = Object.defineProperty;
  const describe = Object.getOwnPropertyDescriptor;
  const apply = Reflect.apply;
  const getter = (proto, name) => {
    const descriptor = proto && describe(proto, name);
    return descriptor && descriptor.get;
  };
  // Everything the script relies on is taken now: players polyfill
  // MediaSource.isTypeSupported and Shaka replaces requestMediaKeySystemAccess,
  // MediaKeys and setMediaKeys with versions built on WebKitMediaKeys.
  const NativeMediaSource = g.MediaSource;
  const mediaSourceSupports = typeof NativeMediaSource === 'function' &&
      typeof NativeMediaSource.isTypeSupported === 'function' ?
      NativeMediaSource.isTypeSupported : null;
  const NativeEvent = g.Event;
  const NativeEventTarget = g.EventTarget;
  const NativeUint8Array = g.Uint8Array;
  const NativeArrayBuffer = g.ArrayBuffer;
  const NativeDataView = g.DataView;
  const NativeWeakMap = g.WeakMap;
  const NativeWeakSet = g.WeakSet;
  const typedArrayTag = getter(Object.getPrototypeOf(NativeUint8Array.prototype), Symbol.toStringTag);
  const promiseThen = Promise.prototype.then;
  const resolved = Promise.resolve();
  const jsonParse = JSON.parse;
  const jsonStringify = JSON.stringify;
  const nativeSetTimeout = g.setTimeout;
  const nativeAtob = g.atob;
  const nativeBtoa = g.btoa;
  const fromCharCode = String.fromCharCode;
  const NativeTextDecoder = g.TextDecoder;
  const NativeTextEncoder = g.TextEncoder;
  const cryptoObject = g.crypto;
  const randomUUID = cryptoObject && cryptoObject.randomUUID;
  const eventTargetPrototype = NativeEventTarget && NativeEventTarget.prototype;
  const addListener = eventTargetPrototype && eventTargetPrototype.addEventListener;
  const dispatch = eventTargetPrototype && eventTargetPrototype.dispatchEvent;
  const eventTarget = getter(NativeEvent && NativeEvent.prototype, 'target');
  const navigatorObject = g.navigator;
  const requestAccess = g.Navigator && g.Navigator.prototype.requestMediaKeySystemAccess;
  const createMediaKeys = g.MediaKeySystemAccess &&
      g.MediaKeySystemAccess.prototype.createMediaKeys;
  const keysPrototype = g.MediaKeys && g.MediaKeys.prototype;
  const createModernSession = keysPrototype && keysPrototype.createSession;
  const setServerCertificate = keysPrototype && keysPrototype.setServerCertificate;
  const sessionPrototype = g.MediaKeySession && g.MediaKeySession.prototype;
  const generateRequest = sessionPrototype && sessionPrototype.generateRequest;
  const updateModern = sessionPrototype && sessionPrototype.update;
  const closeModern = sessionPrototype && sessionPrototype.close;
  const messageEventPrototype = g.MediaKeyMessageEvent && g.MediaKeyMessageEvent.prototype;
  const messageOf = getter(messageEventPrototype, 'message');
  const messageTypeOf = getter(messageEventPrototype, 'messageType');
  const encryptedEventPrototype = g.MediaEncryptedEvent && g.MediaEncryptedEvent.prototype;
  const initDataTypeOf = getter(encryptedEventPrototype, 'initDataType');
  const initDataOf = getter(encryptedEventPrototype, 'initData');
  const NativeMediaElement = g.HTMLMediaElement;
  const mediaPrototype = NativeMediaElement && NativeMediaElement.prototype;
  const setMediaKeys = mediaPrototype && mediaPrototype.setMediaKeys;
  const mediaKeysDescriptor = mediaPrototype && describe(mediaPrototype, 'mediaKeys');
  const pausedOf = getter(mediaPrototype, 'paused');
  const canUseKeys = !!(navigatorObject && requestAccess && createMediaKeys &&
      createModernSession && setServerCertificate && generateRequest &&
      updateModern && closeModern && messageOf && messageTypeOf && setMediaKeys &&
      addListener && dispatch && NativeEvent && NativeEventTarget &&
      nativeSetTimeout && nativeAtob && nativeBtoa);

  // LegacyCDMPrivateAVFObjC::parseKeySystem.
  const MEDIA_SOURCE_KEY_SYSTEM = /^com\.apple\.fps\.([23])_\d+(?:,\d+)*$/i;
  // WebKit's AVFoundation player takes these
  // (MediaPlayerPrivateAVFoundationObjC::keySystemIsSupported, ignoring case).
  // Parc serves them through its native HLS route
  // (Engine/ParcNative/fairplay_chromium/NATIVE_HLS.md); the token below
  // turns true when parc::fairplay::kNativeHlsEnabled does.
  const NATIVE_HLS = /*PARC_NATIVE_HLS*/false;
  const HLS_KEY_SYSTEM = /^com\.apple\.fps(?:\.1_0)?$/i;
  // LegacyCDMPrivateClearKey: clear key, which the AVFoundation player takes
  // for HLS only.
  const CLEAR_KEY_SYSTEM = /^org\.w3c\.clearkey$/i;
  const CLEAR_KEY_TYPE = 'application/x-mpegurl';
  // AVURLAsset.audiovisualMIMETypes on macOS 27.2, the container list of
  // WebKit's AVAssetMIMETypeCache.
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
  // Codecs AVFoundation plays there: what its isPlayableExtendedMIMEType,
  // which WebKit asks for a type with codecs, answered on macOS 27.2
  // (case-sensitive; avc3, hev1 and dvhe answer no).
  const AVFOUNDATION_CODECS = [
    /^avc1(?:\.|$)/, /^hvc1(?:\.|$)/, /^dvh1(?:\.|$)/, /^av01(?:\.|$)/, /^mp4v(?:\.|$)/,
    /^mp4a\.(?:40(?:\.\d+)?|67)$/,
    /^(?:ac-3|ec-3|alac|fLaC|Opus|ulaw|alaw|wvtt)$/,
  ];
  const CODECS_PARAMETER = /;\s*codecs\s*=\s*(?:"([^"]*)"|([^;]*))/i;
  // The modern access the legacy keys are built on: every FairPlay codec, so
  // whatever the page plays is covered.
  const ACCESS_CONFIGURATIONS = [{
    initDataTypes: ['cenc', 'sinf', 'skd', 'keyids'],
    videoCapabilities: ['avc1.640028', 'hvc1.1.6.L93.B0', 'dvh1.05.06'].map(
        (codec) => ({contentType: 'video/mp4; codecs="' + codec + '"'})),
    audioCapabilities: ['mp4a.40.2', 'ec-3', 'ac-3'].map(
        (codec) => ({contentType: 'audio/mp4; codecs="' + codec + '"'})),
    distinctiveIdentifier: 'not-allowed',
    persistentState: 'optional',
    sessionTypes: ['temporary'],
  }];
  // WebKitMediaKeyError codes (LegacyCDM::CDMErrorCode) and the
  // MediaPlayer::MediaKeyException values WebKit reports through them.
  const UNKNOWN = 1;
  const CLIENT = 2;
  const DOMAIN = 6;
  const INVALID_PLAYER_STATE = 1;
  const KEY_SYSTEM_NOT_SUPPORTED = 2;
  const NO_EXPIRED_SESSIONS = 0x216d6f72;  // '!mor'

  const keysState = new NativeWeakMap();
  const sessionState = new NativeWeakMap();
  const errorState = new NativeWeakMap();
  const eventState = new NativeWeakMap();
  const handlers = new NativeWeakMap();
  const elementKeys = new NativeWeakMap();
  const elementInitData = new NativeWeakMap();
  const forwarding = new NativeWeakSet();
  const raisedFrom = new NativeWeakSet();
  const elementKeyRequests = new NativeWeakMap();
  const legacyModernKeys = new NativeWeakSet();
  let constructing = false;

  // WebIDL conversions.
  const toDOMString = (value) => `${value}`;
  function required(count, length, what) {
    if (length < count) {
      throw new TypeError('Failed to ' + what + ': ' + count + ' argument' +
          (count > 1 ? 's' : '') + ' required, but only ' + length + ' present.');
    }
  }
  function isUint8Array(value) {
    try {
      return apply(typedArrayTag, value, []) === 'Uint8Array';
    } catch (error) {
      return false;
    }
  }
  function toUint8Array(value, what, index) {
    if (!isUint8Array(value)) {
      throw new TypeError('Failed to ' + what + ': parameter ' + index +
          " is not of type 'Uint8Array'.");
    }
    return value;
  }
  const copy = (bytes) => new NativeUint8Array(bytes);
  function illegal() {
    throw new TypeError('Illegal constructor');
  }
  function stateOf(map, object) {
    const state = map.get(object);
    if (!state) {
      throw new TypeError('Illegal invocation');
    }
    return state;
  }
  function brandMedia(element) {
    apply(pausedOf, element, []);
  }
  const then = (promise, fulfilled, rejected) =>
      apply(promiseThen, promise, [fulfilled, rejected]);
  const later = (task) => apply(nativeSetTimeout, g, [task, 0]);

  function ascii(text) {
    const bytes = new NativeUint8Array(text.length);
    for (let i = 0; i < text.length; ++i) {
      bytes[i] = text.charCodeAt(i);
    }
    return bytes;
  }
  function equalsAscii(bytes, text) {
    if (bytes.length !== text.length) {
      return false;
    }
    for (let i = 0; i < text.length; ++i) {
      if (bytes[i] !== text.charCodeAt(i)) {
        return false;
      }
    }
    return true;
  }
  function latin1(bytes) {
    let text = '';
    for (let i = 0; i < bytes.length; i += 0x2000) {
      text += apply(fromCharCode, null, bytes.subarray(i, i + 0x2000));
    }
    return text;
  }
  const toBase64 = (bytes) => apply(nativeBtoa, g, [latin1(bytes)]);
  function fromBase64(text) {
    const binary = apply(nativeAtob, g, [text]);
    const bytes = new NativeUint8Array(binary.length);
    for (let i = 0; i < binary.length; ++i) {
      bytes[i] = binary.charCodeAt(i);
    }
    return bytes;
  }
  function parseJson(bytes) {
    try {
      return apply(jsonParse, JSON, [latin1(bytes)]);
    } catch (error) {
      return undefined;
    }
  }

  // The init data type Parc's CDM takes for legacy init data: the sinf JSON
  // WebKit's Media Source gives, concatenated pssh boxes (Chromium's MP4
  // parser), or key IDs.
  function initDataTypeOfBytes(bytes) {
    let first = 0;
    while (first < bytes.length && (bytes[first] === 0x20 || bytes[first] === 0x0a ||
                                    bytes[first] === 0x0d || bytes[first] === 0x09)) {
      ++first;
    }
    if (bytes[first] === 0x7b) {
      const json = parseJson(bytes);
      if (json && typeof json === 'object') {
        if (Array.isArray(json.sinf) && json.sinf.length) {
          return 'sinf';
        }
        if (Array.isArray(json.kids) && json.kids.length) {
          return 'keyids';
        }
      }
      return null;
    }
    let offset = 0;
    while (offset + 8 <= bytes.length) {
      const size = ((bytes[offset] << 24) | (bytes[offset + 1] << 16) |
                    (bytes[offset + 2] << 8) | bytes[offset + 3]) >>> 0;
      if (size < 8 || offset + size > bytes.length ||
          bytes[offset + 4] !== 0x70 || bytes[offset + 5] !== 0x73 ||
          bytes[offset + 6] !== 0x73 || bytes[offset + 7] !== 0x68) {
        return null;
      }
      offset += size;
    }
    return offset && offset === bytes.length ? 'cenc' : null;
  }

  // WebKit's legacy skd init data: a 4-byte little-endian length, then the
  // URI as UTF-16 (MediaPlayerPrivateAVFoundationObjC::shouldWaitForLoadingOfResource).
  function legacySkdInitData(utf8) {
    const uri = NativeTextDecoder ? new NativeTextDecoder().decode(utf8) : latin1(utf8);
    const buffer = new NativeArrayBuffer(4 + uri.length * 2);
    const view = new NativeDataView(buffer);
    view.setUint32(0, uri.length * 2, true);
    for (let i = 0; i < uri.length; ++i) {
      view.setUint16(4 + i * 2, uri.charCodeAt(i), true);
    }
    return new NativeUint8Array(buffer);
  }

  // MIMETypeCache::canDecodeType for WebKit's AVFoundation player: a listed
  // container, and with codecs, ones AVFoundation plays.
  function avFoundationDecodes(type) {
    const container = type.split(';')[0].trim().toLowerCase();
    if (!AVFOUNDATION_TYPES.has(container)) {
      return false;
    }
    const parameter = CODECS_PARAMETER.exec(type);
    if (!parameter) {
      return true;
    }
    const list = parameter[1] !== undefined ? parameter[1] : parameter[2];
    const codecs = list.split(',').map((codec) => codec.trim()).filter((codec) => codec);
    return codecs.every((codec) => AVFOUNDATION_CODECS.some((pattern) => pattern.test(codec)));
  }

  function utf16(bytes, offset, length) {
    let text = '';
    for (let i = 0; i + 1 < length; i += 2) {
      text += fromCharCode(bytes[offset + i] | (bytes[offset + i + 1] << 8));
    }
    return text;
  }
  // MediaPlayerPrivateAVFoundation::extractKeyURIKeyIDAndCertificateFromInitData:
  // [4 bytes LE: URI length][URI, UTF-16][4 bytes LE: content ID length]
  // [content ID, UTF-16][4 bytes LE: certificate length][certificate]. The URI
  // is read through a Uint16Array of its length in elements, so that many
  // code units must fit too.
  function parseHlsInitData(bytes) {
    const view = new NativeDataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
    let offset = 0;
    const length = () => {
      if (offset + 4 > bytes.length) {
        return -1;
      }
      const value = view.getUint32(offset, true);
      offset += 4;
      return value;
    };
    const uriLength = length();
    if (uriLength < 0 || offset + uriLength > bytes.length ||
        offset + uriLength * 2 > bytes.length) {
      return null;
    }
    const uri = utf16(bytes, offset, uriLength);
    offset += uriLength;
    const idLength = length();
    if (idLength < 0 || offset + idLength > bytes.length) {
      return null;
    }
    const contentId = utf16(bytes, offset, idLength);
    offset += idLength;
    const certificateLength = length();
    if (certificateLength < 0 || offset + certificateLength > bytes.length) {
      return null;
    }
    return {uri, contentId, certificate: bytes.slice(offset, offset + certificateLength)};
  }
  const utf8 = (text) => NativeTextEncoder ? new NativeTextEncoder().encode(text) : ascii(text);
  function uuid() {
    if (randomUUID) {
      return apply(randomUUID, cryptoObject, []);
    }
    const bytes = new NativeUint8Array(16);
    cryptoObject.getRandomValues(bytes);
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    const hex = Array.from(bytes, (byte) => (byte + 0x100).toString(16).slice(1)).join('');
    return hex.slice(0, 8) + '-' + hex.slice(8, 12) + '-' + hex.slice(12, 16) + '-' +
        hex.slice(16, 20) + '-' + hex.slice(20);
  }

  // Which WebKit legacy CDM serves a key system: its Media Source CDM, or
  // its AVFoundation player (native HLS).
  function keySystemKind(keySystem) {
    if (NATIVE_HLS && CLEAR_KEY_SYSTEM.test(keySystem)) {
      return 'clearkey';
    }
    if (MEDIA_SOURCE_KEY_SYSTEM.test(keySystem)) {
      return 'mse';
    }
    return NATIVE_HLS && HLS_KEY_SYSTEM.test(keySystem) ? 'hls' : null;
  }

  function legacyVersion(keySystem) {
    const match = MEDIA_SOURCE_KEY_SYSTEM.exec(keySystem);
    return match ? +match[1] : 0;
  }

  // MediaPlayerPrivateMediaSourceAVFObjC::supportsTypeAndCodecs: what Media
  // Source plays (Chromium's answer, taken before any page script).
  const mediaSourcePlays = (type) => !!mediaSourceSupports &&
      apply(mediaSourceSupports, NativeMediaSource, [type]) === true;
  const asciiLower = (text) => text.replace(/[A-Z]+/g, (letters) => letters.toLowerCase());

  // LegacyCDMPrivateAVFObjC::supportsMIMEType, and for the AVFoundation
  // player MediaPlayer::supportsKeySystem.
  const sessionTypeSupported = (kind, type) =>
      kind === 'hls' ? avFoundationDecodes(type) :
      kind === 'clearkey' ? asciiLower(type) === CLEAR_KEY_TYPE :
      type === 'keyrelease' || mediaSourcePlays(type);

  // Event handler IDL attributes.
  function handlerOf(target, type) {
    const map = handlers.get(target);
    const entry = map && map.get(type);
    return entry ? entry.handler : null;
  }
  function setHandler(target, type, value) {
    let map = handlers.get(target);
    if (!map) {
      map = new Map();
      handlers.set(target, map);
    }
    let entry = map.get(type);
    if (!entry) {
      entry = {handler: null};
      entry.listener = function(event) {
        const handler = entry.handler;
        if (typeof handler === 'function' && apply(handler, this, [event]) === false) {
          event.preventDefault();
        }
      };
      map.set(type, entry);
      apply(addListener, target, [type, entry.listener]);
    }
    entry.handler = typeof value === 'function' ||
        (typeof value === 'object' && value !== null) ? value : null;
  }

  class WebKitMediaKeyError {
    constructor() {
      if (!constructing) {
        illegal();
      }
    }
    get code() { return stateOf(errorState, this).code; }
    get systemCode() { return stateOf(errorState, this).systemCode; }
  }
  function makeError(code, systemCode) {
    constructing = true;
    let error;
    try {
      error = new WebKitMediaKeyError();
    } finally {
      constructing = false;
    }
    errorState.set(error, {code, systemCode: systemCode >>> 0});
    return error;
  }
  const ERROR_CODES = [['MEDIA_KEYERR_UNKNOWN', 1], ['MEDIA_KEYERR_CLIENT', 2],
                       ['MEDIA_KEYERR_SERVICE', 3], ['MEDIA_KEYERR_OUTPUT', 4],
                       ['MEDIA_KEYERR_HARDWARECHANGE', 5], ['MEDIA_KEYERR_DOMAIN', 6]];

  function readDictionary(init, what) {
    if (init === undefined || init === null) {
      return {};
    }
    if (typeof init !== 'object' && typeof init !== 'function') {
      throw new TypeError('Failed to construct ' + what +
          ": The provided value is not of type '" + what + "Init'.");
    }
    return init;
  }
  function nullableUint8Array(value, what, member) {
    if (value === undefined || value === null) {
      return null;
    }
    if (!isUint8Array(value)) {
      throw new TypeError('Failed to construct ' + what + ": Failed to read the '" +
          member + "' property from '" + what + "Init': The provided value is not of type 'Uint8Array'.");
    }
    return value;
  }

  // Every window has Event and EventTarget; the bases only keep the script
  // loadable without them.
  const EventBase = NativeEvent || class {};
  const EventTargetBase = NativeEventTarget || class {};

  class WebKitMediaKeyMessageEvent extends EventBase {
    constructor(type, eventInitDict = undefined) {
      required(1, arguments.length, "construct 'WebKitMediaKeyMessageEvent'");
      const init = readDictionary(eventInitDict, 'WebKitMediaKeyMessageEvent');
      super(type, init);
      const destinationURL = init.destinationURL === undefined ? '' : toDOMString(init.destinationURL);
      const message = nullableUint8Array(init.message, 'WebKitMediaKeyMessageEvent', 'message');
      eventState.set(this, {message, destinationURL});
    }
    get message() { return stateOf(eventState, this).message; }
    get destinationURL() { return stateOf(eventState, this).destinationURL; }
  }

  class WebKitMediaKeyNeededEvent extends EventBase {
    constructor(type, eventInitDict = undefined) {
      required(1, arguments.length, "construct 'WebKitMediaKeyNeededEvent'");
      const init = readDictionary(eventInitDict, 'WebKitMediaKeyNeededEvent');
      super(type, init);
      eventState.set(this, {
        initData: nullableUint8Array(init.initData, 'WebKitMediaKeyNeededEvent', 'initData'),
      });
    }
    get initData() { return stateOf(eventState, this).initData; }
  }

  function fire(target, event) {
    apply(dispatch, target, [event]);
  }
  const plainEvent = (type) => new NativeEvent(type, {bubbles: false, cancelable: false});

  class WebKitMediaKeySession extends EventTargetBase {
    constructor() {
      if (!constructing) {
        illegal();
      }
      super();
    }
    get error() { return stateOf(sessionState, this).error; }
    get keySystem() { return stateOf(sessionState, this).keys.keySystem; }
    get sessionId() { return stateOf(sessionState, this).sessionId; }
    update(key) {
      const session = stateOf(sessionState, this);
      const what = "execute 'update' on 'WebKitMediaKeySession'";
      required(1, arguments.length, what);
      toUint8Array(key, what, 1);
      if (key.length === 0) {
        throw new DOMException('', 'InvalidAccessError');
      }
      const bytes = copy(key);
      later(() => {
        session.chain = then(session.chain, () => processKey(session, bytes));
      });
    }
    close() {
      const session = stateOf(sessionState, this);
      if (!session.open) {
        return;
      }
      session.open = false;
      if (session.cache) {
        session.cache.clear();
        const index = session.keys.sessions.indexOf(session);
        if (index >= 0) {
          session.keys.sessions.splice(index, 1);
        }
      }
      if (session.modern) {
        then(apply(closeModern, session.modern, []), undefined, () => {});
      }
    }
    get onwebkitkeyadded() { return handlerOf(this, 'webkitkeyadded'); }
    set onwebkitkeyadded(value) { setHandler(this, 'webkitkeyadded', value); }
    get onwebkitkeyerror() { return handlerOf(this, 'webkitkeyerror'); }
    set onwebkitkeyerror(value) { setHandler(this, 'webkitkeyerror', value); }
    get onwebkitkeymessage() { return handlerOf(this, 'webkitkeymessage'); }
    set onwebkitkeymessage(value) { setHandler(this, 'webkitkeymessage', value); }
  }

  function sendMessage(session, bytes) {
    if (session.open) {
      fire(session.object, new WebKitMediaKeyMessageEvent('webkitkeymessage', {message: bytes}));
    }
  }
  function sendError(session, code, systemCode) {
    if (session.open) {
      session.error = makeError(code, systemCode);
      fire(session.object, plainEvent('webkitkeyerror'));
    }
  }
  // Blink adds a CDM's system code to the rejection message as " (code)".
  function systemCodeOf(error) {
    const match = /\((\d+)\)\s*$/.exec(error && typeof error.message === 'string' ? error.message : '');
    return match ? +match[1] : 0;
  }

  // The modern MediaKeys of one WebKitMediaKeys, made once.
  function modernKeysOf(keys) {
    if (!keys.modern) {
      keys.modern = then(
          apply(requestAccess, navigatorObject, ['com.apple.fps', ACCESS_CONFIGURATIONS]),
          (access) => {
            const modern = apply(createMediaKeys, access, []);
            return then(modern, (mediaKeys) => {
              legacyModernKeys.add(mediaKeys);
              return mediaKeys;
            });
          });
    }
    return keys.modern;
  }

  // Runs |task| after the keys' earlier certificate and request, so each
  // session's SPC uses its own certificate.
  function serialized(keys, task) {
    const run = then(keys.requests, task);
    keys.requests = then(run, undefined, () => {});
    return run;
  }

  function onModernMessage(session, event) {
    const type = apply(messageTypeOf, event, []);
    if (type !== 'license-request' && type !== 'license-renewal') {
      return;
    }
    const bytes = new NativeUint8Array(apply(messageOf, event, []));
    if (!session.json) {
      session.pending.push(null);
      sendMessage(session, bytes);
      return;
    }
    // cenc and keyids sessions: one {keyID, payload} entry per key.
    const entries = parseJson(bytes);
    if (!Array.isArray(entries)) {
      return;
    }
    for (const entry of entries) {
      if (entry && typeof entry.keyID === 'string' && typeof entry.payload === 'string') {
        session.pending.push(entry.keyID);
        session.lastKeyId = entry.keyID;
        sendMessage(session, fromBase64(entry.payload));
      }
    }
  }

  // CDMSessionAVContentKeySession::update: the first update after the
  // certificate message makes the SPC.
  function startRequest(session) {
    const keys = session.keys;
    const type = initDataTypeOfBytes(session.initData);
    if (!type) {
      sendError(session, DOMAIN, 0);
      return undefined;
    }
    session.json = type !== 'sinf';
    // Version 2 names the SPC by the page's identifier: Parc's CDM takes it
    // with the media's init data as a keyids extension (fairplay_init_data.mm).
    const requestType = session.keys.version === 2 ? 'keyids' : type;
    const contentId = session.keys.version === 2 ? toBase64(session.identifier) : '';
    const requestData = !contentId ? copy(session.initData) :
        ascii(apply(jsonStringify, JSON, [type === 'keyids' ?
            {kids: parseJson(session.initData).kids, contentId} :
            {initDataType: type, initData: toBase64(session.initData), contentId}]));
    const failed = (error) => sendError(session, DOMAIN, systemCodeOf(error));
    return then(modernKeysOf(keys), (mediaKeys) => serialized(keys, () => {
      if (!session.open) {
        return undefined;
      }
      return then(apply(setServerCertificate, mediaKeys, [copy(session.certificate)]), () => {
        if (!session.open) {
          return undefined;
        }
        const modern = apply(createModernSession, mediaKeys, ['temporary']);
        session.modern = modern;
        apply(addListener, modern, ['message', (event) => onModernMessage(session, event)]);
        if (!session.open) {
          then(apply(closeModern, modern, []), undefined, () => {});
          return undefined;
        }
        return then(apply(generateRequest, modern, [requestType, requestData]),
                    undefined, failed);
      }, failed);
    }), failed);
  }

  function answer(session, ckc) {
    let response = ckc;
    if (session.json) {
      const keyId = session.pending.length ? session.pending.shift() : session.lastKeyId;
      response = ascii(apply(jsonStringify, JSON, [[{keyID: keyId, payload: toBase64(ckc)}]]));
    } else if (session.pending.length) {
      session.pending.shift();
    }
    return then(apply(updateModern, session.modern, [response]), () => {
      if (session.open) {
        fire(session.object, plainEvent('webkitkeyadded'));
      }
    }, (error) => sendError(session, UNKNOWN, systemCodeOf(error)));
  }

  // CDMSessionAVFoundationObjC::generateKeyRequest: the init data names the
  // key URI of a request the attached player is holding, the content ID and
  // the certificate; the SPC is the first message.
  function generateHlsRequest(session, initData) {
    const parsed = parseHlsInitData(initData);
    const requests = parsed && elementKeyRequests.get(session.element);
    if (!requests || !requests.delete(parsed.uri)) {
      sendError(session, UNKNOWN, 0);
      return;
    }
    const keys = session.keys;
    const failed = (error) => sendError(session, DOMAIN, systemCodeOf(error));
    // Parc's CDM names the request by the URI and the SPC by the content ID
    // (WebKit: contentIdentifier = the content ID as UTF-8).
    const request = ascii(apply(jsonStringify, JSON, [{
      skd: parsed.uri, contentId: toBase64(utf8(parsed.contentId)),
    }]));
    session.chain = then(session.chain, () => then(modernKeysOf(keys), (mediaKeys) => serialized(keys, () => {
      if (!session.open) {
        return undefined;
      }
      return then(apply(setServerCertificate, mediaKeys, [parsed.certificate]), () => {
        if (!session.open) {
          return undefined;
        }
        const modern = apply(createModernSession, mediaKeys, ['temporary']);
        session.modern = modern;
        apply(addListener, modern, ['message', (event) => onModernMessage(session, event)]);
        return then(apply(generateRequest, modern, ['skd', request]), undefined, failed);
      }, failed);
    }), failed));
  }

  // CDMSessionAVFoundationObjC::update: every key is the answer to the held
  // request, and WebKit reports it added.
  function processHlsKey(session, key) {
    const added = () => {
      if (session.open) {
        fire(session.object, plainEvent('webkitkeyadded'));
      }
    };
    if (!session.modern) {
      added();
      return undefined;
    }
    return then(apply(updateModern, session.modern, [key]), added, added);
  }

  // WTF::base64Decode without options: the standard alphabet, padding
  // optional, no whitespace.
  function decodeBase64Strict(text) {
    const body = text.replace(/={1,2}$/, '');
    if (!/^[A-Za-z0-9+/]*$/.test(body) || body.length % 4 === 1) {
      return null;
    }
    try {
      return fromBase64(body + '=='.slice(0, (4 - body.length % 4) % 4));
    } catch (error) {
      return null;
    }
  }
  function decodeUtf8Strict(bytes) {
    try {
      return new NativeTextDecoder('utf-8', {fatal: true}).decode(bytes);
    } catch (error) {
      return null;
    }
  }

  // CDMSessionClearKey::update: a JWK set; each A128KW "oct" key with a kid
  // and a base64 k is kept for the player's clearkey:// requests.
  function processClearKey(session, key) {
    const text = decodeUtf8Strict(key);
    let json;
    try {
      json = text ? apply(jsonParse, JSON, [text]) : undefined;
    } catch (error) {
      json = undefined;
    }
    const list = json && typeof json === 'object' && !Array.isArray(json) ? json.keys : undefined;
    let found = false;
    if (Array.isArray(list)) {
      for (const entry of list) {
        if (!entry || typeof entry !== 'object' || Array.isArray(entry)) {
          continue;
        }
        const string = (name) => typeof entry[name] === 'string' ? entry[name] : '';
        const keyId = string('kid');
        const value = string('k');
        const bytes = value ? decodeBase64Strict(value) : null;
        if (asciiLower(string('alg')) !== 'a128kw' || asciiLower(string('kty')) !== 'oct' ||
            !keyId || !bytes || !bytes.length) {
          continue;
        }
        session.cache.set(keyId, bytes);
        found = true;
      }
    }
    if (!found) {
      sendError(session, CLIENT, 0);
      return;
    }
    fire(session.object, plainEvent('webkitkeyadded'));
    keysAdded(session.keys);
  }

  // WebKitMediaKeys::cachedKeyForKeyId: the first open session holding it
  // (keys.sessions lists a keys object's open clear key sessions).
  function cachedKeyFor(keys, keyId) {
    for (const session of keys.sessions) {
      const bytes = session.open && session.cache && session.cache.get(keyId);
      if (bytes) {
        return copy(bytes);
      }
    }
    return null;
  }

  function processKey(session, key) {
    if (!session.open || session.inert) {
      return undefined;
    }
    if (session.keys.kind === 'hls') {
      return processHlsKey(session, key);
    }
    if (session.keys.kind === 'clearkey') {
      processClearKey(session, key);
      return undefined;
    }
    if (equalsAscii(key, 'acknowledged')) {
      // A secure-stop acknowledgement with no expired session in hand.
      sendError(session, INVALID_PLAYER_STATE, 0);
      return undefined;
    }
    const renew = equalsAscii(key, 'renew');
    const makeRequest = !session.certificate || renew;
    if (!session.certificate) {
      session.certificate = key;
    }
    if (session.keyRelease) {
      return undefined;
    }
    if (session.keys.version === 2) {
      // com.apple.fps.2_0: the init data comes from the protected media the
      // keys are attached to.
      const element = session.keys.element;
      const initData = element && elementInitData.get(element);
      if (!initData) {
        sendError(session, INVALID_PLAYER_STATE, 0);
        return undefined;
      }
      if (!session.modern) {
        session.initData = initData;
      }
    }
    if (makeRequest && !session.modern) {
      return startRequest(session);
    }
    if (!session.modern) {
      // An answer before the SPC exists.
      sendError(session, INVALID_PLAYER_STATE, 0);
      return undefined;
    }
    if (renew) {
      return then(apply(updateModern, session.modern, [ascii('renew')]), undefined,
                  (error) => sendError(session, DOMAIN, systemCodeOf(error)));
    }
    return answer(session, key);
  }

  // WebKitMediaKeySession::generateKeyRequest, run as a task after
  // createSession.
  function generateKeyRequest(session, type, initData) {
    if (!session.open || session.inert) {
      return;
    }
    if (session.keys.kind === 'hls') {
      generateHlsRequest(session, initData);
      return;
    }
    if (session.keys.kind === 'clearkey') {
      // CDMSessionClearKey::generateKeyRequest: init data that is UTF-8 (the
      // key ID) comes back as the message.
      if (decodeUtf8Strict(initData) === null) {
        sendError(session, CLIENT, 0);
      } else {
        sendMessage(session, copy(initData));
      }
      return;
    }
    if (asciiLower(type) === 'keyrelease') {
      // CDMSessionAVContentKeySession::generateKeyReleaseMessage without any
      // expired-session report.
      session.keyRelease = true;
      session.certificate = initData;
      sendError(session, KEY_SYSTEM_NOT_SUPPORTED, NO_EXPIRED_SESSIONS);
      return;
    }
    if (session.keys.version === 2) {
      session.identifier = initData;
    } else {
      session.initData = initData;
    }
    sendMessage(session, ascii('certificate'));
  }

  class WebKitMediaKeys {
    constructor(keySystem) {
      required(1, arguments.length, "construct 'WebKitMediaKeys'");
      const system = toDOMString(keySystem);
      if (system === '') {
        throw new DOMException('', 'InvalidAccessError');
      }
      // FairPlay keys are built on modern EME, which an insecure context
      // lacks; clear key keys are the script's own.
      const kind = keySystemKind(system);
      if (!kind || (kind !== 'clearkey' && !canUseKeys)) {
        throw new DOMException('', 'NotSupportedError');
      }
      keysState.set(this, {
        object: this, keySystem: system, kind, version: legacyVersion(system),
        element: null, modern: null, requests: resolved, attaching: resolved, sessions: [],
      });
    }
    get keySystem() { return stateOf(keysState, this).keySystem; }
    createSession(type, initData) {
      const keys = stateOf(keysState, this);
      const what = "execute 'createSession' on 'WebKitMediaKeys'";
      required(2, arguments.length, what);
      const mime = toDOMString(type);
      toUint8Array(initData, what, 2);
      if (mime === '' || initData.length === 0) {
        throw new DOMException('', 'InvalidAccessError');
      }
      if (!sessionTypeSupported(keys.kind, mime)) {
        throw new DOMException('', 'NotSupportedError');
      }
      constructing = true;
      let object;
      try {
        object = new WebKitMediaKeySession();
      } finally {
        constructing = false;
      }
      // The AVFoundation player's sessions belong to the player of the
      // element the keys are attached to; without one the session does
      // nothing (CDMPrivateMediaPlayer::createSession returns none). They
      // and clear key sessions have an ID (CDMSessionAVFoundationObjC,
      // CDMSessionClearKey); Media Source ones don't.
      const element = keys.kind === 'hls' ? keys.element : null;
      const inert = keys.kind === 'hls' && !element;
      const session = {
        object, keys, element, inert, open: true, error: null,
        sessionId: keys.kind !== 'mse' && !inert ? uuid() : '', chain: resolved,
        certificate: null, keyRelease: false, initData: null, identifier: null,
        modern: null, json: false, pending: [], lastKeyId: null,
        cache: keys.kind === 'clearkey' ? new Map() : null,
      };
      sessionState.set(object, session);
      if (session.cache) {
        keys.sessions.push(session);
      }
      const bytes = copy(initData);
      later(() => generateKeyRequest(session, mime, bytes));
      return object;
    }
    // The default makes its length 1, as for a WebIDL operation with one
    // required argument.
    static isTypeSupported(keySystem, type = undefined) {
      required(1, arguments.length, "execute 'isTypeSupported' on 'WebKitMediaKeys'");
      const system = toDOMString(keySystem);
      const contentType = type === undefined ? '' : toDOMString(type);
      const kind = keySystemKind(system);
      if (!kind) {
        return false;
      }
      // LegacyCDMPrivateAVFObjC::supportsKeySystemAndMimeType answers
      // "keyrelease" ignoring case, where supportsMIMEType doesn't.
      // The AVFoundation player takes clear key for the one HLS type only
      // (MediaPlayerPrivateAVFoundationObjC::supportsKeySystem).
      return contentType === '' ||
          (kind === 'hls' ? avFoundationDecodes(contentType) :
           kind === 'clearkey' ? asciiLower(contentType) === CLEAR_KEY_TYPE :
              asciiLower(contentType) === 'keyrelease' || mediaSourcePlays(contentType));
    }
  }

  // Element side: WebKitMediaKeys::keyAdded reaches the attached player
  // (MediaPlayerPrivateAVFoundationObjC::keyAdded), which fulfils each held
  // clearkey:// request whose key ID cachedKeyFor(keys, keyId) now has.
  // fp-legacy-element and native HLS provide the player side.
  function keysAdded(keys) {
  }

  // Attaching legacy keys gives the element their modern MediaKeys. Keys
  // follow the last element they were set on (WebKitMediaKeys::setMediaElement).
  // Clear key keys have no FairPlay keys to attach.
  function attachKeys(keys, element) {
    const previous = keys.element;
    keys.element = element;
    if (keys.kind === 'clearkey') {
      return;
    }
    const step = () => then(modernKeysOf(keys), (mediaKeys) => {
      if (keys.element !== element) {
        return undefined;
      }
      const detached = previous && previous !== element ?
          then(apply(setMediaKeys, previous, [null]), undefined, () => {}) : resolved;
      return then(detached, () => keys.element === element ?
          apply(setMediaKeys, element, [mediaKeys]) : undefined);
    });
    keys.attaching = then(then(keys.attaching, step), undefined, () => {});
  }
  function detachKeys(keys, element) {
    if (keys.element !== element) {
      return;
    }
    keys.element = null;
    if (keys.kind === 'clearkey') {
      return;
    }
    keys.attaching = then(keys.attaching, () => keys.element === null ?
        then(apply(setMediaKeys, element, [null]), undefined, () => {}) : undefined);
  }

  // webkitneedkey: raised from each encrypted event of a media element, with
  // its init data (skd in WebKit's legacy layout).
  // Once per event: the window's capture listener and a forwarder the page
  // adds on the element during that dispatch both see it. Only the media
  // pipeline's own (trusted) events count; a page's script-made `encrypted`
  // event (Shaka's legacy shim dispatches one from webkitneedkey) is left
  // alone.
  function raiseNeedKey(element, event) {
    if (raisedFrom.has(event)) {
      return;
    }
    raisedFrom.add(event);
    if (event.isTrusted !== true) {
      return;
    }
    let type;
    let buffer;
    try {
      type = apply(initDataTypeOf, event, []);
      buffer = apply(initDataOf, event, []);
    } catch (error) {
      return;
    }
    if (!buffer || (type !== 'cenc' && type !== 'sinf' && type !== 'skd')) {
      return;
    }
    const bytes = new NativeUint8Array(buffer);
    const initData = type === 'skd' ? legacySkdInitData(bytes) : copy(bytes);
    elementInitData.set(element, initData);
    if (type === 'skd') {
      // The request the player holds for this key URI, for a legacy session
      // to take (MediaPlayerPrivateAVFoundationObjC::m_keyURIToRequestMap).
      let requests = elementKeyRequests.get(element);
      if (!requests) {
        requests = new Set();
        elementKeyRequests.set(element, requests);
      }
      requests.add(utf16(initData, 4, initData.length - 4));
    }
    fire(element, new WebKitMediaKeyNeededEvent('webkitneedkey', {initData: copy(initData)}));
  }
  function isMediaElement(value) {
    if (!value || typeof value !== 'object') {
      return false;
    }
    try {
      brandMedia(value);
      return true;
    } catch (error) {
      return false;
    }
  }
  function forwardFrom(element) {
    if (forwarding.has(element)) {
      return;
    }
    forwarding.add(element);
    apply(addListener, element, ['encrypted', (event) => raiseNeedKey(element, event)]);
  }

  const interfaces = [['WebKitMediaKeys', WebKitMediaKeys], ['WebKitMediaKeyError', WebKitMediaKeyError]];
  if (NativeEvent && NativeEventTarget) {
    interfaces.push(['WebKitMediaKeySession', WebKitMediaKeySession],
                    ['WebKitMediaKeyMessageEvent', WebKitMediaKeyMessageEvent],
                    ['WebKitMediaKeyNeededEvent', WebKitMediaKeyNeededEvent]);
  }
  for (const [name, constructor] of interfaces) {
    // WebIDL members are enumerable; the prototype is not writable.
    const prototype = constructor.prototype;
    for (const key of Reflect.ownKeys(prototype)) {
      if (key !== 'constructor') {
        define(prototype, key, {enumerable: true});
      }
    }
    define(prototype, Symbol.toStringTag, {value: name, configurable: true});
    define(constructor, 'prototype', {writable: false});
  }
  define(WebKitMediaKeys, 'isTypeSupported', {enumerable: true});
  for (const [name, value] of ERROR_CODES) {
    const constant = {value, writable: false, enumerable: true, configurable: false};
    define(WebKitMediaKeyError, name, constant);
    define(WebKitMediaKeyError.prototype, name, constant);
  }
  for (const [name, constructor] of interfaces) {
    define(g, name, {value: constructor, writable: true, enumerable: false, configurable: true});
  }

  if (typeof g.MediaError === 'function' && !('MEDIA_ERR_ENCRYPTED' in g.MediaError)) {
    const constant = {value: 5, writable: false, enumerable: true, configurable: false};
    define(g.MediaError, 'MEDIA_ERR_ENCRYPTED', constant);
    define(g.MediaError.prototype, 'MEDIA_ERR_ENCRYPTED', constant);
  }

  if (!mediaPrototype || !pausedOf || !canUseKeys) {
    return;
  }
  const members = {
    webkitSetMediaKeys(mediaKeys) {
      brandMedia(this);
      required(1, arguments.length,
               "execute 'webkitSetMediaKeys' on 'HTMLMediaElement'");
      if (mediaKeys !== undefined && mediaKeys !== null && !keysState.has(mediaKeys)) {
        throw new TypeError("Failed to execute 'webkitSetMediaKeys' on 'HTMLMediaElement': " +
            "parameter 1 is not of type 'WebKitMediaKeys'.");
      }
      const next = mediaKeys === undefined ? null : mediaKeys;
      const current = elementKeys.get(this) || null;
      if (current === next) {
        return;
      }
      if (current) {
        detachKeys(keysState.get(current), this);
      }
      if (next) {
        elementKeys.set(this, next);
        forwardFrom(this);
        attachKeys(keysState.get(next), this);
      } else {
        elementKeys.delete(this);
      }
    },
    get webkitKeys() {
      brandMedia(this);
      return elementKeys.get(this) || null;
    },
    // A webkitneedkey listener on a media element anywhere (detached, or in a
    // shadow tree the window doesn't see) gets the element's events.
    addEventListener(type, listener, options = undefined) {
      if (arguments.length >= 1 && toDOMString(type) === 'webkitneedkey' &&
          isMediaElement(this)) {
        forwardFrom(this);
      }
      return apply(Object.getPrototypeOf(mediaPrototype).addEventListener, this, arguments);
    },
  };
  define(mediaPrototype, 'webkitSetMediaKeys', {
    value: members.webkitSetMediaKeys, writable: true, enumerable: true, configurable: true,
  });
  define(mediaPrototype, 'webkitKeys', {
    get: describe(members, 'webkitKeys').get, enumerable: true, configurable: true,
  });
  define(mediaPrototype, 'addEventListener', {
    value: members.addEventListener, writable: true, enumerable: true, configurable: true,
  });
  // Safari keeps legacy keys out of mediaKeys.
  if (mediaKeysDescriptor && mediaKeysDescriptor.get) {
    const nativeMediaKeys = mediaKeysDescriptor.get;
    define(mediaPrototype, 'mediaKeys', {
      get: describe({
        get mediaKeys() {
          const value = apply(nativeMediaKeys, this, []);
          return value && legacyModernKeys.has(value) ? null : value;
        },
      }, 'mediaKeys').get,
      enumerable: mediaKeysDescriptor.enumerable,
      configurable: true,
    });
  }
  // Every encrypted event of a media element in this window's tree, before
  // its own listeners run.
  try {
    apply(addListener, g, ['encrypted', (event) => {
      const element = apply(eventTarget, event, []);
      if (isMediaElement(element) && !forwarding.has(element)) {
        raiseNeedKey(element, event);
      }
    }, true]);
  } catch (error) {
  }
})();
)PARC_WKMK_JS";

}  // namespace blink

#endif  // THIRD_PARTY_BLINK_RENDERER_BINDINGS_CORE_V8_PARC_WEBKIT_MEDIA_KEYS_H_
