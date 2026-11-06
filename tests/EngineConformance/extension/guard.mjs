export const ORIGIN = "http://127.0.0.1:8765";
export const PATH = "/fixture.html";
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
const STEPS = new Set(["one", "two", "popup"]);
const ROLES = new Set(["main", "sibling", "popup"]);

export function fixtureURL(run, step = "one", role = "main") {
  if (!UUID.test(run) || !STEPS.has(step) || !ROLES.has(role)) throw new Error("Invalid fixture URL parameters");
  const url = new URL(PATH, ORIGIN);
  url.search = new URLSearchParams({run, step, role}).toString();
  return url.href;
}

export function parseFixtureURL(input) {
  try {
    const url = new URL(input);
    const {run, step, role} = Object.fromEntries(url.searchParams);
    if (url.origin !== ORIGIN || url.pathname !== PATH || url.username || url.password || url.hash ||
        [...url.searchParams].length !== 3 || !UUID.test(run) || !STEPS.has(step) || !ROLES.has(role)) return null;
    if (url.href !== fixtureURL(run, step, role)) return null;
    return {run, step, role};
  } catch { return null; }
}

export function ownsTab(tab, registry) {
  const record = registry.tabs[String(tab?.id)];
  const parsed = parseFixtureURL(tab?.url);
  return Boolean(record && parsed && parsed.run === registry.run && record.run === registry.run &&
    parsed.role === record.role && tab.windowId === record.windowId && registry.windows[String(tab.windowId)]);
}

export function sameIDs(left, right) {
  return left.length === right.length && new Set(left).size === left.length &&
    new Set(right).size === right.length && left.every(id => right.includes(id));
}

export function identityFailure(window, current, query, active, singles, registry) {
  if (window.id !== current.windowId || window.type !== registry.windows[String(window.id)]?.type)
    return "windows.get returned the wrong window ID/type";
  if (!Array.isArray(window.tabs) || !sameIDs(window.tabs.map(tab => tab.id), query.map(tab => tab.id)))
    return "windows.get and tabs.query disagree about membership";
  const expected = Object.values(registry.tabs).filter(tab => tab.windowId === window.id).map(tab => tab.id);
  if (!expected.includes(current.id) || !expected.every(id => query.some(tab => tab.id === id)))
    return "Window queries omitted a registered live fixture tab";
  if (active.length !== 1 || active[0].id !== current.id || !sameIDs(expected, singles.map(tab => tab.id)))
    return "Active tab query or individual tab membership disagrees";
  if (current.active !== true || active[0].active !== true ||
      query.filter(tab => tab.active === true).length !== 1)
    return "Window must select exactly one active tab";
  const indices = query.map(tab => tab.index).sort((a, b) => a - b);
  if (indices.some((index, offset) => index !== offset))
    return "Window tab indices must cover zero through tab count minus one";
  for (const tab of query) {
    if (tab.windowId !== window.id || !Number.isInteger(tab.index) || tab.index < 0)
      return "Queried tab has the wrong window or invalid index";
    const peers = [window.tabs.find(item => item.id === tab.id), ...singles.filter(item => item.id === tab.id),
      ...active.filter(item => item.id === tab.id), ...(tab.id === current.id ? [current] : [])];
    if (peers.some(item => !item || item.id !== tab.id || item.windowId !== tab.windowId ||
        item.index !== tab.index || item.active !== tab.active))
      return "Populated window, tab query and tabs.get disagree about identity/index/selection";
  }
  return null;
}
