// Copyright 2026 Parc contributors.
// Safari's video presentation and fullscreen API for documents presenting
// Safari's identity
// (docs/fairplay-identity.md, docs/fairplay-safari-surface.md). It
// evaluates to a function that Blink calls in the main world, before the
// page's own scripts, with helpers the page never sees (InstallParcSafariScripts
// in fairplay-identity-blink.patch): `fire` dispatches trusted events, and
// `mediaGesture` and `allowPictureInPicture` carry WebKit's lift of the
// gesture rule for an element that had a gesture-started load, play, volume,
// muted, audio track or autoplay change (HTMLMediaElement::
// removeBehaviorRestrictionsAfterFirstUserGesture); without them it works
// with script-made events and transient activation alone. It adds what
// WebKit's
// HTMLVideoElement offers on macOS (Source/WebCore/html/HTMLVideoElement.idl,
// VIDEO_PRESENTATION_MODE, VIDEO_USES_ELEMENT_FULLSCREEN), built on Chromium's standard Picture-in-Picture
// and Fullscreen APIs, which it captures before any page script can replace
// them. So Parc's picture-in-picture panel and fullscreen window present the
// video, and the standard APIs (`document.pictureInPictureElement`,
// `document.fullscreenElement`, their events) always agree with it:
// - `webkitSupportsPresentationMode(mode)`: "inline" always; "fullscreen"
//   once the element has a media player (WebKit creates one when a load
//   starts); "picture-in-picture" once it also has video and Parc offers
//   picture in picture.
// - `webkitPresentationMode`: "fullscreen" while the video is its document's
//   fullscreen element, "picture-in-picture" while it is in picture in
//   picture, "inline" otherwise. As in WebKit, a change this API starts
//   reports picture in picture from the task after the call, and inline at
//   once when leaving it, before the platform has finished.
// - `webkitSetPresentationMode(mode)`: ignored while a change it started is in
//   progress and when the mode is current; "inline" leaves picture in picture
//   or fully exits fullscreen; the others need a user gesture (transient
//   activation, or the lifted rule), except picture in picture while the
//   document already has a picture-in-picture element, and are ignored when
//   unsupported. Element fullscreen itself still needs transient activation,
//   as in WebKit (fullscreenerror otherwise).
// - `webkitpresentationmodechanged` (not bubbling, cancelable) on every mode
//   change, whoever made it, before the standard event of that change
//   (`fullscreenchange`, `enterpictureinpicture`, `leavepictureinpicture`)
//   reaches the page's listeners.
// - `webkitSupportsFullscreen`: as `webkitSupportsPresentationMode("fullscreen")`.
// - `webkitDisplayingFullscreen`: true while the video is its document's
//   fullscreen element or in any mode but inline (picture in picture too).
// - `webkitEnterFullscreen()` (and `webkitEnterFullScreen()`): nothing while
//   displaying fullscreen; InvalidStateError without a user gesture, without
//   fullscreen support or while a change is in progress; otherwise element
//   fullscreen of the video.
// - `webkitExitFullscreen()` (and `webkitExitFullScreen()`): unless a change
//   is in progress, fully exits fullscreen or leaves picture in picture.
// - `webkitendfullscreen` (not bubbling, cancelable) after the
//   webkitpresentationmodechanged of a change from fullscreen to picture in
//   picture. On macOS video fullscreen is element fullscreen, so WebKit fires
//   `webkitbeginfullscreen` never and `webkitendfullscreen` only then.
// tests/FairPlayIdentity/webkit_presentation.mjs runs this exact script.
// Installed at third_party/blink/renderer/bindings/core/v8/parc_webkit_presentation.h.
#ifndef THIRD_PARTY_BLINK_RENDERER_BINDINGS_CORE_V8_PARC_WEBKIT_PRESENTATION_H_
#define THIRD_PARTY_BLINK_RENDERER_BINDINGS_CORE_V8_PARC_WEBKIT_PRESENTATION_H_

namespace blink {

inline constexpr char kParcWebKitPresentationScript[] = R"PARC_WKPM_JS(
(function(native) {
  'use strict';
  const g = globalThis;
  const videoPrototype = g.HTMLVideoElement && g.HTMLVideoElement.prototype;
  if (!videoPrototype || 'webkitSetPresentationMode' in videoPrototype) {
    return;
  }
  const define = Object.defineProperty;
  const describe = Object.getOwnPropertyDescriptor;
  const apply = Reflect.apply;
  const getPrototypeOf = Object.getPrototypeOf;
  const getter = (proto, name) => {
    const descriptor = proto && describe(proto, name);
    return descriptor && descriptor.get;
  };
  const method = (proto, name) => {
    const value = proto && proto[name];
    return typeof value === 'function' ? value : null;
  };
  const NativeEvent = g.Event;
  const NativeDOMException = g.DOMException;
  const NativeWeakMap = g.WeakMap;
  const NativeWeakRef = g.WeakRef;
  const deref = NativeWeakRef && NativeWeakRef.prototype.deref;
  const weakGet = NativeWeakMap.prototype.get;
  const weakSet = NativeWeakMap.prototype.set;
  const promiseThen = Promise.prototype.then;
  const nativeSetTimeout = g.setTimeout;
  const eventTargetPrototype = g.EventTarget && g.EventTarget.prototype;
  const addListener = method(eventTargetPrototype, 'addEventListener');
  const dispatch = method(eventTargetPrototype, 'dispatchEvent');
  const eventPrototype = NativeEvent && NativeEvent.prototype;
  const typeOf = getter(eventPrototype, 'type');
  const composedPath = method(eventPrototype, 'composedPath');
  const nodePrototype = g.Node && g.Node.prototype;
  const getRootNode = method(nodePrototype, 'getRootNode');
  const ownerDocumentOf = getter(nodePrototype, 'ownerDocument');
  const mediaPrototype = g.HTMLMediaElement && g.HTMLMediaElement.prototype;
  const networkStateOf = getter(mediaPrototype, 'networkState');
  const readyStateOf = getter(mediaPrototype, 'readyState');
  const videoWidthOf = getter(videoPrototype, 'videoWidth');
  const videoHeightOf = getter(videoPrototype, 'videoHeight');
  const requestPictureInPicture = method(videoPrototype, 'requestPictureInPicture');
  const requestFullscreen = method(g.Element && g.Element.prototype, 'requestFullscreen');
  const documentPrototype = g.Document && g.Document.prototype;
  const shadowRootPrototype = g.ShadowRoot && g.ShadowRoot.prototype;
  const exitPictureInPicture = method(documentPrototype, 'exitPictureInPicture');
  const exitFullscreen = method(documentPrototype, 'exitFullscreen');
  const documentFullscreenElement = getter(documentPrototype, 'fullscreenElement');
  const shadowFullscreenElement = getter(shadowRootPrototype, 'fullscreenElement');
  const documentPictureInPictureElement = getter(documentPrototype, 'pictureInPictureElement');
  const shadowPictureInPictureElement = getter(shadowRootPrototype, 'pictureInPictureElement');
  const pictureInPictureEnabledOf = getter(documentPrototype, 'pictureInPictureEnabled');
  const helper = (name) =>
      native && typeof native[name] === 'function' ? native[name] : null;
  const nativeFire = helper('fire');
  const mediaGesture = helper('mediaGesture');
  const allowPictureInPicture = helper('allowPictureInPicture');
  const activation = g.navigator && g.navigator.userActivation;
  const isActiveOf = getter(g.UserActivation && g.UserActivation.prototype, 'isActive');
  if (!NativeEvent || !NativeDOMException || !addListener || !dispatch || !typeOf || !getRootNode ||
      !ownerDocumentOf || !networkStateOf || !readyStateOf || !videoWidthOf ||
      !videoHeightOf || !nativeSetTimeout) {
    return;
  }

  const INLINE = 'inline';
  const FULLSCREEN = 'fullscreen';
  const PICTURE_IN_PICTURE = 'picture-in-picture';
  // The events that report a presentation change of a video. Fullscreen
  // changes are composed and always reach the window; picture-in-picture
  // changes aren't, so watched videos hear those themselves. (A listener of
  // the script's for fullscreenchange on a video would count as the page's
  // when Blink decides whether to add webkitfullscreenchange, as WebKit's
  // DocumentFullscreen does.)
  const FULLSCREEN_CHANGES = ['fullscreenchange', 'webkitfullscreenchange'];
  const PICTURE_IN_PICTURE_CHANGES = ['enterpictureinpicture', 'leavepictureinpicture'];
  // Listening for these on a video makes the script watch it.
  const ANNOUNCED = ['webkitpresentationmodechanged', 'webkitbeginfullscreen',
                     'webkitendfullscreen'];

  const then = (promise, fulfilled, rejected) =>
      apply(promiseThen, promise, [fulfilled, rejected]);
  const later = (task) => apply(nativeSetTimeout, g, [task, 0]);
  // HTMLMediaElement::scheduleEvent: trusted, not bubbling, cancelable.
  const fire = (target, type) => (nativeFire ?
      apply(nativeFire, undefined, [target, type]) :
      apply(dispatch, target, [new NativeEvent(type, {bubbles: false, cancelable: true})]));
  function required(count, length, what) {
    if (length < count) {
      throw new TypeError('Failed to execute ' + what + ': ' + count +
          ' argument' + (count > 1 ? 's' : '') + ' required, but only ' +
          length + ' present.');
    }
  }
  // WebIDL's VideoPresentationMode enum.
  function toMode(value, what) {
    const mode = `${value}`;
    if (mode !== INLINE && mode !== FULLSCREEN && mode !== PICTURE_IN_PICTURE) {
      throw new TypeError('Failed to execute ' + what + ": The provided value '" +
          mode + "' is not a valid enum value of type VideoPresentationMode.");
    }
    return mode;
  }
  // Illegal invocation (a TypeError) unless `element` is a video.
  function brand(element) {
    apply(videoWidthOf, element, []);
  }
  function isVideo(value) {
    if (!value || typeof value !== 'object') {
      return false;
    }
    try {
      brand(value);
      return true;
    } catch (error) {
      return false;
    }
  }
  const contains = (list, value) => {
    for (let i = 0; i < list.length; ++i) {
      if (list[i] === value) {
        return true;
      }
    }
    return false;
  };

  // DocumentOrShadowRoot's element for `element`: its shadow root's, or its
  // node document's (a detached element's too), retargeted as the page sees
  // it, so it is `element` itself only when `element` holds the state.
  function scoped(element, ofShadowRoot, ofDocument) {
    if (!ofDocument) {
      return null;
    }
    const root = apply(getRootNode, element, []);
    if (ofShadowRoot) {
      try {
        return apply(ofShadowRoot, root, []);
      } catch (error) {
        // Not a shadow root.
      }
    }
    try {
      return apply(ofDocument, apply(ownerDocumentOf, element, []), []);
    } catch (error) {
      return null;
    }
  }
  const isFullscreenElement = (element) =>
      scoped(element, shadowFullscreenElement, documentFullscreenElement) === element;
  const isPictureInPictureElement = (element) =>
      scoped(element, shadowPictureInPictureElement, documentPictureInPictureElement) === element;
  // WebKit's toPresentationMode(fullscreenMode()) on macOS, where video
  // fullscreen is element fullscreen of the video (VIDEO_USES_ELEMENT_FULLSCREEN).
  function actualMode(element) {
    if (isFullscreenElement(element)) {
      return FULLSCREEN;
    }
    return isPictureInPictureElement(element) ? PICTURE_IN_PICTURE : INLINE;
  }
  function documentHasPictureInPicture(element) {
    try {
      return !!(documentPictureInPictureElement &&
          apply(documentPictureInPictureElement, apply(ownerDocumentOf, element, []), []));
    } catch (error) {
      return false;
    }
  }

  // MediaElementSession::fullscreenPermitted: RequireUserGestureForFullscreen
  // and Document::processingUserGestureForMedia, which is transient activation.
  const userGesture = () => !isActiveOf || !activation || !!apply(isActiveOf, activation, []);
  // ...or the element's lifted rule.
  const fullscreenPermitted = (element) => userGesture() ||
      (!!mediaGesture && !!apply(mediaGesture, undefined, [element]));
  // WebKit creates the media player when a load starts (prepareForLoad); a
  // video that never loaded has none.
  const hasPlayer = (element) => apply(networkStateOf, element, []) !== 0;
  // MediaPlayer::hasVideo: known from metadata.
  const hasVideo = (element) => apply(readyStateOf, element, []) >= 1 &&
      (apply(videoWidthOf, element, []) > 0 || apply(videoHeightOf, element, []) > 0);
  // Whether Parc offers picture in picture to the document at all
  // (WebKit's supportsPictureInPicture()).
  function pictureInPictureAvailable(element) {
    if (!requestPictureInPicture || !exitPictureInPicture) {
      return false;
    }
    try {
      return !pictureInPictureEnabledOf ||
          !!apply(pictureInPictureEnabledOf, apply(ownerDocumentOf, element, []), []);
    } catch (error) {
      return false;
    }
  }
  // HTMLVideoElement::supportsFullscreen on macOS: fullscreen needs a player
  // (and the page's fullscreen API, always on in Parc); picture in picture
  // also needs video.
  function supportsMode(element, mode) {
    if (mode === INLINE) {
      // !MediaElementSession::requiresFullscreenForVideoPlayback: macOS plays
      // inline.
      return true;
    }
    if (!hasPlayer(element)) {
      return false;
    }
    if (mode === FULLSCREEN) {
      return !!requestFullscreen && !!exitFullscreen;
    }
    return pictureInPictureAvailable(element) && hasVideo(element);
  }

  // Per video: `reported` is the mode its last webkitpresentationmodechanged
  // announced; `intent` is a change this API started, until the standard
  // call carrying it settles (WebKit's isChangingVideoFullscreenMode).
  const states = new NativeWeakMap();
  // Videos not inline or changing; held so a document's fullscreenchange
  // (a video that left the tree) still reaches them.
  const active = [];
  // Every watched video, weakly, for fullscreen changes the window sees
  // with a shadow host as their target.
  const watched = [];
  const peek = (element) => apply(weakGet, states, [element]);
  function stateOf(element, reported) {
    let state = peek(element);
    if (!state) {
      state = {reported, intent: null, watched: false};
      apply(weakSet, states, [element, state]);
      watch(element, state);
      retain(element, state);
    }
    return state;
  }
  // WebKit's isChangingVideoFullscreenMode. A picture-in-picture intent that
  // outlives its promise only to cover Chromium's late fullscreen exit
  // doesn't count.
  const changing = (state) => !!(state && state.intent && !state.intent.lingering);
  function effectiveMode(element, state) {
    const intent = state && state.intent;
    if (intent && intent.shown) {
      return intent.mode;
    }
    const mode = actualMode(element);
    return intent && intent.hold && mode === INLINE ? intent.hold : mode;
  }
  function retain(element, state) {
    const busy = state.reported !== INLINE || !!state.intent;
    if (busy && !contains(active, element)) {
      active[active.length] = element;
    } else if (!busy) {
      for (let i = 0; i < active.length; ++i) {
        if (active[i] === element) {
          for (let j = i + 1; j < active.length; ++j) {
            active[j - 1] = active[j];
          }
          active.length -= 1;
          break;
        }
      }
    }
  }
  // HTMLMediaElement::setFullscreenMode: each change of mode fires
  // webkitpresentationmodechanged.
  function announce(element, state) {
    if (state.intent && state.intent.lingering && !isFullscreenElement(element)) {
      state.intent = null;
    }
    const mode = effectiveMode(element, state);
    if (mode !== state.reported) {
      const previous = state.reported;
      state.reported = mode;
      retain(element, state);
      changed(element, previous, mode);
    } else {
      retain(element, state);
    }
  }
  function changed(element, previous, mode) {
    fire(element, 'webkitpresentationmodechanged');
    // HTMLMediaElement::enterFullscreen(PictureInPicture) from standard
    // fullscreen.
    if (previous === FULLSCREEN && mode === PICTURE_IN_PICTURE) {
      fire(element, 'webkitendfullscreen');
    }
  }

  // A change this API starts. `eager` changes (entering picture in picture,
  // or leaving it for inline) report the new mode before the platform
  // finishes, as WebKit's setFullscreenMode does: `afterTask` from the task
  // after the call (enterFullscreen's queued task), otherwise at once
  // (exitFullscreen); the event follows in a task. Others report what the
  // standard API reports. The intent ends when `promise` settles. Until an
  // `afterTask` change shows, the mode it leaves holds (Chromium may leave
  // fullscreen first), so fullscreen to picture in picture is one change.
  function begin(element, state, mode, eager, afterTask, promise) {
    const hold = eager && afterTask ? effectiveMode(element, state) : null;
    // Picture in picture outlasts a fullscreen Chromium hasn't left yet.
    const intent = {mode, shown: false, hold, masksFullscreen: mode === PICTURE_IN_PICTURE};
    state.intent = intent;
    retain(element, state);
    const show = () => {
      if (state.intent === intent) {
        intent.shown = true;
        later(() => announce(element, state));
      }
    };
    if (eager) {
      if (afterTask) {
        later(show);
      } else {
        show();
      }
    }
    const settle = () => {
      if (state.intent === intent) {
        state.intent = null;
        announce(element, state);
      }
    };
    // Picture in picture can be up before Chromium's exit from fullscreen
    // lands; the video keeps reporting the new mode until it does.
    const entered = () => {
      if (state.intent === intent && intent.masksFullscreen &&
          isFullscreenElement(element)) {
        intent.shown = true;
        intent.lingering = true;
        announce(element, state);
        return;
      }
      settle();
    };
    try {
      then(promise, entered, settle);
    } catch (error) {
      // No promise: the call failed at once.
      settle();
    }
    return intent;
  }
  // The standard call's promise, or null if it threw.
  function start(call, target) {
    try {
      return apply(call, target, []);
    } catch (error) {
      return null;
    }
  }
  // HTMLMediaElement::exitFullscreen: element fullscreen exits fully
  // (fullyExitFullscreen), picture in picture ends.
  function leave(element, state, current) {
    const ownerDocument = apply(ownerDocumentOf, element, []);
    if (current === PICTURE_IN_PICTURE) {
      // Leaving picture in picture before Chromium's late exit from
      // fullscreen lands keeps that fullscreen hidden too.
      const lingering = !!(state.intent && state.intent.lingering);
      begin(element, state, INLINE, true, false,
            start(exitPictureInPicture, ownerDocument)).masksFullscreen = lingering;
      return;
    }
    // Chromium's exitFullscreen leaves one level of nested fullscreen.
    let steps = 0;
    const exitStep = () => then(start(exitFullscreen, ownerDocument), () => {
      if (++steps < 8 && apply(documentFullscreenElement, ownerDocument, [])) {
        return exitStep();
      }
      return undefined;
    });
    let promise = null;
    try {
      promise = exitStep();
    } catch (error) {
    }
    begin(element, state, INLINE, false, false, promise);
  }
  // HTMLMediaElement::enterFullscreen(mode).
  function enter(element, state, mode) {
    if (mode === PICTURE_IN_PICTURE) {
      // The lifted rule lets picture in picture go without transient
      // activation, through Chromium's picture-in-picture request token.
      if (allowPictureInPicture && !userGesture() && !documentHasPictureInPicture(element)) {
        apply(allowPictureInPicture, undefined, [element]);
      }
      // Chromium leaves element fullscreen first, as WebKit does.
      begin(element, state, mode, true, true, start(requestPictureInPicture, element));
    } else {
      // Chromium ends picture in picture once the video is fullscreen
      // (HTMLVideoElement::DidEnterFullscreen), as WebKit does.
      begin(element, state, mode, false, false, start(requestFullscreen, element));
    }
  }
  // HTMLVideoElement::setPresentationMode.
  function setPresentationMode(element, state, mode) {
    const current = effectiveMode(element, state);
    if (current === mode) {
      return;
    }
    if (mode === INLINE) {
      if (current !== INLINE || isFullscreenElement(element)) {
        leave(element, state, current);
      }
      return;
    }
    const requiresUserGesture = mode !== PICTURE_IN_PICTURE ||
        !documentHasPictureInPicture(element);
    if ((requiresUserGesture && !fullscreenPermitted(element)) || !supportsMode(element, mode)) {
      return;
    }
    enter(element, state, mode);
  }

  // The mode a video had before a change event the script sees for it
  // first.
  function priorMode(element, type) {
    const now = actualMode(element);
    if (type === 'enterpictureinpicture') {
      return now === PICTURE_IN_PICTURE ? INLINE : now;
    }
    if (type === 'leavepictureinpicture') {
      return now === INLINE ? PICTURE_IN_PICTURE : now;
    }
    if (now === FULLSCREEN) {
      return isPictureInPictureElement(element) ? PICTURE_IN_PICTURE : INLINE;
    }
    return FULLSCREEN;
  }
  function observe(element, type) {
    const state = peek(element) || stateOf(element, priorMode(element, type));
    announce(element, state);
  }
  function revisitActive() {
    const snapshot = [];
    for (let i = 0; i < active.length; ++i) {
      snapshot[i] = active[i];
    }
    for (let i = 0; i < snapshot.length; ++i) {
      announce(snapshot[i], peek(snapshot[i]));
    }
  }
  function revisitWatched() {
    const alive = [];
    let kept = 0;
    for (let i = 0; i < watched.length; ++i) {
      const element = apply(deref, watched[i], []);
      if (element) {
        watched[kept++] = watched[i];
        alive[alive.length] = element;
      }
    }
    watched.length = kept;
    for (let i = 0; i < alive.length; ++i) {
      announce(alive[i], peek(alive[i]));
    }
  }
  // A watched video hears its own change events, so one in a shadow tree
  // (picture-in-picture events aren't composed) or out of the document
  // still reports.
  function watch(element, state) {
    if (state.watched) {
      return;
    }
    state.watched = true;
    if (deref) {
      watched[watched.length] = new NativeWeakRef(element);
    }
    for (let i = 0; i < PICTURE_IN_PICTURE_CHANGES.length; ++i) {
      const type = PICTURE_IN_PICTURE_CHANGES[i];
      apply(addListener, element, [type, () => observe(element, type), true]);
    }
  }
  const known = (element) => peek(element) || stateOf(element, effectiveMode(element, null));

  // HTMLMediaElement::isFullscreen: the document's fullscreen element, or any
  // mode but inline.
  const displaysFullscreen = (element, state) =>
      isFullscreenElement(element) || effectiveMode(element, state) !== INLINE;
  // HTMLVideoElement::webkitEnterFullscreen.
  function webkitEnter(element) {
    const state = peek(element);
    if (displaysFullscreen(element, state)) {
      return;
    }
    if (!fullscreenPermitted(element) || !supportsMode(element, FULLSCREEN) || changing(state)) {
      throw new NativeDOMException('The object is in an invalid state.', 'InvalidStateError');
    }
    enter(element, known(element), FULLSCREEN);
  }
  // HTMLVideoElement::webkitExitFullscreen.
  function webkitExit(element) {
    const state = known(element);
    if (!changing(state) && displaysFullscreen(element, state)) {
      leave(element, state, effectiveMode(element, state));
    }
  }

  const members = {
    webkitSupportsPresentationMode(mode) {
      brand(this);
      required(1, arguments.length,
               "'webkitSupportsPresentationMode' on 'HTMLVideoElement'");
      return supportsMode(this, toMode(mode,
          "'webkitSupportsPresentationMode' on 'HTMLVideoElement'"));
    },
    get webkitPresentationMode() {
      brand(this);
      return effectiveMode(this, peek(this));
    },
    webkitSetPresentationMode(mode) {
      brand(this);
      required(1, arguments.length, "'webkitSetPresentationMode' on 'HTMLVideoElement'");
      const target = toMode(mode, "'webkitSetPresentationMode' on 'HTMLVideoElement'");
      const state = known(this);
      if (!changing(state)) {
        setPresentationMode(this, state, target);
      }
    },
    get webkitSupportsFullscreen() {
      brand(this);
      return supportsMode(this, FULLSCREEN);
    },
    get webkitDisplayingFullscreen() {
      brand(this);
      return displaysFullscreen(this, peek(this));
    },
    webkitEnterFullscreen() {
      brand(this);
      webkitEnter(this);
    },
    webkitExitFullscreen() {
      brand(this);
      webkitExit(this);
    },
    // WebKit keeps the "FullScreen" spellings (ImplementedAs the above).
    webkitEnterFullScreen() {
      brand(this);
      webkitEnter(this);
    },
    webkitExitFullScreen() {
      brand(this);
      webkitExit(this);
    },
    // A listener for the webkit presentation events on a video anywhere
    // (detached, or in a shadow tree the window doesn't see) gets them.
    addEventListener(type, listener, options = undefined) {
      if (typeof type === 'string' && contains(ANNOUNCED, type) && isVideo(this)) {
        known(this);
      }
      return apply(getPrototypeOf(videoPrototype).addEventListener, this, arguments);
    },
  };
  // WebIDL members are enumerable and configurable; operations writable.
  for (const name of ['webkitSupportsFullscreen', 'webkitDisplayingFullscreen',
                      'webkitPresentationMode']) {
    define(videoPrototype, name, {
      get: describe(members, name).get, enumerable: true, configurable: true,
    });
  }
  for (const name of ['webkitEnterFullscreen', 'webkitExitFullscreen',
                      'webkitEnterFullScreen', 'webkitExitFullScreen',
                      'webkitSupportsPresentationMode', 'webkitSetPresentationMode',
                      'addEventListener']) {
    define(videoPrototype, name, {
      value: members[name], writable: true, enumerable: true, configurable: true,
    });
  }

  // Every change event of a video in this window's tree, before the page's
  // listeners; a document's fullscreenchange (its fullscreen video left the
  // tree) revisits the videos that aren't inline, and one whose target is a
  // shadow host the watched videos.
  for (const type of [...FULLSCREEN_CHANGES, ...PICTURE_IN_PICTURE_CHANGES]) {
    try {
      apply(addListener, g, [type, (event) => {
        let target = null;
        try {
          target = composedPath ? apply(composedPath, event, [])[0] : null;
        } catch (error) {
        }
        const eventType = apply(typeOf, event, []);
        if (isVideo(target)) {
          observe(target, eventType);
        }
        revisitActive();
        if (eventType === 'fullscreenchange' || eventType === 'webkitfullscreenchange') {
          revisitWatched();
        }
      }, true]);
    } catch (error) {
    }
  }
})
)PARC_WKPM_JS";

}  // namespace blink

#endif  // THIRD_PARTY_BLINK_RENDERER_BINDINGS_CORE_V8_PARC_WEBKIT_PRESENTATION_H_
