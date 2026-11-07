// Runs the WebKitMediaKeys script from
// Engine/ParcRenderer/parc_webkit_media_keys.h against a model of what
// Chromium's MediaSource.isTypeSupported answers on a Safari-identity page.
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
function makeWorld() {
  const calls = [];
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
  const context = { MediaSource, DOMException, calls };
  context.window = context;
  vm.createContext(context);
  return context;
}
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

// ---- The constructor: no legacy key sessions.
{
  const world = makeWorld();
  run(world, script);
  const construct = (...args) => thrown(() => new world.WebKitMediaKeys(...args));
  for (const keySystem of ['com.apple.fps.2_0', 'com.apple.fps.3_0', 'com.apple.fps',
                           'com.apple.fps.1_0', 'com.widevine.alpha']) {
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
  // Disney+'s native client (dwp bundle), exactly: the failure stays inside
  // its try, as the ReferenceError did before the object existed.
  check(run(world, `((J = WebKitMediaKeys) => { try { new J("com.apple.fps.1_0"); return "made"; }
      catch (e) { return e.name; } })()`) === 'NotSupportedError', "Disney+'s native client catches it");
}

// ---- An existing WebKitMediaKeys is left alone.
{
  const world = makeWorld();
  run(world, 'globalThis.WebKitMediaKeys = function Existing() {};');
  run(world, script);
  check(world.WebKitMediaKeys.name === 'Existing', 'an existing WebKitMediaKeys is kept');
}

console.log(`webkit media keys: ${checks} checks passed`);
