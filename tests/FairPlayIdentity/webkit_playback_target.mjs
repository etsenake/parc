// Runs the AirPlay availability event script from
// Engine/ParcRenderer/parc_webkit_playback_target.h against a model of a
// window's Event and asserts WebKit's WebKitPlaybackTargetAvailabilityEvent
// (WebKitPlaybackTargetAvailabilityEvent.idl, HTMLMediaElement::
// enqueuePlaybackTargetAvailabilityChangedEvent). No browser;
// `node webkit_playback_target.mjs`.
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';

const header = readFileSync(fileURLToPath(new URL(
    '../../Engine/ParcRenderer/parc_webkit_playback_target.h', import.meta.url)), 'utf8');
const match = header.match(/R"PARC_WKPT_JS\(([\s\S]*)\)PARC_WKPT_JS"/);
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
function throwsTypeError(fn) {
  try {
    fn();
  } catch (e) {
    return e instanceof TypeError || e.name === 'TypeError';
  }
  return false;
}

// A window's Event, as Chromium's: type, bubbles and cancelable from the
// dictionary, both false by default.
const context = vm.createContext({});
vm.runInContext(`
  class Event {
    #type; #bubbles; #cancelable;
    constructor(type, init = undefined) {
      if (arguments.length < 1) throw new TypeError('1 argument required');
      this.#type = \`\${type}\`;
      this.#bubbles = !!(init && init.bubbles);
      this.#cancelable = !!(init && init.cancelable);
    }
    get type() { return this.#type; }
    get bubbles() { return this.#bubbles; }
    get cancelable() { return this.#cancelable; }
  }
  globalThis.Event = Event;
`, context);

const hook = vm.runInContext(script, context);
check(typeof hook === 'function', 'the completion value is the hook');
const descriptor = Object.getOwnPropertyDescriptor(
    vm.runInContext('globalThis', context), 'WebKitPlaybackTargetAvailabilityEvent');
check(descriptor && descriptor.writable && descriptor.configurable && !descriptor.enumerable,
      'the interface is a writable, configurable, non-enumerable global');
const Cls = descriptor.value;

const plain = new Cls('custom');
check(plain.availability === 'not-available', 'availability defaults to "not-available"');
check(plain.type === 'custom' && !plain.bubbles && !plain.cancelable, 'an Event of the given type');
check(plain instanceof vm.runInContext('Event', context), 'it is an Event');
check(Object.prototype.toString.call(plain) === '[object WebKitPlaybackTargetAvailabilityEvent]',
      'its class string');
check(new Cls('x', {availability: 'available'}).availability === 'available',
      'availability from the dictionary');
check(new Cls('x', {availability: 7}).availability === '7', 'converted to a DOMString');
check(new Cls('x', null).availability === 'not-available', 'a null dictionary is the default');
check(new Cls('x', {bubbles: true}).bubbles, 'EventInit members reach Event');
check(throwsTypeError(() => new Cls()), 'the type is required');
check(throwsTypeError(() => new Cls('x', 1)), 'a non-object dictionary is a TypeError');
check(throwsTypeError(() => Cls('x')), 'it must be constructed');
const getter = Object.getOwnPropertyDescriptor(Cls.prototype, 'availability');
check(getter && getter.enumerable && typeof getter.get === 'function',
      'availability is an enumerable accessor');
check(throwsTypeError(() => getter.get.call({})), 'availability of another object throws');
check(Object.getOwnPropertyDescriptor(Cls, 'prototype').writable === false,
      'the prototype is not writable');

for (const [available, value] of [[true, 'available'], [false, 'not-available']]) {
  const event = hook(available);
  check(event instanceof Cls && event.type === 'webkitplaybacktargetavailabilitychanged',
        'the hook makes the element\'s event');
  check(event.availability === value, `the hook's event says "${value}"`);
  check(!event.bubbles && !event.cancelable, 'it neither bubbles nor cancels');
}

// A page's getters on Object.prototype never run for the hook's event.
let touched = 0;
vm.runInContext(`Object.defineProperty(Object.prototype, 'bubbles', {
  get() { globalThis.touched = (globalThis.touched || 0) + 1; return true; },
  configurable: true});`, context);
const guarded = hook(true);
touched = vm.runInContext('globalThis.touched || 0', context);
check(touched === 0 && !guarded.bubbles, 'the hook reads nothing from Object.prototype');
vm.runInContext('delete Object.prototype.bubbles;', context);

// Nor does a page changing the class's parent.
vm.runInContext(`Object.setPrototypeOf(WebKitPlaybackTargetAvailabilityEvent,
    function() { return new Event('click', {bubbles: true}); });`, context);
const reparented = hook(true);
check(reparented instanceof Cls && reparented.type === 'webkitplaybacktargetavailabilitychanged' &&
      reparented.availability === 'available' && !reparented.bubbles,
      'the hook\'s event ignores a replaced parent class');

// WebIDL converts the type before the dictionary.
let order = '';
try {
  new Cls({toString() { order += 'type'; throw new RangeError('type'); }}, 1);
} catch (e) {
  order += e instanceof RangeError || e.name === 'RangeError' ? ':range' : ':other';
}
check(order === 'type:range', 'the type converts first');

// A page replacing the global keeps the hook working with the real class.
vm.runInContext('globalThis.WebKitPlaybackTargetAvailabilityEvent = null;', context);
check(hook(true) instanceof Cls, 'the hook keeps the real class');

// A document taking over the context already has the interface.
const second = vm.createContext({});
vm.runInContext('globalThis.Event = class Event {}; globalThis.WebKitPlaybackTargetAvailabilityEvent = 1;', second);
check(vm.runInContext(script, second) === undefined, 'an existing interface is kept, no hook');

console.log(`webkit playback target: ${checks} checks passed`);
