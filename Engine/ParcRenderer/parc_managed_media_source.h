// Copyright 2026 Parc contributors.
// ManagedMediaSource for documents presenting Safari's identity
// (docs/fairplay-identity.md). Apple TV+ plays through Safari's
// ManagedMediaSource, which Chromium doesn't have. This script, run in the main
// world before the page's own scripts, adds it on top of Chromium's
// MediaSource: a MediaSource subclass with `streaming`, `startstreaming` /
// `endstreaming` and their handler attributes; SourceBuffers it creates are
// ManagedSourceBuffers that fire `bufferedchange` (a BufferedChangeEvent with
// addedRanges and removedRanges) whenever their buffered ranges change; static
// isTypeSupported; attachment through `src` or `<source>` with an object URL
// or through `srcObject`, which Chromium accepts only for MediaStreams and so
// is mapped to an object URL. `streaming` follows WebKit's managed policy
// (ManagedMediaSource::monitorSourceBuffers): true while the next 10 s aren't
// buffered, false once the next 30 s are (capped at the duration once the
// source has ended), changing at once with its event queued as a task.
// Dedicated workers of such
// documents get it too, where it attaches through MediaSource's `handle`.
// tests/FairPlayIdentity/managed_media_source.mjs runs this exact script
// against a model of the media APIs.
// Installed at third_party/blink/renderer/bindings/core/v8/parc_managed_media_source.h.
#ifndef THIRD_PARTY_BLINK_RENDERER_BINDINGS_CORE_V8_PARC_MANAGED_MEDIA_SOURCE_H_
#define THIRD_PARTY_BLINK_RENDERER_BINDINGS_CORE_V8_PARC_MANAGED_MEDIA_SOURCE_H_

namespace blink {

inline constexpr char kParcManagedMediaSourceScript[] = R"PARC_MMS_JS(
(() => {
  'use strict';
  const g = globalThis;
  if (typeof g.MediaSource !== 'function' || typeof g.SourceBuffer !== 'function' ||
      'ManagedMediaSource' in g) {
    return;
  }
  const NativeMediaSource = g.MediaSource;
  const NativeSourceBuffer = g.SourceBuffer;
  // Workers have TimeRanges objects but no TimeRanges interface; its
  // prototype is then taken from the first buffered ranges seen.
  let timeRangesPrototype = typeof g.TimeRanges === 'function' ? g.TimeRanges.prototype : null;
  const NativeEvent = g.Event;
  const NativeWeakRef = g.WeakRef;
  const define = Object.defineProperty;
  const describe = Object.getOwnPropertyDescriptor;
  const setPrototype = Object.setPrototypeOf;
  const createObjectURL = g.URL && g.URL.createObjectURL;
  const revokeObjectURL = g.URL && g.URL.revokeObjectURL;
  // WebKit's ManagedMediaSource thresholds and MediaSourcePrivate's gap
  // tolerances: a gap shorter than the tolerance counts as buffered.
  const LOW_SECONDS = 10;
  const HIGH_SECONDS = 30;
  const START_GAP_SECONDS = 1;
  const GAP_SECONDS = 0.125;
  const AUDIO_GAP_SECONDS = 0.25;
  const POLL_MS = 1000;
  const MEDIA_EVENTS = ['timeupdate', 'seeking', 'seeked', 'waiting', 'playing', 'emptied'];
  const mediaPrototype = g.HTMLMediaElement && g.HTMLMediaElement.prototype;
  const nativeSrc = mediaPrototype && describe(mediaPrototype, 'src');
  const nativeCurrentSrc = mediaPrototype && describe(mediaPrototype, 'currentSrc');
  const readNative = (descriptor, target) =>
      descriptor && descriptor.get ? descriptor.get.call(target) : '';

  const sources = new WeakMap();
  const buffers = new WeakMap();
  const events = new WeakMap();
  const handlers = new WeakMap();
  const urls = new Map();

  function illegal() {
    throw new TypeError('Illegal constructor');
  }
  function isMedia(element) {
    return !!(element && g.HTMLMediaElement && element instanceof g.HTMLMediaElement);
  }
  function isSource(element) {
    return !!(element && g.HTMLSourceElement && element instanceof g.HTMLSourceElement);
  }

  // TimeRanges objects for BufferedChangeEvent. Chromium's TimeRanges has no
  // constructor, so these inherit its prototype and carry their own values.
  function ranges(list) {
    const value = Object.create(timeRangesPrototype || Object.prototype);
    const bound = (index) => {
      if (!(index >= 0 && index < list.length)) {
        throw new DOMException('The index provided (' + index +
            ') is greater than or equal to the maximum bound (' +
            list.length + ').', 'IndexSizeError');
      }
      return index >>> 0;
    };
    define(value, 'length', {value: list.length});
    define(value, 'start', {value: function start(index) { return list[bound(index)][0]; }});
    define(value, 'end', {value: function end(index) { return list[bound(index)][1]; }});
    return value;
  }

  function snapshot(timeRanges) {
    const list = [];
    for (let i = 0; i < timeRanges.length; ++i) {
      list.push([timeRanges.start(i), timeRanges.end(i)]);
    }
    return list;
  }

  // a minus b, both sorted lists of disjoint [start, end) pairs.
  function subtract(a, b) {
    const out = [];
    for (const [start, end] of a) {
      let cursor = start;
      for (const [bStart, bEnd] of b) {
        if (bEnd <= cursor || bStart >= end) {
          continue;
        }
        if (bStart > cursor) {
          out.push([cursor, Math.min(bStart, end)]);
        }
        cursor = Math.max(cursor, bEnd);
        if (cursor >= end) {
          break;
        }
      }
      if (cursor < end) {
        out.push([cursor, end]);
      }
    }
    return out;
  }

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
        if (typeof handler === 'function' &&
            handler.call(this, event) === false) {
          event.preventDefault();
        }
      };
      map.set(type, entry);
      target.addEventListener(type, entry.listener);
    }
    entry.handler = typeof value === 'function' ||
        (typeof value === 'object' && value !== null) ? value : null;
  }

  class BufferedChangeEvent extends NativeEvent {
    constructor(type, init) {
      super(type, init);
      const options = init || {};
      events.set(this, {
        added: options.addedRanges || ranges([]),
        removed: options.removedRanges || ranges([]),
      });
    }
    get addedRanges() { return events.get(this).added; }
    get removedRanges() { return events.get(this).removed; }
  }

  // Whether a SourceBuffer of this type carries audio, which widens the gap
  // tolerance where its ranges cover the time.
  function carriesAudio(type) {
    const value = String(type);
    return /^\s*audio\//i.test(value) ||
        /(^|[\s,"'=])(mp4a|ac-3|ec-3|ec\+3|ac-4|dts[cehlx]|mh[am]1|opus|flac|vorbis|alac|mp3|[if]pcm)([.,"'\s]|$)/i.test(
            value.slice(value.indexOf(';') + 1));
  }

  // Replaces a SourceBuffer member in place, keeping its attributes, so
  // ManagedSourceBuffer.prototype keeps only the members WebKit gives it.
  function wrapMember(name, wrap) {
    const descriptor = describe(NativeSourceBuffer.prototype, name);
    if (!descriptor) {
      return;
    }
    define(NativeSourceBuffer.prototype, name, wrap(descriptor));
  }
  wrapMember('changeType', (descriptor) => ({
    // A method definition, so not constructible, like the native one.
    value: {changeType(type) {
      const result = descriptor.value.apply(this, arguments);
      const state = buffers.get(this);
      if (state) {
        state.audio = carriesAudio(type);
      }
      return result;
    }}.changeType,
    writable: descriptor.writable, enumerable: descriptor.enumerable,
    configurable: descriptor.configurable,
  }));

  class ManagedSourceBuffer extends NativeSourceBuffer {
    constructor() { illegal(); }
    get onbufferedchange() { return handlerOf(this, 'bufferedchange'); }
    set onbufferedchange(value) { setHandler(this, 'bufferedchange', value); }
  }

  // Compares a SourceBuffer's ranges with the last ones reported and queues a
  // bufferedchange task for the difference, as WebKit does. Called after
  // every append or removal and on each poll, which catches changes made
  // without one (end of stream, garbage collection under memory pressure).
  function bufferedChanged(sourceBuffer) {
    const state = buffers.get(sourceBuffer);
    if (!state) {
      return;
    }
    let now;
    try {
      const buffered = sourceBuffer.buffered;
      if (!timeRangesPrototype) {
        timeRangesPrototype = Object.getPrototypeOf(buffered);
      }
      now = snapshot(buffered);
    } catch (e) {
      return;
    }
    const added = subtract(now, state.ranges);
    const removed = subtract(state.ranges, now);
    state.ranges = now;
    if (added.length || removed.length) {
      g.setTimeout(() => {
        sourceBuffer.dispatchEvent(new BufferedChangeEvent('bufferedchange', {
          addedRanges: ranges(added),
          removedRanges: ranges(removed),
        }));
      }, 0);
    }
  }

  // The media element playing a source: the one it was attached to, the
  // parent of the <source> that named it, or one showing its object URL.
  function elementOf(source, state) {
    let element = state.element;
    if (isSource(element)) {
      element = element.parentElement;
    }
    if (!isMedia(element) && state.url && g.document && g.document.querySelectorAll) {
      for (const candidate of g.document.querySelectorAll('video, audio')) {
        if (readNative(nativeCurrentSrc, candidate) === state.url ||
            readNative(nativeSrc, candidate) === state.url) {
          element = candidate;
          break;
        }
      }
    }
    if (!isMedia(element)) {
      return null;
    }
    watch(source, state, element);
    return element;
  }

  // Listens to the element's playback events until the source closes or is
  // collected, so an element that plays one source after another doesn't
  // collect listeners.
  function watch(source, state, element) {
    if (state.watched.has(element)) {
      return;
    }
    state.watched.add(element);
    const ref = new NativeWeakRef(source);
    const stop = () => {
      for (const type of MEDIA_EVENTS) {
        element.removeEventListener(type, update);
      }
    };
    const update = () => {
      const live = ref.deref();
      if (live) {
        evaluate(live);
      } else {
        stop();
      }
    };
    for (const type of MEDIA_EVENTS) {
      element.addEventListener(type, update);
    }
    state.unwatch.push(stop);
  }

  function remember(source, element) {
    const state = sources.get(source);
    if (state && element) {
      state.element = element;
      elementOf(source, state);
    }
  }

  // a ∩ b, both sorted lists of disjoint [start, end] pairs.
  function intersect(a, b) {
    const out = [];
    for (let i = 0, j = 0; i < a.length && j < b.length;) {
      const start = Math.max(a[i][0], b[j][0]);
      const end = Math.min(a[i][1], b[j][1]);
      if (start < end) {
        out.push([start, end]);
      }
      if (a[i][1] < b[j][1]) {
        ++i;
      } else {
        ++j;
      }
    }
    return out;
  }

  // The media source's buffered ranges as WebKit's MediaSourcePrivate has
  // them: the intersection of its active SourceBuffers' ranges, each one's
  // last range reaching the highest end time once the source has ended, and
  // the union of the ranges of those carrying audio.
  function sourceBuffered(source, ended) {
    const list = source.activeSourceBuffers;
    const all = [];
    let highest = 0;
    for (let i = 0; i < list.length; ++i) {
      let ranges;
      try {
        ranges = snapshot(list[i].buffered);
      } catch (e) {
        ranges = [];
      }
      all.push({ranges, audio: !!(buffers.get(list[i]) || {}).audio});
      if (ranges.length) {
        highest = Math.max(highest, ranges[ranges.length - 1][1]);
      }
    }
    let buffered = null;
    const audio = [];
    for (const entry of all) {
      const ranges = entry.ranges;
      if (entry.audio) {
        audio.push(...ranges);
      }
      if (ended && ranges.length) {
        ranges[ranges.length - 1] = [ranges[ranges.length - 1][0], highest];
      }
      buffered = buffered ? intersect(buffered, ranges) : ranges;
    }
    return {buffered: buffered || [], audio};
  }

  // MediaSourcePrivate::gapToleranceAtTime.
  function tolerance(time, ranges) {
    const buffered = ranges.buffered;
    if (time >= 0 && time < START_GAP_SECONDS && buffered.length &&
        buffered[0][0] <= START_GAP_SECONDS && time < buffered[0][0]) {
      return START_GAP_SECONDS;
    }
    return ranges.audio.some(([start, end]) => time >= start && time <= end)
        ? AUDIO_GAP_SECONDS : GAP_SECONDS;
  }

  function nearest(list, time) {
    let closest = NaN;
    let delta = Infinity;
    for (const [start, end] of list) {
      if (time >= start && time <= end) {
        return time;
      }
      for (const edge of [start, end]) {
        if (Math.abs(edge - time) < delta) {
          delta = Math.abs(edge - time);
          closest = edge;
        }
      }
    }
    return closest;
  }

  // MediaSourcePrivate::isBuffered: [from, to] is buffered, give or take the
  // gap tolerance at its ends and at each gap inside it.
  function isBuffered(ranges, from, to) {
    const inside = intersect(ranges.buffered, [[from, to]]);
    if (!inside.length ||
        !(Math.abs(nearest(inside, from) - from) <= tolerance(from, ranges)) ||
        !(Math.abs(nearest(inside, to) - to) <= tolerance(to, ranges))) {
      return false;
    }
    for (let i = 1; i < inside.length; ++i) {
      if (inside[i][0] - inside[i - 1][1] > tolerance(inside[i - 1][1], ranges)) {
        return false;
      }
    }
    return true;
  }

  // WebKit's ManagedMediaSource::setStreaming: the attribute changes at once
  // and its event follows as a task.
  function setStreaming(source, state, streaming) {
    if (state.streaming === streaming) {
      return;
    }
    state.streaming = streaming;
    g.setTimeout(() => {
      source.dispatchEvent(new NativeEvent(streaming ? 'startstreaming' : 'endstreaming'));
    }, 0);
  }

  // WebKit's ManagedMediaSource::monitorSourceBuffers, run whenever the
  // playback position, the buffered ranges or the source's state change.
  // Without a known playback position the source may start streaming but
  // never stops, so a player that obeys it can't stall.
  function evaluate(source) {
    const state = sources.get(source);
    if (!state) {
      return;
    }
    if (source.readyState === 'closed') {
      setStreaming(source, state, false);
      return;
    }
    if (!source.activeSourceBuffers.length) {
      setStreaming(source, state, true);
      return;
    }
    const element = elementOf(source, state);
    const time = element ? element.currentTime : 0;
    const ended = source.readyState === 'ended';
    const duration = source.duration;
    if (element && ended && time >= duration) {
      setStreaming(source, state, false);
      return;
    }
    const limitAhead = (upper) => ended ? Math.min(duration, time + upper) : time + upper;
    const ranges = sourceBuffered(source, ended);
    if (!state.streaming) {
      if (!isBuffered(ranges, time, Math.max(time, limitAhead(LOW_SECONDS)))) {
        setStreaming(source, state, true);
      }
      return;
    }
    if (!element) {
      return;
    }
    const ahead = limitAhead(HIGH_SECONDS);
    if (time >= ahead || isBuffered(ranges, time, ahead)) {
      setStreaming(source, state, false);
    }
  }

  // The poll holds the source weakly, so a player torn down without detaching
  // can still be collected; it ends with the source or when it closes.
  function opened(source) {
    const state = sources.get(source);
    if (!state) {
      return;
    }
    if (state.revokeOnOpen && state.url && revokeObjectURL) {
      revokeObjectURL.call(g.URL, state.url);
      state.revokeOnOpen = false;
    }
    if (!state.timer) {
      const ref = new NativeWeakRef(source);
      const timer = g.setInterval(() => {
        const live = ref.deref();
        if (!live) {
          g.clearInterval(timer);
          return;
        }
        for (let i = 0; i < live.sourceBuffers.length; ++i) {
          bufferedChanged(live.sourceBuffers[i]);
        }
        evaluate(live);
      }, POLL_MS);
      state.timer = timer;
    }
    evaluate(source);
  }

  function closed(source) {
    const state = sources.get(source);
    if (!state) {
      return;
    }
    if (state.timer) {
      g.clearInterval(state.timer);
      state.timer = 0;
    }
    for (const stop of state.unwatch.splice(0)) {
      stop();
    }
    state.watched = new WeakSet();
    evaluate(source);
  }

  class ManagedMediaSource extends NativeMediaSource {
    constructor() {
      super();
      sources.set(this, {
        streaming: false, element: null, url: '', revokeOnOpen: false,
        timer: 0, watched: new WeakSet(), unwatch: [],
      });
      // Capturing listeners added first run before any of the page's, so
      // `streaming` is current when the page hears these events, as in
      // WebKit, which updates it as the state changes.
      this.addEventListener('sourceopen', () => opened(this), true);
      this.addEventListener('sourceended', () => evaluate(this), true);
      this.addEventListener('sourceclose', () => closed(this), true);
    }
    get streaming() {
      const state = sources.get(this);
      if (!state) {
        throw new TypeError('Illegal invocation');
      }
      return state.streaming;
    }
    get onstartstreaming() { return handlerOf(this, 'startstreaming'); }
    set onstartstreaming(value) { setHandler(this, 'startstreaming', value); }
    get onendstreaming() { return handlerOf(this, 'endstreaming'); }
    set onendstreaming(value) { setHandler(this, 'endstreaming', value); }
    addSourceBuffer(type) {
      const sourceBuffer = super.addSourceBuffer(type);
      setPrototype(sourceBuffer, ManagedSourceBuffer.prototype);
      buffers.set(sourceBuffer, {ranges: [], audio: carriesAudio(type)});
      const ref = new NativeWeakRef(this);
      const update = () => {
        const live = ref.deref();
        if (live) {
          evaluate(live);
        }
      };
      // WebKit re-evaluates as an append or removal completes, before
      // `update` and `updateend` reach the page.
      sourceBuffer.addEventListener('update', update, true);
      sourceBuffer.addEventListener('updateend', () => {
        bufferedChanged(sourceBuffer);
        update();
      }, true);
      return sourceBuffer;
    }
    static isTypeSupported(type) {
      return NativeMediaSource.isTypeSupported(type);
    }
    // Dedicated workers of a Safari-identity document get this script too.
    static get canConstructInDedicatedWorker() {
      return NativeMediaSource.canConstructInDedicatedWorker === true;
    }
  }

  // Interface objects and members look like the WebIDL ones: interfaces are
  // writable, configurable and not enumerable; members are enumerable.
  for (const [name, value] of [['ManagedMediaSource', ManagedMediaSource],
                               ['ManagedSourceBuffer', ManagedSourceBuffer],
                               ['BufferedChangeEvent', BufferedChangeEvent]]) {
    for (const key of Object.getOwnPropertyNames(value.prototype)) {
      if (key !== 'constructor') {
        define(value.prototype, key, {enumerable: true});
      }
    }
    define(value.prototype, Symbol.toStringTag,
           {value: name, configurable: true});
    define(g, name, {value, writable: true, configurable: true});
  }
  define(ManagedMediaSource, 'canConstructInDedicatedWorker', {enumerable: true});

  // Object URLs of managed sources, so `src` finds the element that plays one.
  function createObjectURLNative(object) {
    return createObjectURL.call(g.URL, object);
  }
  if (createObjectURL) {
    define(g.URL, 'createObjectURL', {
      value: function createObjectURL(object) {
        const url = createObjectURLNative(object);
        if (sources.has(object)) {
          sources.get(object).url = url;
          urls.set(url, new NativeWeakRef(object));
        }
        return url;
      },
      writable: true, configurable: true, enumerable: true,
    });
  }
  function sourceForURL(value) {
    const key = String(value);
    const ref = urls.get(key);
    const source = ref && ref.deref();
    if (ref && !source) {
      urls.delete(key);
    }
    return source || null;
  }

  // src set through the property or through setAttribute, on a media element
  // or on a <source> inside one.
  function noteSrc(element, value) {
    const source = sourceForURL(value);
    // A source already open on another element can't attach here.
    if (source && source.readyState === 'closed') {
      remember(source, element);
    }
  }
  function wrapSrc(prototype) {
    const descriptor = prototype && describe(prototype, 'src');
    if (!descriptor || !descriptor.set) {
      return;
    }
    define(prototype, 'src', {
      get: descriptor.get,
      set: function(value) {
        descriptor.set.call(this, value);
        noteSrc(this, value);
      },
      enumerable: descriptor.enumerable, configurable: true,
    });
  }
  wrapSrc(g.HTMLMediaElement && g.HTMLMediaElement.prototype);
  wrapSrc(g.HTMLSourceElement && g.HTMLSourceElement.prototype);
  function wrapSetAttribute(prototype) {
    const descriptor = prototype && describe(g.Element.prototype, 'setAttribute');
    if (!descriptor || typeof descriptor.value !== 'function') {
      return;
    }
    const nativeSetAttribute = descriptor.value;
    define(prototype, 'setAttribute', {
      value: function setAttribute(name, value) {
        const result = nativeSetAttribute.apply(this, arguments);
        if (typeof name === 'string' && name.length === 3 &&
            name.toLowerCase() === 'src') {
          noteSrc(this, value);
        }
        return result;
      },
      writable: true, configurable: true, enumerable: descriptor.enumerable,
    });
  }
  if (g.Element) {
    wrapSetAttribute(g.HTMLMediaElement && g.HTMLMediaElement.prototype);
    wrapSetAttribute(g.HTMLSourceElement && g.HTMLSourceElement.prototype);
  }

  // Safari plays a ManagedMediaSource assigned to srcObject; Chromium's
  // srcObject takes only MediaStreams, so it is played through an object URL.
  // While that URL is the element's, srcObject reports the source and src and
  // currentSrc report nothing, as in Safari; load() attaches it again.
  const media = g.HTMLMediaElement && g.HTMLMediaElement.prototype;
  const srcObject = media && describe(media, 'srcObject');
  const src = media && describe(media, 'src');
  const currentSrc = media && describe(media, 'currentSrc');
  const loadDescriptor = media && describe(media, 'load');
  if (srcObject && srcObject.get && srcObject.set && src && src.get && src.set &&
      createObjectURL) {
    const assigned = new WeakMap();
    const managedEntry = (target) => {
      const entry = assigned.get(target);
      return entry && src.get.call(target) === entry.url ? entry : null;
    };
    const attach = (target, entry) => {
      const state = sources.get(entry.source);
      if (entry.url && revokeObjectURL) {
        revokeObjectURL.call(g.URL, entry.url);
      }
      entry.url = createObjectURLNative(entry.source);
      state.url = entry.url;
      state.revokeOnOpen = true;
      src.set.call(target, entry.url);
      // A source already open on another element can't attach here; keep
      // following the element that plays it.
      if (entry.source.readyState === 'closed') {
        remember(entry.source, target);
      }
    };
    define(media, 'srcObject', {
      get: function() {
        const entry = managedEntry(this);
        return entry ? entry.source : srcObject.get.call(this);
      },
      set: function(value) {
        const previous = assigned.get(this);
        if (value instanceof ManagedMediaSource) {
          const current = previous && managedEntry(this) === previous;
          const entry = {
            source: value, url: previous ? previous.url : '',
            originalSrc: current ? previous.originalSrc : this.getAttribute('src'),
          };
          srcObject.set.call(this, null);
          assigned.set(this, entry);
          attach(this, entry);
          return;
        }
        if (previous) {
          assigned.delete(this);
          if (src.get.call(this) === previous.url) {
            if (previous.originalSrc === null) {
              this.removeAttribute('src');
            } else {
              src.set.call(this, previous.originalSrc);
            }
          }
          if (revokeObjectURL) {
            revokeObjectURL.call(g.URL, previous.url);
          }
        }
        srcObject.set.call(this, value);
      },
      enumerable: srcObject.enumerable, configurable: true,
    });
    define(media, 'src', {
      get: function() {
        return managedEntry(this) ? '' : src.get.call(this);
      },
      set: describe(media, 'src').set,
      enumerable: src.enumerable, configurable: true,
    });
    if (currentSrc && currentSrc.get) {
      define(media, 'currentSrc', {
        get: function() {
          return managedEntry(this) ? '' : currentSrc.get.call(this);
        },
        enumerable: currentSrc.enumerable, configurable: true,
      });
    }
    if (loadDescriptor && typeof loadDescriptor.value === 'function') {
      define(media, 'load', {
        value: function load() {
          const entry = managedEntry(this);
          if (entry) {
            attach(this, entry);
            return;
          }
          return loadDescriptor.value.apply(this, arguments);
        },
        writable: true, configurable: true, enumerable: loadDescriptor.enumerable,
      });
    }
  }
})();
)PARC_MMS_JS";

}  // namespace blink

#endif  // THIRD_PARTY_BLINK_RENDERER_BINDINGS_CORE_V8_PARC_MANAGED_MEDIA_SOURCE_H_
