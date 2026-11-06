// Static fixture/guard checks only. This never launches a browser or claims API conformance.
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import {fileURLToPath} from "node:url";
import {spawnSync} from "node:child_process";
import {fixtureURL, parseFixtureURL, ownsTab, sameIDs, identityFailure} from "./guard.mjs";
const root = path.dirname(fileURLToPath(import.meta.url));
let checks = 0;
function test(fn) { fn(); checks++; }
const manifest = JSON.parse(fs.readFileSync(path.join(root, "manifest.json"), "utf8"));
test(() => assert.equal(manifest.manifest_version, 3));
test(() => assert.deepEqual(manifest.permissions, ["activeTab", "scripting", "storage"]));
for (const key of ["host_permissions", "optional_host_permissions", "optional_permissions", "content_scripts", "externally_connectable", "web_accessible_resources", "update_url"]) {
  test(() => assert.equal(manifest[key], undefined, `${key} widens this fixture's scope`));
}
test(() => assert.deepEqual(manifest.background, {service_worker: "worker.js", type: "module"}));
test(() => assert.equal(manifest.action.default_popup, "popup.html"));
test(() => assert.equal(manifest.content_security_policy.extension_pages,
  "default-src 'self'; script-src 'self'; object-src 'none'; connect-src 'none'; base-uri 'none'; form-action 'none'"));
test(() => assert.deepEqual(Object.keys(manifest.commands), ["fixture-command", "_execute_action"]));
for (const name of [manifest.background.service_worker, manifest.action.default_popup, "popup.js", "popup.css", "web/fixture.html", "web/fixture.js", "web/fixture.css"]) {
  test(() => assert.ok(fs.statSync(path.join(root, name)).isFile(), `Missing ${name}`));
}
for (const file of ["worker.js", "popup.js", "guard.mjs", "web/fixture.js", "validate.mjs"]) {
  const source = fs.readFileSync(path.join(root, file), "utf8");
  const syntax = spawnSync(process.execPath, ["--input-type=module", "--check"], {input: source, encoding: "utf8"});
  test(() => assert.equal(syntax.status, 0, `${file}: ${syntax.stderr}`));
}
const run = "11111111-1111-4111-8111-111111111111";
const other = "22222222-2222-4222-8222-222222222222";
const valid = fixtureURL(run);
test(() => assert.deepEqual(parseFixtureURL(valid), {run, step: "one", role: "main"}));
for (const bad of [
  undefined, "", "https://example.com/", valid.replace("127.0.0.1", "localhost"),
  valid.replace("127.0.0.1", "127.0.0.1.example.com"), valid.replace("http:", "https:"),
  valid.replace(":8765", ":8766"), valid.replace("/fixture.html", "/private.html"),
  valid.replace("127.0.0.1", "user:password@127.0.0.1"), valid + "#extra", valid + "&run=" + run,
  valid + "&unknown=1", valid.replace("step=one", "step=other"), valid.replace("role=main", "role=other"),
  valid.replace(run, "bad"), valid.replace("/fixture.html", "/%66ixture.html")
]) test(() => assert.equal(parseFixtureURL(bad), null, `Accepted unsafe URL: ${bad}`));
const registry = {run, tabs: {"3": {id: 3, windowId: 7, role: "main", run}}, windows: {"7": {id: 7, type: "normal"}}};
const tab = {id: 3, windowId: 7, url: valid};
test(() => assert.equal(ownsTab(tab, registry), true));
for (const changed of [undefined, {...tab, id: 4}, {...tab, windowId: 8}, {...tab, url: undefined},
  {...tab, url: fixtureURL(other)}, {...tab, url: fixtureURL(run, "one", "sibling")}, {...tab, url: "https://example.com"}]) {
  test(() => assert.equal(ownsTab(changed, registry), false));
}
test(() => assert.equal(ownsTab({...tab, url: fixtureURL(run, "two")}, registry), true));
test(() => assert.equal(ownsTab(tab, {...registry, run: other}), false));
test(() => assert.equal(ownsTab(tab, {...registry, windows: {}}), false));
test(() => assert.equal(sameIDs([1, 2], [2, 1]), true));
test(() => assert.equal(sameIDs([1, 1], [1, 2]), false));
test(() => assert.equal(sameIDs([1], [1, 2]), false));
test(() => assert.throws(() => fixtureURL("bad")));
const main = {id: 3, windowId: 7, index: 0, active: false};
const sibling = {id: 4, windowId: 7, index: 1, active: true};
const tracked = {...registry, tabs: {...registry.tabs, "4": {id: 4, windowId: 7, role: "sibling", run}}};
const window = {id: 7, type: "normal", tabs: [main, sibling]};
const verify = (w = window, q = [main, sibling], a = [sibling], s = [main, sibling]) =>
  identityFailure(w, sibling, q, a, s, tracked);
test(() => assert.equal(verify(), null));
test(() => assert.ok(verify({...window, tabs: [sibling]}, [sibling], [sibling], [sibling])));
test(() => assert.ok(verify({...window, tabs: [main, {...sibling, windowId: 999}]})));
test(() => assert.ok(verify({...window, tabs: [main, {...sibling, index: 999}]})));
test(() => assert.ok(verify(window, [main, sibling], [main])));
test(() => assert.ok(verify(window, [main, sibling], [sibling], [main, {...sibling, active: false}])));
test(() => assert.ok(verify({...window, type: "popup"})));
// Mutate every API result together: agreement alone must not accept invalid state.
for (const invalid of [
  [main, {...sibling, active: false}],
  [{...main, active: true}, sibling],
  [{...main, index: 8}, {...sibling, index: 9}],
  [{...main, index: 0}, {...sibling, index: 0}]
]) {
  test(() => assert.ok(identityFailure({...window, tabs: invalid}, invalid[1],
    invalid, [invalid[1]], invalid, tracked)));
}
console.log(`${checks} fixture manifest, syntax and URL/ownership guard checks passed. Browser runtime remains untested.`);
