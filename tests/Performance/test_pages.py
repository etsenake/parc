# Adapted from Ardia's apps/browser/scripts/perf/xbench.mjs (Apache-2.0, Copyright 2026 Mantra Patel; see tests/Performance/NOTICE), modified for Parc.
import re
import unittest

from pages import PAGE_SCRIPT, page_for, static_page

ARDIA_SOURCE = r'''const PAGE_SCRIPT = `
window.__ac = { vis: [[Date.now(), document.visibilityState]], shown: [], fcp: null, frame: null, ticks: 0 };
requestAnimationFrame(() => (__ac.frame = Date.now()));
new PerformanceObserver((list) => {
  for (const e of list.getEntries()) if (e.name === "first-contentful-paint") __ac.fcp = performance.timeOrigin + e.startTime;
}).observe({ type: "paint", buffered: true });
document.addEventListener("visibilitychange", () => {
  const t = Date.now();
  __ac.vis.push([t, document.visibilityState]);
  if (document.visibilityState === "visible")
    requestAnimationFrame(() => requestAnimationFrame(() => __ac.shown.push([t, Date.now()])));
});
setInterval(() => __ac.ticks++, 1000);
`;

function staticPage(id) {
  const paras = Array.from({ length: 120 }, (_, i) =>
    `<p>Paragraph ${i} of page ${id}. The quick brown fox jumps over the lazy dog; pack my box with five dozen liquor jugs. ` +
    `Sphinx of black quartz, judge my vow. <a href="#p${i}">anchor ${i}</a></p>`).join("");
  const boxes = Array.from({ length: 60 }, (_, i) =>
    `<div class=b style="background:hsl(${(i * 37 + Number(id.replace(/\D/g, "") || 0) * 11) % 360} 60% 70%)">${i}</div>`).join("");
  return `<!doctype html><meta charset=utf-8><title>Bench ${id}</title>
<style>body{font:15px/1.5 -apple-system,sans-serif;margin:0;padding:24px 48px;background:#fbfaf8;color:#222}
.g{display:grid;grid-template-columns:repeat(10,1fr);gap:8px;margin:16px 0}.b{height:48px;border-radius:10px;display:grid;place-items:center}
h1{font-size:32px}</style><h1>Bench page ${id}</h1><div class=g>${boxes}</div>${paras}<script>${PAGE_SCRIPT}</script>`;
}
'''

HUE = "(i * 37 + Number(id.replace(/\\D/g, \"\") || 0) * 11) % 360"


def ardia_script() -> str:
    return re.search(r"const PAGE_SCRIPT = `([^`]*)`;", ARDIA_SOURCE).group(1)


def ardia_literals() -> list[str]:
    body = ARDIA_SOURCE[ARDIA_SOURCE.index("function staticPage(id) {"):]
    return re.findall(r"`([^`]*)`", body)


def fill(template: str, values: dict) -> str:
    def value(match):
        expression = match.group(1)
        if expression not in values:
            raise AssertionError(f"unexpected expression in Ardia's page: {expression}")
        return values[expression]

    return re.sub(r"\$\{((?:[^{}]|\{[^{}]*\})*)\}", value, template)


def ardia_page(page_id: str) -> str:
    first, second, box, page = ardia_literals()
    lengths = [int(n) for n in re.findall(r"Array\.from\(\{ length: (\d+) \}", ARDIA_SOURCE)]
    number = int(re.sub(r"[^0-9]", "", page_id) or 0)
    paras = "".join(fill(first, {"i": str(i), "id": page_id}) + fill(second, {"i": str(i), "id": page_id}) for i in range(lengths[0]))
    boxes = "".join(fill(box, {"i": str(i), HUE: str((i * 37 + number * 11) % 360)}) for i in range(lengths[1]))
    return fill(page, {"id": page_id, "boxes": boxes, "paras": paras, "PAGE_SCRIPT": ardia_script()})


class StaticPageTests(unittest.TestCase):
    def test_the_fixture_is_ardias_page_source(self):
        self.assertEqual(len(ardia_literals()), 4)
        self.assertIn(HUE, ARDIA_SOURCE)
        self.assertEqual([int(n) for n in re.findall(r"length: (\d+)", ARDIA_SOURCE)], [120, 60])
        self.assertEqual(ARDIA_SOURCE.count('.join("")'), 2)

    def test_the_page_script_is_byte_identical(self):
        self.assertEqual(PAGE_SCRIPT, ardia_script())
        self.assertTrue(PAGE_SCRIPT.startswith("\nwindow.__ac = {"))
        self.assertTrue(PAGE_SCRIPT.endswith("setInterval(() => __ac.ticks++, 1000);\n"))

    def test_every_page_the_harness_opens_is_byte_identical(self):
        ids = ["seed", "0", "", "check", "check-nt", "r0-link0-parc", "r2-link1-chrome", "r4-restore1-helium-bg"]
        ids += [f"t{i}" for i in range(1, 20)] + [f"n{k}" for k in range(5)] + [f"w{k}" for k in range(3)]
        for page_id in ids:
            with self.subTest(page_id=page_id):
                self.assertEqual(static_page(page_id).encode(), ardia_page(page_id).encode())

    def test_known_slices(self):
        seed = static_page("seed")
        self.assertTrue(seed.startswith("<!doctype html><meta charset=utf-8><title>Bench seed</title>\n<style>body{font:15px/1.5"))
        self.assertIn('<div class=b style="background:hsl(0 60% 70%)">0</div><div class=b style="background:hsl(37 60% 70%)">1</div>', seed)
        self.assertIn('<div class=b style="background:hsl(77 60% 70%)">0</div>', static_page("t7"))
        self.assertIn('<p>Paragraph 119 of page seed. The quick brown fox jumps over the lazy dog; pack my box with five dozen '
                      'liquor jugs. Sphinx of black quartz, judge my vow. <a href="#p119">anchor 119</a></p><script>\n', seed)
        self.assertTrue(seed.endswith("1000);\n</script>"))
        self.assertEqual(seed.count("<p>"), 120)
        self.assertEqual(seed.count("<div class=b "), 60)

    def test_digits_hue_like_javascript_numbers(self):
        self.assertIn("hsl(NaN 60% 70%)", static_page("x" + "9" * 400))
        self.assertIn('hsl(231 60% 70%)">0</div>', static_page("r2-link1-chrome"))


class ServedPageTests(unittest.TestCase):
    def test_the_server_serves_the_static_page_by_id(self):
        self.assertEqual(page_for("/static?id=seed"), static_page("seed"))
        self.assertEqual(page_for("/static?id=t3&x=1"), static_page("t3"))
        self.assertEqual(page_for("/static?x=1&id=a&id=b"), static_page("a"))

    def test_a_missing_id_is_0_and_an_empty_one_stays_empty(self):
        self.assertEqual(page_for("/static"), static_page("0"))
        self.assertEqual(page_for("/static?id="), static_page(""))

    def test_ids_are_decoded_as_search_params(self):
        self.assertEqual(page_for("/static?id=a+b%21"), static_page("a b!"))

    def test_other_paths_are_not_found(self):
        for path in ("/", "/anim?id=1", "/appcast.xml", "/static/", "/%73tatic?id=1"):
            with self.subTest(path=path):
                self.assertIsNone(page_for(path))


if __name__ == "__main__":
    unittest.main()
