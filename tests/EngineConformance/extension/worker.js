import {fixtureURL, parseFixtureURL, ownsTab, identityFailure} from "./guard.mjs";

const BOOT = crypto.randomUUID();
const BOOT_TIME = Date.now();
const LIMIT = 200;
let state;
let queue = Promise.resolve();
const pendingRemovals = new Map();
class Outcome extends Error {
  constructor(status, message) { super(message); this.status = status; }
}
function check(condition, message) { if (!condition) throw new Outcome("FAIL", message); }
function blocked(message) { throw new Outcome("BLOCKED", message); }
function serial(task) {
  const pending = queue.then(task);
  queue = pending.catch(() => {});
  return pending;
}
function api(path, ...args) {
  const parts = path.split(".");
  let owner = chrome;
  for (const part of parts.slice(0, -1)) owner = owner?.[part];
  const fn = owner?.[parts.at(-1)];
  if (typeof fn !== "function") throw new Outcome("UNSUPPORTED", `${path} is absent`);
  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => reject(new Outcome("FAIL", `${path} did not answer within 12 seconds`)), 12000);
    try {
      fn.call(owner, ...args, result => {
        clearTimeout(timeout);
        const error = chrome.runtime.lastError;
        if (error) reject(new Outcome("FAIL", `${path}: ${error.message}`));
        else resolve(result);
      });
    } catch (error) { clearTimeout(timeout); reject(error); }
  });
}
async function load() {
  if (state) return state;
  const local = await api("storage.local.get", ["journal", "profileNonce"]);
  const session = await api("storage.session.get", "registry");
  state = {
    registry: session.registry ?? {run: null, tabs: {}, windows: {}},
    journal: Array.isArray(local.journal) ? local.journal.slice(-LIMIT) : [],
    profileNonce: typeof local.profileNonce === "string" ? local.profileNonce : null
  };
  return state;
}
async function persist() {
  await api("storage.session.set", {registry: state.registry});
  await api("storage.local.set", {journal: state.journal});
}
async function record(operation, status, detail = {}) {
  await load();
  state.journal.push({time: new Date().toISOString(), boot: BOOT, operation, status, detail});
  state.journal = state.journal.slice(-LIMIT);
  await persist();
}
function snapshot() {
  return {boot: BOOT, bootTime: BOOT_TIME, registry: state.registry,
    profileNonce: state.profileNonce, journal: state.journal};
}
function summary(tab) {
  return {id: tab.id, windowId: tab.windowId, index: tab.index, active: tab.active};
}
async function currentFixture() {
  const current = await api("tabs.query", {active: true, lastFocusedWindow: true});
  if (current.length !== 1) blocked("Open the action on one active fixture page");
  const tab = current[0];
  if (!ownsTab(tab, state.registry)) blocked("Open the toolbar action on a page created by this fixture in this browser session; no other tab was changed");
  if (tab.status !== "complete" || tab.pendingUrl) blocked("Wait for the fixture page to finish loading, then reopen the action");
  return tab;
}
function registerTab(tab, role) {
  check(Number.isInteger(tab?.id) && tab.id >= 0 && Number.isInteger(tab.windowId), "Engine returned invalid tab/window identity");
  check(Number.isInteger(tab.index) && tab.index >= 0, "Engine returned an invalid tab index");
  check(!state.registry.tabs[String(tab.id)], "Engine reused a live tracked tab ID");
  state.registry.tabs[String(tab.id)] = {id: tab.id, windowId: tab.windowId, role, run: state.registry.run};
}
async function createWindow(type) {
  if (type === "normal") {
    if (Object.keys(state.registry.tabs).length) blocked("Close the existing fixture tabs before starting another run");
    state.registry = {run: crypto.randomUUID(), tabs: {}, windows: {}};
  } else await currentFixture();
  const role = type === "popup" ? "popup" : "main";
  const window = await api("windows.create", {url: fixtureURL(state.registry.run, role === "popup" ? "popup" : "one", role),
    type, focused: true, width: 840, height: 620});
  check(Number.isInteger(window?.id) && window.id >= 0, "Engine returned invalid window identity");
  check(!state.registry.windows[String(window.id)], "Engine reused a tracked window ID");
  state.registry.windows[String(window.id)] = {id: window.id, type};
  const tabs = await api("tabs.query", {windowId: window.id});
  for (const tab of tabs) registerTab(tab, role);
  await persist();
  check(window.type === type, `Requested ${type} window, received ${window.type ?? "missing type"}`);
  check(tabs.length === 1, "A fresh fixture window must contain exactly one tab");
  return {windowId: window.id, type: window.type, tab: summary(tabs[0]), run: state.registry.run};
}
async function inspectIdentity() {
  const current = await currentFixture();
  const window = await api("windows.get", current.windowId, {populate: true});
  const query = await api("tabs.query", {windowId: current.windowId});
  const active = await api("tabs.query", {windowId: current.windowId, active: true});
  const own = query.filter(tab => state.registry.tabs[String(tab.id)]);
  const singles = [];
  for (const tab of own) {
    singles.push(await api("tabs.get", tab.id));
  }
  const failure = identityFailure(window, current, query, active, singles, state.registry);
  check(!failure, failure);
  return {windowId: window.id, type: window.type, activeTabId: current.id,
    fixtureTabs: own.map(summary), untrackedTabCount: query.length - own.length};
}
async function inject() {
  const tab = await currentFixture();
  const expected = tab.url;
  const results = await api("scripting.executeScript", {
    target: {tabId: tab.id, frameIds: [0]},
    func: (expectedURL) => {
      if (location.href !== expectedURL || location.origin !== "http://127.0.0.1:8765" ||
          location.pathname !== "/fixture.html") return {ok: false, reason: "document changed"};
      if (document.querySelector('meta[name="parc-engine-fixture"]')?.content !== "1")
        return {ok: false, reason: "fixture marker missing"};
      const output = document.getElementById("scripting-count");
      const count = Number(output?.textContent);
      if (!output || !Number.isSafeInteger(count)) return {ok: false, reason: "counter missing"};
      output.textContent = String(count + 1);
      return {ok: true, count: count + 1, step: new URL(location.href).searchParams.get("step")};
    }, args: [expected]
  });
  check(results.length === 1 && results[0].frameId === 0, "Injection did not return one main-frame result");
  const result = results[0].result;
  check(result?.ok === true && Number.isSafeInteger(result.count), `Injection rejected: ${result?.reason ?? "missing result"}`);
  return {tab: summary(tab), ...result};
}
async function perform(operation, input) {
  await load();
  switch (operation) {
    case "snapshot": return snapshot();
    case "new-run": return createWindow("normal");
    case "popup": return createWindow("popup");
    case "identity": return inspectIdentity();
    case "inject": return inject();
    case "sibling": {
      const source = await currentFixture();
      const tab = await api("tabs.create", {windowId: source.windowId, openerTabId: source.id,
        url: fixtureURL(state.registry.run, "one", "sibling"), active: true});
      registerTab(tab, "sibling"); await persist();
      check(tab.windowId === source.windowId, "Sibling was created in the wrong window");
      check(tab.openerTabId === source.id, "Sibling openerTabId was not preserved");
      return {tab: summary(tab), openerTabId: tab.openerTabId};
    }
    case "navigate": {
      const tab = await currentFixture();
      const parsed = parseFixtureURL(tab.url);
      const next = parsed.step === "one" ? "two" : "one";
      const updated = await api("tabs.update", tab.id, {url: fixtureURL(state.registry.run, next, parsed.role)});
      check(updated?.id === tab.id && updated.windowId === tab.windowId, "Navigation changed tab/window identity");
      return {tab: summary(updated), requestedStep: next, note: "Request accepted; verify the visible step and run Inject after loading"};
    }
    case "remove": {
      const tab = await currentFixture();
      if (typeof chrome.tabs?.onRemoved?.addListener !== "function") throw new Outcome("UNSUPPORTED", "tabs.onRemoved is absent");
      let timer;
      const removal = new Promise((resolve, reject) => {
        pendingRemovals.set(tab.id, resolve);
        timer = setTimeout(() => reject(new Outcome("FAIL", "tabs.remove did not produce onRemoved within 8 seconds")), 8000);
      });
      removal.catch(() => {});
      try {
        await api("tabs.remove", tab.id);
        const info = await removal;
        check(info.windowId === tab.windowId, "Removal event reported the wrong window");
        return {removedTabId: tab.id, windowId: tab.windowId, removalEventObserved: true};
      } finally { clearTimeout(timer); pendingRemovals.delete(tab.id); }
    }
    case "ping": return {boot: BOOT, uptimeMs: Date.now() - BOOT_TIME};
    case "commands": {
      if (typeof chrome.commands?.onCommand?.addListener !== "function") throw new Outcome("UNSUPPORTED", "commands.onCommand is absent");
      const commands = await api("commands.getAll");
      check(commands.some(item => item.name === "fixture-command"), "The custom command was not registered");
      return {commands: commands.map(({name, shortcut}) => ({name, shortcut})),
        note: "An empty shortcut is unbound; it is not evidence of command dispatch"};
    }
    case "nonce-create": {
      if (state.profileNonce) blocked("This profile already has a nonce; use Read / compare instead");
      const nonce = crypto.randomUUID();
      await api("storage.local.set", {profileNonce: nonce});
      const read = await api("storage.local.get", "profileNonce");
      check(read.profileNonce === nonce, "Profile nonce read-after-write mismatch");
      state.profileNonce = nonce;
      return {nonce, note: "Copy this synthetic nonce; compare after restart and in a second profile"};
    }
    case "nonce-empty": {
      const read = await api("storage.local.get", "profileNonce");
      check(read.profileNonce === undefined, "This profile already has a nonce; it is not a fresh extension profile");
      return {nonceAbsent: true};
    }
    case "nonce-read": {
      const read = await api("storage.local.get", "profileNonce");
      if (typeof read.profileNonce !== "string") blocked("Profile nonce is absent (expected in a fresh second profile); nothing was created");
      state.profileNonce = read.profileNonce;
      const expected = String(input.expected ?? "").trim();
      if (!expected) blocked("Enter the previously recorded nonce to perform a persistence comparison");
      check(read.profileNonce === expected, "Profile nonce differs from the supplied expected value");
      return {nonce: read.profileNonce, comparison: "equal"};
    }
    default: blocked("Unknown operation");
  }
}
async function request(operation, input = {}) {
  try {
    const detail = await perform(operation, input);
    if (operation !== "snapshot") await record(operation, "PASS", detail);
    return {ok: true, state: snapshot()};
  } catch (error) {
    const status = error.status ?? "FAIL";
    const message = String(error.message).replace(/(?:https?|file):\/\/\S+/g, "[URL omitted]").slice(0, 600);
    try { await record(operation, status, {message}); } catch { }
    return {ok: false, status, message, state: state ? snapshot() : null};
  }
}

chrome.runtime.onMessage.addListener((message, sender, respond) => {
  if (sender.id !== chrome.runtime.id || sender.url !== chrome.runtime.getURL("popup.html") ||
      message?.fixture !== 1 || typeof message.operation !== "string") return false;
  serial(() => request(message.operation, message)).then(respond,
    error => respond({ok: false, status: "FAIL", message: String(error.message)}));
  return true;
});

function event(operation, extract) {
  return (...args) => { serial(async () => {
    await load();
    const detail = extract(...args);
    if (detail) await record(operation, "EVENT", detail);
  }).catch(error => console.error("Conformance event was not saved:", error.message)); };
}
chrome.runtime.onInstalled.addListener(event("runtime.onInstalled", info => ({reason: info.reason})));
chrome.runtime.onStartup.addListener(event("runtime.onStartup", () => ({boot: BOOT})));
chrome.commands?.onCommand?.addListener(event("commands.onCommand", (command, tab) => ({command,
  fixtureTabId: state.registry.tabs[String(tab?.id)] ? tab.id : null})));
chrome.tabs?.onCreated?.addListener(event("tabs.onCreated", tab => state.registry.tabs[String(tab.id)] ? summary(tab) : null));
chrome.tabs?.onUpdated?.addListener(event("tabs.onUpdated", (id, change) =>
  state.registry.tabs[String(id)] && change.status ? {tabId: id, status: change.status} : null));
chrome.tabs?.onActivated?.addListener(event("tabs.onActivated", info =>
  state.registry.tabs[String(info.tabId)] ? {tabId: info.tabId, windowId: info.windowId} : null));
chrome.tabs?.onRemoved?.addListener((id, info) => {
  pendingRemovals.get(id)?.(info);
  const wasTracked = Boolean(state?.registry.tabs[String(id)]);
  serial(async () => {
    await load();
    if (!wasTracked && !state.registry.tabs[String(id)]) return;
    delete state.registry.tabs[String(id)];
    await record("tabs.onRemoved", "EVENT", {tabId: id, windowId: info.windowId, isWindowClosing: info.isWindowClosing});
  }).catch(error => console.error("Conformance removal was not saved:", error.message));
});
chrome.windows?.onRemoved?.addListener(event("windows.onRemoved", id => {
  if (!state.registry.windows[String(id)]) return null;
  delete state.registry.windows[String(id)];
  for (const [tabID, tab] of Object.entries(state.registry.tabs)) if (tab.windowId === id) delete state.registry.tabs[tabID];
  return {windowId: id};
}));
