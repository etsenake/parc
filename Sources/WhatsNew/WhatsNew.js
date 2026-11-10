// See What's New opens the page at #from=<the version the update replaced>&to=<the one it installed>.
// A tab restored after a later update keeps the old range, which this page then ignores.
// scripts/whats_new.py defines `copy` above this, from its COPY.
const [, from, to] = /^#from=(\d+(?:\.\d+)*)&to=(\d+(?:\.\d+)*)$/.exec(location.hash) ?? [];
const [current, ...earlier] = document.querySelectorAll(".step");
if (from && current?.dataset.version === to) {
  // Numeric collation orders 1.10.0 after 1.9.0, as the app compares versions.
  const newer = (step) => step.dataset.version.localeCompare(from, "en", { numeric: true }) > 0;
  const mark = (step, kind, label) => {
    step.classList.add(kind);
    const tag = Object.assign(document.createElement("span"), { className: "tag", textContent: label });
    step.querySelector(".version").after(tag);
  };
  const skipped = earlier.filter(newer);
  skipped.forEach((step) => mark(step, "unseen", copy["new to you"]));
  const previous = earlier.find((step) => step.dataset.version === from);
  if (previous) mark(previous, "previous", copy["previous version"]);
  const note = document.querySelector(".skipped");
  if (note && skipped.length) {
    const line = skipped.length === 1 ? copy["skipped one"] : copy.skipped;
    note.querySelector("span").textContent = line.replace("{from}", from).replace("{count}", skipped.length);
    note.querySelector("a").addEventListener("click", () =>
      skipped.forEach((step) => (step.querySelector("details").open = true)));
    note.hidden = false;
  }
}
