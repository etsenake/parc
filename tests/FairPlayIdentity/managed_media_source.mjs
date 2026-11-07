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
function makeWorld(options = {}) {
  const timers = [];
  const intervals = new Map();
  class TimeRanges {
    constructor() { throw new TypeError('Illegal constructor'); }
  }
  Object.defineProperty(TimeRanges.prototype, Symbol.toStringTag, { value: 'TimeRanges', configurable: true });
  function nativeRanges(list) {
    const value = Object.create(TimeRanges.prototype);
    Object.defineProperty(value, 'length', { value: list.length });
    value.start = (i) => list[i][0];
    value.end = (i) => list[i][1];
    return value;
  }
  const busy = () => new DOMException('busy', 'InvalidStateError');
  class SourceBuffer extends EventTarget {
    constructor(token) {
      if (token !== SourceBuffer.token) throw new TypeError('Illegal constructor');
      super();
      this._ranges = [];
      this._updating = false;
      this._settings = { timestampOffset: 0, appendWindowStart: 0, appendWindowEnd: Infinity, mode: 'segments' };
      this.calls = [];
    }
    get buffered() { return nativeRanges(this._ranges); }
    get updating() { return this._updating; }
    appendBuffer(data) { if (this._updating) throw busy(); this._updating = true; this.calls.push('appendBuffer'); }
    remove(start, end) { if (this._updating) throw busy(); this._updating = true; this.calls.push('remove'); }
    abort() {
      this.calls.push('abort');
      if (this._updating) {
        this._updating = false;
        this.dispatchEvent(new Event('abort'));
        this.dispatchEvent(new Event('updateend'));
      }
    }
    changeType(type) { if (this._updating) throw busy(); this.type = type; }
    // Test helper: an append or eviction finished with these ranges.
    _finish(list) {
      this._ranges = list;
      this._updating = false;
      this.dispatchEvent(new Event('update'));
      this.dispatchEvent(new Event('updateend'));
    }
    // Test helper: an append failed after parsing changed the ranges.
    _fail(list) {
      this._ranges = list;
      this._updating = false;
      this.dispatchEvent(new Event('error'));
      this.dispatchEvent(new Event('updateend'));
    }
  }
  for (const name of ['timestampOffset', 'appendWindowStart', 'appendWindowEnd', 'mode']) {
    Object.defineProperty(SourceBuffer.prototype, name, {
      get() { return this._settings[name]; },
      set(value) { if (this._updating) throw busy(); this._settings[name] = value; },
      enumerable: true, configurable: true,
    });
  }
  SourceBuffer.token = Symbol('sb');
  class SourceBufferList extends Array {}
  class MediaSource extends EventTarget {
    constructor() {
      super();
      this.readyState = 'closed';
      this._duration = NaN;
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
    get duration() { return this._duration; }
    set duration(value) { this._duration = value; }
    endOfStream() { this._end(); }
    removeSourceBuffer(sb) {
      for (const list of [this.sourceBuffers, this.activeSourceBuffers]) {
        if (list.includes(sb)) list.splice(list.indexOf(sb), 1);
      }
    }
    static isTypeSupported(type) {
      if (!arguments.length) throw new TypeError('1 argument required');
      return /^video\/mp4|^audio\/mp4/.test(type);
    }
    static get canConstructInDedicatedWorker() { return true; }
    _deactivate(sb) { this.activeSourceBuffers.splice(this.activeSourceBuffers.indexOf(sb), 1); }
    _activate(sb) { this.activeSourceBuffers.push(sb); }
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
  if (options.worker) {
    // A dedicated worker: MediaSource and SourceBuffer, TimeRanges objects
    // without a TimeRanges interface, no DOM.
    for (const name of ['TimeRanges', 'Element', 'HTMLMediaElement', 'HTMLSourceElement',
                        'HTMLVideoElement', 'document']) {
      delete context[name];
    }
  }
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
  check(ManagedMediaSource.canConstructInDedicatedWorker === true, 'offered to workers, which get it too');
  const managed = new ManagedMediaSource();
  check(managed.quality === 'high', 'quality is "high", as WebKit answers');
  let illegal = false;
  try { Object.getOwnPropertyDescriptor(ManagedMediaSource.prototype, 'quality').get.call({}); }
  catch (e) { illegal = e.name === 'TypeError'; }
  check(illegal, 'quality on another object is an illegal invocation');
  check(managed.onqualitychange === null, 'onqualitychange starts null');
  let qualityEvents = 0;
  managed.onqualitychange = () => ++qualityEvents;
  managed.dispatchEvent(new context.Event('qualitychange'));
  check(typeof managed.onqualitychange === 'function' && qualityEvents === 1, 'onqualitychange is an event handler');
  check(Object.getOwnPropertyNames(ManagedMediaSource.prototype).join() ===
        'constructor,quality,onqualitychange,streaming,onstartstreaming,onendstreaming',
        'exactly the members of WebKit\'s ManagedMediaSource.idl, in order');
  check(Object.getOwnPropertyNames(ManagedMediaSource).sort().join() === 'isTypeSupported,length,name,prototype' &&
        Object.getOwnPropertyDescriptor(ManagedMediaSource, 'isTypeSupported').enumerable &&
        ManagedMediaSource.length === 0 && ManagedMediaSource.isTypeSupported.length === 1,
        'the interface object has WebKit\'s statics; canConstructInDedicatedWorker comes from MediaSource');
  let noArgument = false;
  try { ManagedMediaSource.isTypeSupported(); } catch (e) { noArgument = e.name === 'TypeError'; }
  check(noArgument, 'isTypeSupported() without a type throws like MediaSource\'s');
  for (const name of ['onqualitychange', 'onstartstreaming', 'onendstreaming']) {
    let foreign = false;
    try { Object.getOwnPropertyDescriptor(ManagedMediaSource.prototype, name).get.call(new MediaSource()); }
    catch (e) { foreign = e.name === 'TypeError'; }
    check(foreign, name + ' on a plain MediaSource is an illegal invocation');
  }
  let badInit = false;
  try { new ManagedMediaSource(5); } catch (e) { badInit = e.name === 'TypeError'; }
  check(badInit, 'a non-dictionary init is a TypeError');
  let readDetachable = false;
  new ManagedMediaSource({ get detachable() { readDetachable = true; return false; } });
  check(readDetachable, 'MediaSourceInit.detachable is read');
  const plainSB = new MediaSource().addSourceBuffer('video/mp4');
  check(Object.getPrototypeOf(plainSB) === SourceBuffer.prototype, 'a plain MediaSource still makes plain SourceBuffers');
  let foreignHandler = false;
  try { Object.getOwnPropertyDescriptor(ManagedSourceBuffer.prototype, 'onbufferedchange').set.call(plainSB, () => {}); }
  catch (e) { foreignHandler = e.name === 'TypeError'; }
  check(foreignHandler, 'onbufferedchange on a plain SourceBuffer is an illegal invocation');
  check(Object.getOwnPropertyDescriptor(ManagedMediaSource.prototype, 'quality').enumerable &&
        Object.getOwnPropertyDescriptor(ManagedMediaSource.prototype, 'onqualitychange').enumerable,
        'quality and onqualitychange are enumerable');
  let threw = false;
  try { new ManagedSourceBuffer(); } catch (e) { threw = e.name === 'TypeError'; }
  check(threw, 'ManagedSourceBuffer has no public constructor');
  let oneArgument = false;
  try { new BufferedChangeEvent('bufferedchange'); } catch (e) { oneArgument = e.name === 'TypeError'; }
  check(oneArgument && BufferedChangeEvent.length === 2, 'the init dictionary is required, as WebKit\'s IDL has it');
  const event = new BufferedChangeEvent('bufferedchange', {});
  check(event.addedRanges === null && event.removedRanges === null, 'ranges not given are null');
  check(event instanceof context.Event, 'BufferedChangeEvent is an Event');
  const given = new BufferedChangeEvent('bufferedchange', { addedRanges: plainSB.buffered });
  check(given.addedRanges === given.addedRanges && given.addedRanges instanceof context.TimeRanges &&
        given.removedRanges === null, 'given TimeRanges are kept, the same object each time');
  let notRanges = false;
  try { new BufferedChangeEvent('bufferedchange', { removedRanges: [[0, 1]] }); } catch (e) { notRanges = e.name === 'TypeError'; }
  check(notRanges, 'ranges that are not TimeRanges are a TypeError');
  let readRemoved = false;
  try {
    new BufferedChangeEvent('bufferedchange', { addedRanges: {}, get removedRanges() { readRemoved = true; } });
  } catch (e) {}
  check(!readRemoved, 'an invalid addedRanges throws before removedRanges is read');
  const otherFrameRanges = Object.create({ [Symbol.toStringTag]: 'TimeRanges' });
  check(new BufferedChangeEvent('x', { addedRanges: otherFrameRanges }).addedRanges === otherFrameRanges,
        'another frame\'s TimeRanges are accepted');
  let foreignEvent = false;
  try { Object.getOwnPropertyDescriptor(BufferedChangeEvent.prototype, 'addedRanges').get.call(new context.Event('x')); }
  catch (e) { foreignEvent = e.name === 'TypeError'; }
  check(foreignEvent, 'addedRanges on another event is an illegal invocation');
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
  check(changes.length === 1 && attributeChanges === 1, 'bufferedchange as the append completes');
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
  check(source.streaming === true && starts === 1, 'streaming changes at once, its event is a task');
  world.run();
  check(starts === 2, 'startstreaming again under 10 s ahead');

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
  check(source.streaming === true,
        'buffered to the duration of an open source: still streaming (WebKit caps at the duration once ended)');

  // End of stream, then a seek back into data that was evicted.
  source._end();
  check(source.streaming === false, 'ended and buffered to the end: not streaming');
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

// ---- WebKit's streaming policy (ManagedMediaSource::monitorSourceBuffers).
{
  const world = makeWorld();
  const { context } = world;
  const source = new context.ManagedMediaSource();
  const video = new context.HTMLVideoElement();
  video.srcObject = source;
  let seenInSourceOpen = null;
  source.addEventListener('sourceopen', () => { seenInSourceOpen = source.streaming; }, true);
  const order = [];
  source.addEventListener('sourceopen', () => order.push('sourceopen'));
  source.addEventListener('startstreaming', () => order.push('startstreaming'));
  source.addEventListener('endstreaming', () => order.push('endstreaming'));
  source._open();
  check(seenInSourceOpen === true, 'streaming is already true when the page hears sourceopen');
  world.run();
  check(order.join() === 'sourceopen,startstreaming', 'startstreaming follows sourceopen as its own task');

  const first = source.addSourceBuffer('video/mp4; codecs="avc1.640028"');
  source._deactivate(first);
  first._finish([[0, 60]]);
  check(source.streaming === true, 'with no active SourceBuffer the source streams, whatever is buffered');
  source._activate(first);
  let streamingDuringUpdate = null;
  first.addEventListener('update', () => { streamingDuringUpdate = source.streaming; }, true);
  first._finish([[0, 60]]);
  check(streamingDuringUpdate === false, 'once active, 30 s ahead stops it before the page hears update');
  world.run();

  const audio = source.addSourceBuffer('audio/mp4; codecs="mp4a.40.2"');
  audio._finish([[0, 8]]);
  check(source.streaming === true, 'the active SourceBuffers\' intersection decides: 8 s of audio ahead');
  audio._finish([[0, 60]]);
  check(source.streaming === false, 'all of them 30 s ahead stops it');

  // Both transitions in one task queue both events, in order.
  world.run();
  order.length = 0;
  audio._finish([[0, 5]]);
  audio._finish([[0, 60]]);
  check(order.length === 0, 'no event fires synchronously');
  world.run();
  check(order.join() === 'startstreaming,endstreaming', 'each change queues its own event');

  // Ended with the playback position at the duration: never streaming.
  source.duration = 20;
  first._finish([]);
  check(source.streaming === true, 'nothing buffered: streaming');
  video.currentTime = 20;
  source._end();
  check(source.streaming === false, 'ended at the duration: not streaming, though nothing is buffered');
  video.currentTime = 5;
  video.dispatchEvent(new context.Event('seeking'));
  check(source.streaming === true, 'a seek back from the end starts streaming');
}

// ---- WebKit's gap tolerances: 125 ms, 250 ms where audio covers the gap,
// 1 s before the first range near the start.
{
  const world = makeWorld();
  const { context } = world;
  const source = new context.ManagedMediaSource();
  const video = new context.HTMLVideoElement();
  video.srcObject = source;
  source._open();
  const sb = source.addSourceBuffer('video/mp4; codecs="avc1.640028"');
  sb._finish([[0, 10], [10.1, 40]]);
  check(source.streaming === false, 'a gap under 125 ms counts as buffered');
  video.currentTime = 5;
  sb._finish([[0, 10], [10.2, 40]]);
  check(source.streaming === true, 'a 200 ms gap with no audio across it is a hole');
  const muxed = source.addSourceBuffer('video/mp4; codecs="avc1.640028,mp4a.40.2"');
  muxed._finish([[0, 40]]);
  check(source.streaming === false, 'audio across the gap widens the tolerance to 250 ms');
  muxed.changeType('video/mp4; codecs="avc1.640028"');
  video.dispatchEvent(new context.Event('timeupdate'));
  check(source.streaming === true, 'after changeType to video only, the gap is a hole again');
  let constructed = true;
  try { new (muxed.changeType)('video/mp4'); } catch (e) { constructed = e.name !== 'TypeError'; }
  check(!constructed, 'the wrapped changeType is not a constructor, like the native one');

  video.currentTime = 0;
  sb._finish([[0.5, 40]]);
  muxed._finish([[0.5, 40]]);
  check(source.streaming === false, 'a first range starting within 1 s covers the start');
  sb._finish([[1.5, 40]]);
  check(source.streaming === true, 'a first range starting after 1 s leaves the start unbuffered');
}

// ---- bufferedchange inside the operation, as WebKit queues it: before update
// and updateend, with the SourceBuffer still updating.
{
  const world = makeWorld();
  const { context } = world;
  const source = new context.ManagedMediaSource();
  const video = new context.HTMLVideoElement();
  video.srcObject = source;
  source._open();
  world.run();
  const sb = source.addSourceBuffer('video/mp4; codecs="avc1.640028"');
  const order = [];
  let updatingThen = null, updatingAtUpdate = null;
  let onChange = () => {};
  sb.addEventListener('bufferedchange', (e) => { order.push('bufferedchange'); updatingThen = sb.updating; onChange(e); });
  sb.addEventListener('update', () => { order.push('update'); updatingAtUpdate = sb.updating; }, true);
  sb.addEventListener('updateend', () => order.push('updateend'));
  sb.addEventListener('abort', () => order.push('abort'));
  sb.appendBuffer(new Uint8Array(1));
  sb._finish([[0, 10]]);
  check(order.join() === 'bufferedchange,update,updateend',
        'bufferedchange reaches the page before update and updateend, even a capturing update listener');
  check(updatingThen === true && updatingAtUpdate === false && sb.updating === false,
        'updating reads true during bufferedchange only');

  // While it is dispatched, the SourceBuffer and its source refuse what
  // WebKit refuses while updating.
  const refused = [];
  const attempt = (name, fn) => {
    try { fn(); } catch (e) { if (e.name === 'InvalidStateError') refused.push(name); }
  };
  onChange = () => {
    attempt('appendBuffer', () => sb.appendBuffer(new Uint8Array(1)));
    attempt('remove', () => sb.remove(0, 1));
    attempt('changeType', () => sb.changeType('video/mp4; codecs="hvc1.1.6.L93.B0"'));
    attempt('timestampOffset', () => { sb.timestampOffset = 5; });
    attempt('appendWindowStart', () => { sb.appendWindowStart = 1; });
    attempt('appendWindowEnd', () => { sb.appendWindowEnd = 50; });
    attempt('mode', () => { sb.mode = 'sequence'; });
    attempt('endOfStream', () => source.endOfStream());
    attempt('duration', () => { source.duration = 100; });
  };
  sb.appendBuffer(new Uint8Array(1));
  sb._finish([[0, 20]]);
  check(refused.join() === 'appendBuffer,remove,changeType,timestampOffset,appendWindowStart,appendWindowEnd,mode,endOfStream,duration',
        'every mutation WebKit refuses while updating throws InvalidStateError: ' + refused.join());
  check(sb.timestampOffset === 0 && sb.mode === 'segments' && source.readyState === 'open',
        'and none of them took effect');
  onChange = () => {};
  sb.appendBuffer(new Uint8Array(1));
  check(sb.updating === true, 'after the event, appends work again');

  // abort() during it ends the append with abort and updateend, not update.
  order.length = 0;
  onChange = () => { sb.abort(); };
  sb._finish([[0, 30]]);
  check(order.join() === 'bufferedchange,abort,updateend', 'abort() turns update/updateend into abort/updateend: ' + order.join());
  check(sb.calls.filter((c) => c === 'abort').length === 1, 'the native abort ran once (parser and append window reset)');

  // After abort() the SourceBuffer is no longer updating, as in WebKit.
  let afterAbort = null;
  onChange = () => { sb.abort(); afterAbort = sb.updating; sb.timestampOffset = 4; };
  sb.appendBuffer(new Uint8Array(1));
  sb._finish([[0, 35]]);
  check(afterAbort === false && sb.timestampOffset === 4, 'abort() ends updating at once; setters work again');
  sb.timestampOffset = 0;

  // A removal can't be aborted.
  order.length = 0;
  let abortError = null;
  onChange = () => { try { sb.abort(); } catch (e) { abortError = e.name; } };
  sb.remove(0, 5);
  sb._finish([[5, 30]]);
  check(abortError === 'InvalidStateError' && order.join() === 'bufferedchange,update,updateend',
        'abort() during a removal\'s bufferedchange throws, the removal completes');

  // removeSourceBuffer during it aborts the append too.
  order.length = 0;
  onChange = () => { source.removeSourceBuffer(sb); };
  sb.appendBuffer(new Uint8Array(1));
  sb._finish([[5, 40]]);
  check(order.join() === 'bufferedchange,abort,updateend', 'removeSourceBuffer aborts the operation still running');
  check(!source.sourceBuffers.includes(sb), 'and removes the SourceBuffer');
}

// ---- Changes outside an operation are queued as tasks; a failed append
// reports what its parsing changed before updateend.
{
  const world = makeWorld();
  const { context } = world;
  const source = new context.ManagedMediaSource();
  const video = new context.HTMLVideoElement();
  video.srcObject = source;
  source._open();
  world.run();
  const sb = source.addSourceBuffer('video/mp4; codecs="avc1.640028"');
  const changes = [];
  let updatingThen = null;
  sb.addEventListener('bufferedchange', (e) => { changes.push(e); updatingThen = sb.updating; });
  sb._finish([[0, 30]]);

  // endOfStream extends the last range; the change is a task, not updating.
  sb._ranges = [[0, 32]];
  source.endOfStream();
  check(changes.length === 1, 'nothing synchronous at endOfStream');
  world.run();
  check(changes.length === 2 && changes[1].addedRanges.start(0) === 30 && changes[1].addedRanges.end(0) === 32 &&
        updatingThen === false, 'endOfStream\'s change is queued as a task');

  // Setting timestampOffset reopens the ended source, dropping the extension.
  sb._ranges = [[0, 30]];
  sb.timestampOffset = 10;
  source.readyState = 'open';
  world.run();
  check(changes.length === 3 && changes[2].removedRanges.start(0) === 30, 'a setter that reopens the source reports the change');

  // A setter on another SourceBuffer leaves this one's pending change alone,
  // and only timestampOffset and mode on an ended source report changes.
  const second = source.addSourceBuffer('audio/mp4; codecs="mp4a.40.2"');
  sb.appendBuffer(new Uint8Array(1));
  sb._ranges = [[0, 31]];
  source.readyState = 'ended';
  second.timestampOffset = 1;
  second.appendWindowEnd = 100;
  world.run();
  check(changes.length === 3, 'an updating SourceBuffer\'s change waits for its update');
  sb._finish([[0, 31]]);
  check(changes.length === 4 && changes[3].addedRanges.start(0) === 30 && changes[3].addedRanges.end(0) === 31,
        'and is reported as the operation completes');
  source.readyState = 'open';
  sb._ranges = [[0, 30]];
  sb.appendWindowStart = 0;
  world.run();
  check(changes.length === 4, 'append window setters report nothing');
  sb._finish([[0, 30]]);
  changes.splice(3);

  // A shorter duration.
  sb._ranges = [[0, 25]];
  source.duration = 25;
  world.run();
  check(changes.length === 4 && changes[3].removedRanges.start(0) === 25 && changes[3].removedRanges.end(0) === 30,
        'a shorter duration\'s change is queued');

  // The poll leaves a SourceBuffer that is updating to report at completion.
  sb.appendBuffer(new Uint8Array(1));
  sb._ranges = [[0, 25], [26, 28]];
  world.poll();
  world.run();
  check(changes.length === 4, 'the poll skips a SourceBuffer still updating');
  const order = [];
  sb.addEventListener('updateend', () => order.push('updateend'));
  sb.addEventListener('bufferedchange', () => order.push('bufferedchange'));
  sb._fail([[0, 25], [26, 29]]);
  check(changes.length === 5 && changes[4].addedRanges.start(0) === 26 && order.join() === 'bufferedchange,updateend',
        'a failed append reports its parsed ranges before updateend');
}

// ---- A memory-pressure purge by the engine (SourceBuffer::ParcPurge_Locked)
// is reported as WebKit reports it: bufferedchange as a task, streaming
// re-evaluated, the engine's events hidden from the page.
{
  const world = makeWorld();
  const { context } = world;
  const source = new context.ManagedMediaSource();
  const video = new context.HTMLVideoElement();
  video.srcObject = source;
  source._open();
  world.run();
  const sb = source.addSourceBuffer('video/mp4; codecs="avc1.640028"');
  sb._finish([[0, 40], [60, 90]]);
  world.run();
  check(source.streaming === false, 'buffered ahead: not streaming');
  const changes = [];
  sb.addEventListener('bufferedchange', (e) => changes.push(e));
  let pageSawPurge = false, pageSawMarker = false;
  sb.addEventListener('parcmanagedmediasourcepurged', () => { pageSawPurge = true; });
  source.addEventListener('parcmanagedmediasource', () => { pageSawMarker = true; });
  source.dispatchEvent(new context.Event('parcmanagedmediasource'));
  check(!pageSawMarker, 'the marker event never reaches the page');

  // The engine kept 0-40 around the position 0 and dropped 60-90.
  sb._ranges = [[0, 40]];
  sb.dispatchEvent(new context.Event('parcmanagedmediasourcepurged'));
  check(changes.length === 1 && changes[0].removedRanges.length === 1 &&
        changes[0].removedRanges.start(0) === 60 && changes[0].removedRanges.end(0) === 90 &&
        changes[0].addedRanges.length === 0, 'the purge is a bufferedchange with the removed ranges');
  check(!pageSawPurge, 'the engine\'s purge event never reaches the page');

  // A purge that took the data ahead of the position restarts streaming.
  // WebKit's low threshold is the closed window [t, t + 10 s], so exactly
  // 10 s ahead still counts as buffered.
  video.currentTime = 30;
  sb._ranges = [[28, 40]];
  sb.dispatchEvent(new context.Event('parcmanagedmediasourcepurged'));
  check(changes.length === 2 && changes[1].removedRanges.start(0) === 0 && changes[1].removedRanges.end(0) === 28,
        'the front of the buffer went');
  check(source.streaming === false, 'exactly 10 s ahead after the purge: still not streaming');
  video.currentTime = 31;
  video.dispatchEvent(new context.Event('timeupdate'));
  check(source.streaming === true, '9 s ahead after the purge: streaming again');

  // An operation started since reports the change when it completes.
  sb.appendBuffer(new Uint8Array(1));
  sb._ranges = [[30, 40]];
  sb.dispatchEvent(new context.Event('parcmanagedmediasourcepurged'));
  check(changes.length === 2, 'no report while an operation runs');
  sb._finish([[30, 50]]);
  check(changes.length === 3 && changes[2].removedRanges.start(0) === 28 && changes[2].addedRanges.start(0) === 40,
        'the operation reports the purge with its own change');
}

// ---- Other SourceBuffers and MediaSources keep the native behaviour.
{
  const world = makeWorld();
  const { context } = world;
  const plain = new context.MediaSource();
  plain.readyState = 'open';
  const sb = plain.addSourceBuffer('video/mp4; codecs="avc1.640028"');
  sb.appendBuffer(new Uint8Array(1));
  check(sb.updating === true, 'native updating');
  let threw = false;
  try { sb.appendBuffer(new Uint8Array(1)); } catch (e) { threw = e.message === 'busy'; }
  check(threw, 'the native InvalidStateError');
  sb._finish([[0, 5]]);
  sb.timestampOffset = 3;
  plain.duration = 9;
  check(sb.timestampOffset === 3 && plain.duration === 9, 'native setters');
  check(Object.getOwnPropertyNames(context.ManagedSourceBuffer.prototype).sort().join() === 'constructor,onbufferedchange',
        'ManagedSourceBuffer.prototype has only WebKit\'s members');
  let constructed = true;
  try { new (sb.appendBuffer)(); } catch (e) { constructed = e.name !== 'TypeError'; }
  check(!constructed, 'replaced methods are not constructors');
  check(Object.getOwnPropertyDescriptor(context.SourceBuffer.prototype, 'updating').get.name === 'get updating',
        'the updating getter keeps its name');
  check(context.MediaSource.prototype.endOfStream.length === 0 && context.SourceBuffer.prototype.remove.length === 2,
        'replaced methods keep their arity');
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
  const url = context.URL.createObjectURL(playing);
  const three = new context.HTMLVideoElement();
  three.currentTime = 2000;
  three.src = url;
  one.dispatchEvent(new context.Event('timeupdate'));
  check(playing.streaming === true, 'src naming an open source elsewhere does not take over the policy');
}

// ---- A dedicated worker of a Safari-identity document.
{
  const world = makeWorld({ worker: true });
  const { context } = world;
  check(typeof context.ManagedMediaSource === 'function', 'workers get ManagedMediaSource');
  check(context.ManagedMediaSource.canConstructInDedicatedWorker === true,
        'canConstructInDedicatedWorker follows MediaSource once workers have it');
  const source = new context.ManagedMediaSource();
  source._open();
  world.run();
  check(source.streaming === true, 'a worker source starts streaming');
  const sb = source.addSourceBuffer('video/mp4; codecs="dvh1.05.01"');
  const changes = [];
  sb.addEventListener('bufferedchange', (e) => changes.push(e));
  sb._finish([[0, 60]]);
  world.run();
  check(changes.length === 1 && changes[0].addedRanges.end(0) === 60, 'bufferedchange in a worker');
  check(Object.getPrototypeOf(changes[0].addedRanges) === Object.getPrototypeOf(sb.buffered),
        'event ranges share the native TimeRanges prototype');
  check(source.streaming === true, 'no playhead in a worker: streaming never stops');
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
