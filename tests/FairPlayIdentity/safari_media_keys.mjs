import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';

const header = readFileSync(fileURLToPath(new URL(
    '../../Engine/ParcRenderer/parc_safari_media_keys.h', import.meta.url)), 'utf8');
const match = header.match(/R"PARC_SMK_JS\(([\s\S]*)\)PARC_SMK_JS"/);
if (!match) throw new Error('script not found in header');
const script = match[1];
if (/[^\x00-\x7f]/.test(script)) throw new Error('script must be ASCII');

let checks = 0;
function check(condition, message) {
  ++checks;
  if (!condition) {
    console.error('FAIL: ' + message);
    process.exit(1);
  }
}

function secureWindow() {
  const context = vm.createContext({});
  vm.runInContext(`
    class MediaKeys {
      createSession() { return 'session'; }
      setServerCertificate() { return Promise.resolve(true); }
      getStatusForPolicy() { return Promise.reject(new Error('NotSupportedError')); }
    }
    globalThis.MediaKeys = MediaKeys;
    globalThis.mediaKeys = new MediaKeys();
  `, context);
  return context;
}

{
  const window = secureWindow();
  check(vm.runInContext(`'getStatusForPolicy' in mediaKeys`, window),
        'the model starts with Chromium\'s getStatusForPolicy');
  vm.runInContext(script, window);
  check(!vm.runInContext(`'getStatusForPolicy' in mediaKeys`, window),
        'a MediaKeys instance has no getStatusForPolicy');
  check(vm.runInContext(`!MediaKeys.prototype.getStatusForPolicy`, window),
        'MediaKeys.prototype has no getStatusForPolicy');
  check(vm.runInContext(`typeof mediaKeys.getStatusForPolicy`, window) === 'undefined',
        'mediaKeys.getStatusForPolicy is undefined');
  check(vm.runInContext(`(() => {
          try { mediaKeys.getStatusForPolicy({ minHdcpVersion: '1.4' }); return 'called'; }
          catch (error) { return error.name; }
        })()`, window) === 'TypeError',
        'calling it is a TypeError, as in Safari');
  check(vm.runInContext(`mediaKeys.createSession() === 'session' &&
                         typeof mediaKeys.setServerCertificate === 'function'`, window),
        'every other MediaKeys member stays');
  vm.runInContext(script, window);
  check(!vm.runInContext(`'getStatusForPolicy' in MediaKeys.prototype`, window),
        'running it twice is harmless');
}

{
  const window = vm.createContext({});
  vm.runInContext(script, window);
  check(vm.runInContext(`typeof MediaKeys`, window) === 'undefined',
        'without MediaKeys it does nothing and doesn\'t throw');
}

{
  const window = secureWindow();
  vm.runInContext(`Object.defineProperty(MediaKeys.prototype, 'getStatusForPolicy',
                     { configurable: false })`, window);
  vm.runInContext(script, window);
  check(vm.runInContext(`'getStatusForPolicy' in MediaKeys.prototype`, window),
        'a non-configurable method is left without an error');
}

console.log(`safari media keys: ${checks} checks passed`);
