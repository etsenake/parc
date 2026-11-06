// Runs the ManagedMediaSource script from
// Engine/ParcRenderer/parc_managed_media_source.h against a small model of
// Chromium's media APIs. No browser; `node managed_media_source.mjs`.
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';

const header = readFileSync(fileURLToPath(new URL(
    '../../Engine/ParcRenderer/parc_managed_media_source.h', import.meta.url)), 'utf8');
const match = header.match(/R"PARC_MMS_JS\(([\s\S]*)\)PARC_MMS_JS"/);
if (!match) throw new Error('script not found in header');
const script = match[1];

let checks = 0;
function check(condition, message) {
  ++checks;
  if (!condition) {
    console.error('FAIL: ' + message);
    process.exit(1);
  }
}

// ---- Model of the media APIs the script builds on.
function makeWorld() {
  const timers = [];
  const intervals = new Map();
  class TimeRanges {
    constructor() { throw new TypeError('Illegal constructor'); }
  }
  function nativeRanges(list) {
    const value = Object.create(TimeRanges.prototype);
    Object.defineProperty(value, 'length', { value: list.length });
    value.start = (i) => list[i][0];
    value.end = (i) => list[i][1];
    return value;
  }
  class SourceBuffer extends EventTarget {
    constructor(token) {
      if (token !== SourceBuffer.token) throw new TypeError('Illegal constructor');
      super();
      this._ranges = [];
    }
    get buffered() { return nativeRanges(this._ranges); }
    // Test helper: an append or eviction finished with these ranges.
    _finish(list) { this._ranges = list; this.dispatchEvent(new Event('updateend')); }
  }
  SourceBuffer.token = Symbol('sb');
  class SourceBufferList extends Array {}
  class MediaSource extends EventTarget {
    constructor() {
      super();
      this.readyState = 'closed';
      this.duration = NaN;
      this.sourceBuffers = new SourceBufferList();
      this.activeSourceBuffers = new SourceBufferList();
    }
    addSourceBuffer(type) {
      if (!MediaSource.isTypeSupported(type)) throw new DOMException('unsupported', 'NotSupportedError');
      const sb = new SourceBuffer(SourceBuffer.token);
      this.sourceBuffers.push(sb);
      this.activeSourceBuffers.push(sb);
      return sb;
    }
    static isTypeSupported(type) { return /^video\/mp4|^audio\/mp4/.test(type); }
    static get canConstructInDedicatedWorker() { return true; }
    _open() { this.readyState = 'open'; this.dispatchEvent(new Event('sourceopen')); }
    _end() { this.readyState = 'ended'; this.dispatchEvent(new Event('sourceended')); }
    _close() { this.readyState = 'closed'; this.dispatchEvent(new Event('sourceclose')); }
  }
  class Element extends EventTarget {
    constructor() { super(); this.attributes = new Map(); this.parentElement = null; }
    getAttribute(name) { return this.attributes.has(name) ? this.attributes.get(name) : null; }
    setAttribute(name, value) { this.attributes.set(String(name).toLowerCase(), String(value)); }
    removeAttribute(name) { this.attributes.delete(name); }
  }
  class HTMLMediaElement extends Element {
    constructor() { super(); this.currentTime = 0; this._srcObject = null; this.loads = 0; }
    load() { ++this.loads; }
  }
  Object.defineProperty(HTMLMediaElement.prototype, 'src', {
    get() { return this.attributes.get('src') || ''; },
    set(value) { this.attributes.set('src', String(value)); },
    enumerable: true, configurable: true,
  });
  Object.defineProperty(HTMLMediaElement.prototype, 'currentSrc', {
    get() { return this.attributes.get('src') || ''; },
    enumerable: true, configurable: true,
  });
  Object.defineProperty(HTMLMediaElement.prototype, 'srcObject', {
    get() { return this._srcObject; },
    set(value) {
      if (value !== null && !(value instanceof MediaStream)) throw new TypeError('not a MediaStream');
      this._srcObject = value;
    },
    enumerable: true, configurable: true,
  });
  class MediaStream {}
  class HTMLVideoElement extends HTMLMediaElement {}
  class HTMLSourceElement extends Element {}
  Object.defineProperty(HTMLSourceElement.prototype, 'src', {
    get() { return this.attributes.get('src') || ''; },
    set(value) { this.attributes.set('src', String(value)); },
    enumerable: true, configurable: true,
  });
  let nextURL = 0;
  const revoked = [];
  const URL = {
    createObjectURL(object) { return 'blob:https://tv.apple.com/' + (++nextURL); },
    revokeObjectURL(url) { revoked.push(url); },
  };
  const elements = [];
  let nextTimer = 0;
  const context = {
    MediaSource, SourceBuffer, TimeRanges, Event, EventTarget, DOMException, WeakRef,
    Element, HTMLMediaElement, HTMLSourceElement, HTMLVideoElement, MediaStream, URL,
    document: { querySelectorAll: () => elements },
    setTimeout: (fn) => { timers.push(fn); return ++nextTimer; },
    setInterval: (fn) => { const id = ++nextTimer; intervals.set(id, fn); return id; },
    clearInterval: (id) => { intervals.delete(id); },
  };
  context.globalThis = context;
  vm.createContext(context);
  vm.runInContext(script, context);
  return { context, timers, intervals, elements, revoked,
           run: () => { while (timers.length) timers.shift()(); },
           poll: () => { for (const fn of [...intervals.values()]) fn(); } };
}

// ---- Interfaces.
{
  const { context } = makeWorld();
  const { ManagedMediaSource, ManagedSourceBuffer, BufferedChangeEvent, MediaSource, SourceBuffer } = context;
  check(typeof ManagedMediaSource === 'function', 'ManagedMediaSource exists');
  check(Object.getPrototypeOf(ManagedMediaSource) === MediaSource, 'subclass of MediaSource');
  check(Object.getPrototypeOf(ManagedSourceBuffer) === SourceBuffer, 'subclass of SourceBuffer');
  check(!Object.getOwnPropertyDescriptor(context, 'ManagedMediaSource').enumerable, 'interface not enumerable');
  check(Object.getOwnPropertyDescriptor(ManagedMediaSource.prototype, 'streaming').enumerable, 'member enumerable');
  check(Object.prototype.toString.call(new ManagedMediaSource()) === '[object ManagedMediaSource]', 'toStringTag');
  check(ManagedMediaSource.isTypeSupported('video/mp4; codecs="dvh1.05.01"'), 'isTypeSupported delegates');
  check(!ManagedMediaSource.isTypeSupported('video/x-unknown'), 'unsupported type');
  check(ManagedMediaSource.canConstructInDedicatedWorker === false, 'not offered to workers');
  let threw = false;
  try { new ManagedSourceBuffer(); } catch (e) { threw = e.name === 'TypeError'; }
  check(threw, 'ManagedSourceBuffer has no public constructor');
  const event = new BufferedChangeEvent('bufferedchange');
  check(event.addedRanges.length === 0 && event.removedRanges.length === 0, 'empty event ranges');
  check(event instanceof context.Event, 'BufferedChangeEvent is an Event');
}

// Running twice changes nothing.
{
  const { context } = makeWorld();
  const before = context.ManagedMediaSource;
  vm.runInContext(script, context);
  check(context.ManagedMediaSource === before, 'script is idempotent');
}

// ---- Streaming and buffered changes through srcObject.
{
  const world = makeWorld();
  const { context } = world;
  const source = new context.ManagedMediaSource();
  check(source instanceof context.MediaSource, 'instance is a MediaSource');
  check(source.streaming === false, 'not streaming before it opens');
  const video = new context.HTMLVideoElement();
  world.elements.push(video);
  video.setAttribute('src', 'https://example.com/poster-fallback.mp4');
  video.srcObject = source;
  const attachedURL = video.attributes.get('src');
  check(attachedURL.startsWith('blob:'), 'srcObject plays through an object URL');
  check(video.srcObject === source, 'srcObject reports the managed source');
  check(video.src === '' && video.currentSrc === '', 'src and currentSrc are empty, as in Safari');
  let starts = 0, ends = 0, handled = 0;
  source.addEventListener('startstreaming', () => ++starts);
  source.addEventListener('endstreaming', () => ++ends);
  source.onstartstreaming = () => ++handled;
  check(typeof source.onstartstreaming === 'function', 'handler attribute reads back');
  source._open();
  world.run();
  check(world.revoked.includes(attachedURL), 'srcObject URL revoked once open');
  check(source.streaming === true && starts === 1 && handled === 1, 'startstreaming once open and empty');

  const sb = source.addSourceBuffer('video/mp4; codecs="dvh1.05.01"');
  check(sb instanceof context.ManagedSourceBuffer && sb instanceof context.SourceBuffer, 'ManagedSourceBuffer');
  const changes = [];
  sb.addEventListener('bufferedchange', (e) => changes.push(e));
  let attributeChanges = 0;
  sb.onbufferedchange = () => ++attributeChanges;

  sb._finish([[0, 12]]);
  check(changes.length === 0, 'bufferedchange is queued as a task, not fired inside updateend');
  world.run();
  check(changes.length === 1 && attributeChanges === 1, 'bufferedchange after an append');
  check(changes[0].addedRanges.length === 1 && changes[0].addedRanges.start(0) === 0 &&
        changes[0].addedRanges.end(0) === 12 && changes[0].removedRanges.length === 0, 'added range');
  check(changes[0].addedRanges instanceof context.TimeRanges, 'ranges are TimeRanges');
  check(source.streaming === true && ends === 0, '12 s ahead keeps streaming');

  sb._finish([[0, 31]]);
  world.run();
  check(changes[1].addedRanges.start(0) === 12 && changes[1].addedRanges.end(0) === 31, 'only the new part is added');
  check(source.streaming === false && ends === 1, 'endstreaming at 30 s ahead');

  sb._finish([[0, 31]]);
  world.run();
  check(changes.length === 2, 'no event when nothing changed');

  video.currentTime = 25;
  video.dispatchEvent(new context.Event('timeupdate'));
  check(source.streaming === true && starts === 2, 'startstreaming again under 10 s ahead');

  sb._finish([[10, 40]]);
  world.run();
  check(changes[2].removedRanges.length === 1 && changes[2].removedRanges.start(0) === 0 &&
        changes[2].removedRanges.end(0) === 10, 'eviction reported as removed');
  check(changes[2].addedRanges.start(0) === 31 && changes[2].addedRanges.end(0) === 40, 'and the new data as added');

  // A range change without an append (garbage collection) is caught by the poll.
  sb._ranges = [[20, 40]];
  world.poll();
  world.run();
  check(changes.length === 4 && changes[3].removedRanges.start(0) === 10 &&
        changes[3].removedRanges.end(0) === 20, 'poll reports changes made without an append');

  source.duration = 45;
  sb._finish([[20, 45]]);
  world.run();
  check(source.streaming === false, 'buffered to the end stops streaming');

  // End of stream, then a seek back into data that was evicted.
  source._end();
  check(source.streaming === false, 'ended and fully buffered: not streaming');
  video.currentTime = 2;
  video.dispatchEvent(new context.Event('seeking'));
  check(source.streaming === true, 'a seek back after endOfStream starts streaming again');

  let bad = false;
  try { changes[0].addedRanges.start(1); } catch (e) { bad = e.name === 'IndexSizeError'; }
  check(bad, 'out-of-range index throws IndexSizeError');

  const loadsBefore = video.loads;
  video.load();
  const reattached = video.attributes.get('src');
  check(reattached.startsWith('blob:') && reattached !== attachedURL && video.loads === loadsBefore,
        'load() attaches the managed source again through a new URL');
  check(video.srcObject === source, 'still the managed source after load()');

  source._close();
  check(source.streaming === false, 'closed source does not stream');
  check(world.intervals.size === 0, 'poll ends when the source closes');

  video.srcObject = null;
  check(video.srcObject === null, 'clearing srcObject detaches the source');
  check(video.attributes.get('src') === 'https://example.com/poster-fallback.mp4',
        'clearing srcObject restores the src attribute set before');
  check(world.revoked.includes(reattached), 'its URL is revoked');
}

// ---- Attachment through src with an object URL, setAttribute, and <source>.
{
  const world = makeWorld();
  const { context } = world;
  const source = new context.ManagedMediaSource();
  const url = context.URL.createObjectURL(source);
  const video = new context.HTMLVideoElement();
  video.src = url;
  video.currentTime = 100;
  source._open();
  world.run();
  const sb = source.addSourceBuffer('audio/mp4; codecs="ec-3"');
  sb._finish([[100, 135]]);
  check(source.streaming === false, 'src attachment uses the element position');

  const viaAttribute = new context.ManagedMediaSource();
  const attributeURL = context.URL.createObjectURL(viaAttribute);
  const second = new context.HTMLVideoElement();
  second.setAttribute('SRC', attributeURL);
  second.currentTime = 40;
  viaAttribute._open();
  world.run();
  viaAttribute.addSourceBuffer('video/mp4; codecs="avc1.640028"')._finish([[40, 75]]);
  check(viaAttribute.streaming === false, 'setAttribute("src") attachment finds its element');

  const other = new context.ManagedMediaSource();
  const otherURL = context.URL.createObjectURL(other);
  const holder = new context.HTMLVideoElement();
  const child = new context.HTMLSourceElement();
  child.parentElement = holder;
  child.src = otherURL;
  holder.currentTime = 50;
  other._open();
  world.run();
  const otherSB = other.addSourceBuffer('video/mp4; codecs="avc1.640028"');
  otherSB._finish([[0, 55]]);
  check(other.streaming === true, '<source> attachment finds its media element (5 s ahead)');
  otherSB._finish([[0, 90]]);
  check(other.streaming === false, 'enough buffered ahead of the <source> parent');
  holder.currentTime = 85;
  holder.dispatchEvent(new context.Event('seeking'));
  check(other.streaming === true, 'seeking on the media element (not the <source>) is heard at once');
}

// ---- Unknown playback position: may start, never stops.
{
  const world = makeWorld();
  const { context } = world;
  const source = new context.ManagedMediaSource();
  source._open();
  world.run();
  check(source.streaming === true, 'starts streaming with no element known');
  const sb = source.addSourceBuffer('video/mp4; codecs="avc1.640028"');
  sb._finish([[0, 120]]);
  check(source.streaming === true, 'never stops while the playhead is unknown');
}

// ---- Listener cleanup, setAttribute scope, a second element.
{
  const world = makeWorld();
  const { context } = world;
  const video = new context.HTMLVideoElement();
  let added = 0, removed = 0;
  const add = video.addEventListener.bind(video), remove = video.removeEventListener.bind(video);
  video.addEventListener = (type, fn) => { ++added; add(type, fn); };
  video.removeEventListener = (type, fn) => { ++removed; remove(type, fn); };
  const first = new context.ManagedMediaSource();
  video.srcObject = first;
  first._open();
  world.run();
  check(added === 6, 'six playback listeners while a source plays');
  first._close();
  check(removed === 6, 'they go when the source closes');

  check(context.Element.prototype.setAttribute.toString().includes('attributes.set'),
        'Element.prototype.setAttribute stays native');
  check(Object.prototype.hasOwnProperty.call(context.HTMLMediaElement.prototype, 'setAttribute') &&
        Object.prototype.hasOwnProperty.call(context.HTMLSourceElement.prototype, 'setAttribute'),
        'only media and <source> elements are wrapped');

  const playing = new context.ManagedMediaSource();
  const one = new context.HTMLVideoElement();
  const two = new context.HTMLVideoElement();
  one.srcObject = playing;
  one.currentTime = 0;
  playing._open();
  world.run();
  const sb = playing.addSourceBuffer('video/mp4; codecs="avc1.640028"');
  sb._finish([[0, 5]]);
  check(playing.streaming === true, 'playing element 5 s ahead: streaming');
  two.currentTime = 1000;
  two.srcObject = playing;  // fails in Chromium: the source is already open on `one`
  one.dispatchEvent(new context.Event('timeupdate'));
  check(playing.streaming === true, 'a failed second attach does not take over the policy');
}

// A MediaStream still goes to Chromium's srcObject.
{
  const { context } = makeWorld();
  const video = new context.HTMLVideoElement();
  const stream = new context.MediaStream();
  video.srcObject = stream;
  check(video.srcObject === stream, 'MediaStream srcObject unchanged');
  video.load();
  check(video.loads === 1, 'load() of an ordinary element is the native one');
}

console.log('managed media source: ' + checks + ' checks passed');
