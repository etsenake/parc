// Copyright 2026 Parc contributors.
// Safari's AirPlay availability event for documents presenting Safari's
// identity (docs/fairplay-safari-surface.md, Engine/ParcNative/
// fairplay_chromium/NATIVE_HLS.md "AirPlay"). WebKit queues a
// WebKitPlaybackTargetAvailabilityEvent named
// `webkitplaybacktargetavailabilitychanged` at a media element whose
// availability is "available" when AirPlay devices are nearby and the element
// doesn't disable wireless playback, "not-available" otherwise
// (HTMLMediaElement::enqueuePlaybackTargetAvailabilityChangedEvent). Players
// feature-detect `window.WebKitPlaybackTargetAvailabilityEvent` before they
// show an AirPlay button.
//
// The interface is a class of kParcWebKitPlaybackTargetScript, which the main
// world runs before the page's scripts (InstallParcSafariScripts in
// fairplay-identity-blink.patch). Its completion value is a hook,
// (available) => event, which HTMLMediaElement::SetParcPlaybackTargetEventHook
// keeps in a private property of the main world's global object, out of every
// page script's reach. The media element queues the event the hook returns,
// so it is trusted.
// tests/FairPlayIdentity/webkit_playback_target.mjs runs this exact script.
// Installed at third_party/blink/renderer/bindings/core/v8/parc_webkit_playback_target.h.
#ifndef THIRD_PARTY_BLINK_RENDERER_BINDINGS_CORE_V8_PARC_WEBKIT_PLAYBACK_TARGET_H_
#define THIRD_PARTY_BLINK_RENDERER_BINDINGS_CORE_V8_PARC_WEBKIT_PLAYBACK_TARGET_H_

namespace blink {

inline constexpr char kParcWebKitPlaybackTargetScript[] = R"PARC_WKPT_JS(
(function() {
  'use strict';
  const g = globalThis;
  const NativeEvent = g.Event;
  if (typeof NativeEvent !== 'function' ||
      'WebKitPlaybackTargetAvailabilityEvent' in g) {
    return undefined;
  }
  const define = Object.defineProperty;
  const NativeWeakMap = g.WeakMap;
  const weakMapGet = NativeWeakMap.prototype.get;
  const weakMapSet = NativeWeakMap.prototype.set;
  const weakMapHas = NativeWeakMap.prototype.has;
  const apply = Reflect.apply;
  const construct = Reflect.construct;
  const availabilities = new NativeWeakMap();
  const NAME = 'WebKitPlaybackTargetAvailabilityEvent';

  // WebKit's IDL: constructor([AtomString] DOMString type, optional
  // WebKitPlaybackTargetAvailabilityEventInit eventInitDict = {}), whose
  // availability (a DOMString) defaults to "not-available".
  class WebKitPlaybackTargetAvailabilityEvent extends NativeEvent {
    constructor(type, eventInitDict = undefined) {
      if (arguments.length < 1) {
        throw new TypeError("Failed to construct '" + NAME +
            "': 1 argument required, but only 0 present.");
      }
      const typeString = `${type}`;
      if (eventInitDict !== undefined && eventInitDict !== null &&
          typeof eventInitDict !== 'object' && typeof eventInitDict !== 'function') {
        throw new TypeError("Failed to construct '" + NAME +
            "': The provided value is not of type '" + NAME + "Init'.");
      }
      const init = eventInitDict === null ? undefined : eventInitDict;
      super(typeString, init);
      const value = init === undefined ? undefined : init.availability;
      apply(weakMapSet, availabilities,
            [this, value === undefined ? 'not-available' : `${value}`]);
    }
    get availability() {
      if (!apply(weakMapHas, availabilities, [this])) {
        throw new TypeError('Illegal invocation');
      }
      return apply(weakMapGet, availabilities, [this]);
    }
  }
  const prototype = WebKitPlaybackTargetAvailabilityEvent.prototype;
  define(prototype, 'availability', {enumerable: true});
  define(prototype, Symbol.toStringTag, {value: NAME, configurable: true});
  define(WebKitPlaybackTargetAvailabilityEvent, 'prototype', {writable: false});
  define(g, NAME, {value: WebKitPlaybackTargetAvailabilityEvent, writable: true,
                   enumerable: false, configurable: true});
  // The media element's event: not bubbling, not cancelable, as WebKit's
  // WebKitPlaybackTargetAvailabilityEvent::create makes it. Made from the
  // captured Event and a dictionary with no prototype, so nothing a page
  // changed (the class's parent, Object.prototype) takes part.
  return (available) => {
    const event = construct(NativeEvent, [
      'webkitplaybacktargetavailabilitychanged',
      {__proto__: null, bubbles: false, cancelable: false, composed: false},
    ], WebKitPlaybackTargetAvailabilityEvent);
    apply(weakMapSet, availabilities,
          [event, available ? 'available' : 'not-available']);
    return event;
  };
})()
)PARC_WKPT_JS";

}  // namespace blink

#endif  // THIRD_PARTY_BLINK_RENDERER_BINDINGS_CORE_V8_PARC_WEBKIT_PLAYBACK_TARGET_H_
