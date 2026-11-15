# Adapted from Ardia's apps/browser/scripts/perf/xbench-rivals.test.mjs (Apache-2.0, Copyright 2026 Mantra Patel; see tests/Performance/NOTICE), modified for Parc.
import unittest

from rivals import RivalsRefused, merge_rivals, rival_warnings

MACHINE = {"model": "MacBook Pro (Mac17,9)", "chip": "Apple M5 Pro", "cores": 15, "ram": "48 GB", "macOS": "27.2 (26B5112a)"}


def entry(name, version, median, **extra):
    return {"name": name, "version": version, "chromium": "155", "median": median, "min": median, "max": median, "n": 3, **extra}


def stored():
    return {
        "date": "2026-10-19",
        "machine": dict(MACHINE),
        "harness": 1,
        "browsers": {
            "ardia": {"name": "Ardia", "version": "0.2.38-nightly.8", "chromium": "155", "measured": "2026-10-19"},
            "dia": {"name": "Dia", "version": "1.53.0", "chromium": "155", "measured": "2026-10-16"},
            "helium": {"name": "Helium", "version": "0.19.3.1", "chromium": "155"},
        },
        "rows": [
            {"id": "newtab", "label": "New tab → first paint", "unit": "ms", "lowerIsBetter": True, "best": "ardia",
             "browsers": {"ardia": entry("Ardia", "0.2.38-nightly.8", 55), "dia": entry("Dia", "1.53.0", 89),
                          "helium": entry("Helium", "0.19.3.1", 71)}},
            {"id": "launch-restore", "label": "Cold launch → restored tab painted", "unit": "ms", "lowerIsBetter": True, "best": "helium",
             "browsers": {"ardia": entry("Ardia", "0.2.38-nightly.8", 360), "dia": entry("Dia", "1.53.0", None, n=0, note="start view"),
                          "helium": entry("Helium", "0.19.3.1", 355)}},
            {"id": "speedometer", "label": "Speedometer 3", "unit": "score", "lowerIsBetter": False, "best": "ardia",
             "browsers": {"ardia": entry("Ardia", "0.2.38-nightly.7", 59.1, measured="2026-10-18"),
                          "helium": entry("Helium", "0.19.3.1", 58.5), "dia": entry("Dia", "1.53.0", 58.2)}},
        ],
        "method": "docs/perf/vs-browsers.md",
        "notes": ["stored note"],
    }


def fresh(**over):
    return {
        "date": "2026-11-09",
        "machine": {**MACHINE, "macOS": "27.3 (26C10)"},
        "harness": 1,
        "browsers": {"ardia": {"name": "Ardia", "version": "0.2.46", "chromium": "155"}},
        "rows": [
            {"id": "newtab", "label": "New tab → first paint", "unit": "ms", "lowerIsBetter": True, "best": "ardia",
             "browsers": {"ardia": entry("Ardia", "0.2.46", 80)}},
            {"id": "launch-restore", "label": "Cold launch → restored tab painted", "unit": "ms", "lowerIsBetter": True, "best": "ardia",
             "browsers": {"ardia": entry("Ardia", "0.2.46", 340)}},
            {"id": "memory-1", "label": "Memory, 1 tab", "unit": "MB", "lowerIsBetter": True, "best": "ardia",
             "browsers": {"ardia": entry("Ardia", "0.2.46", 290)}},
        ],
        "method": "docs/perf/vs-browsers.md",
        "notes": ["fresh note"],
        **over,
    }


def row(merged, ident):
    return next(r for r in merged["rows"] if r["id"] == ident)


class MergeRivalsTests(unittest.TestCase):
    def test_rivals_keep_their_figures_version_and_date_while_the_measured_browser_is_replaced(self):
        m = merge_rivals(fresh(), stored())
        self.assertEqual(m["date"], "2026-11-09")
        self.assertEqual({k: [b["version"], b["measured"]] for k, b in m["browsers"].items()}, {
            "ardia": ["0.2.46", "2026-11-09"],
            "dia": ["1.53.0", "2026-10-16"],
            "helium": ["0.19.3.1", "2026-10-19"],
        })
        newtab = row(m, "newtab")
        self.assertEqual(newtab["browsers"]["ardia"], {**entry("Ardia", "0.2.46", 80), "measured": "2026-11-09"})
        self.assertEqual(newtab["browsers"]["dia"], {**entry("Dia", "1.53.0", 89), "measured": "2026-10-16"})
        self.assertEqual(newtab["browsers"]["helium"], {**entry("Helium", "0.19.3.1", 71), "measured": "2026-10-19"})
        self.assertEqual(newtab["best"], "helium")
        self.assertEqual(m["machine"]["macOS"], "27.3 (26C10)")
        self.assertEqual(m["notes"], ["stored note"])
        self.assertNotIn("forced", m)

    def test_a_rival_note_and_null_median_survive_and_best_is_taken_again(self):
        restore = row(merge_rivals(fresh(), stored()), "launch-restore")
        self.assertIsNone(restore["browsers"]["dia"]["median"])
        self.assertEqual(restore["browsers"]["dia"]["note"], "start view")
        self.assertEqual(restore["best"], "ardia")

    def test_a_row_the_run_did_not_measure_keeps_every_entry_at_its_own_date(self):
        speedometer = row(merge_rivals(fresh(), stored()), "speedometer")
        self.assertEqual(speedometer["browsers"]["ardia"]["version"], "0.2.38-nightly.7")
        self.assertEqual(speedometer["browsers"]["ardia"]["measured"], "2026-10-18")
        self.assertEqual(speedometer["browsers"]["dia"]["measured"], "2026-10-16")
        self.assertEqual(speedometer["browsers"]["helium"]["measured"], "2026-10-19")
        self.assertNotIn("machine", speedometer)

    def test_a_row_only_the_new_run_has_is_added_alone_and_stored_row_order_is_kept(self):
        m = merge_rivals(fresh(), stored())
        self.assertEqual([r["id"] for r in m["rows"]], ["newtab", "launch-restore", "speedometer", "memory-1"])
        self.assertEqual(list(m["rows"][-1]["browsers"]), ["ardia"])

    def test_another_model_or_chip_is_refused_unless_forced_and_a_forced_merge_says_why(self):
        for machine in ({**MACHINE, "chip": "Apple M6"}, {**MACHINE, "model": "MacBook Air (Mac16,12)"}):
            with self.assertRaises(RivalsRefused):
                merge_rivals(fresh(machine=machine), stored())
        forced = merge_rivals(fresh(machine={**MACHINE, "chip": "Apple M6"}), stored(), force=True)
        self.assertRegex(",".join(forced["forced"]), r'chip: stored "Apple M5 Pro", this Mac "Apple M6"')
        self.assertEqual(row(forced, "speedometer")["machine"], MACHINE)

    def test_a_machine_stored_as_plain_text_is_refused(self):
        with self.assertRaises(RivalsRefused):
            merge_rivals(fresh(), {**stored(), "machine": "MacBook Pro, M5 Pro"})

    def test_another_harness_revision_or_none_recorded_is_refused(self):
        with self.assertRaisesRegex(RivalsRefused, r"different harness \(stored 1, this one 2\)"):
            merge_rivals(fresh(harness=2), stored())
        unrecorded = stored()
        del unrecorded["harness"]
        with self.assertRaisesRegex(RivalsRefused, r"stored unrecorded"):
            merge_rivals(fresh(), unrecorded)

    def test_old_rivals_or_a_new_major_or_minor_version_flag_a_full_rerun(self):
        merged = merge_rivals(fresh(date="2026-12-20"), stored())
        warnings = rival_warnings(merged, installed={"dia": "1.54.0", "helium": "0.19.4.2"})
        self.assertEqual(len(warnings), 3)
        self.assertRegex(warnings[0], r"^Dia was measured 65 days ago")
        self.assertRegex(warnings[1], r"^Dia is now 1\.54\.0, measured on 1\.53\.0: a new minor version")
        self.assertRegex(warnings[2], r"^Helium was measured 62 days ago")
        self.assertEqual(rival_warnings(merge_rivals(fresh(), stored()), installed={"helium": "0.19.4.2"}), [])
        self.assertRegex(rival_warnings(merge_rivals(fresh(), stored()), installed={"helium": "1.0.0"})[0], r"a new major version")

    def test_parc_measured_alone_keeps_ardia_and_the_others_as_rivals(self):
        parc = fresh(browsers={"parc": {"name": "Parc", "version": "2.5.0", "chromium": "155"}},
                     rows=[{"id": "newtab", "label": "New tab → first paint", "unit": "ms", "lowerIsBetter": True, "best": "parc",
                            "browsers": {"parc": entry("Parc", "2.5.0", 50)}}])
        m = merge_rivals(parc, stored())
        self.assertEqual(list(m["browsers"]), ["parc", "ardia", "dia", "helium"])
        newtab = row(m, "newtab")
        self.assertEqual(list(newtab["browsers"]), ["parc", "ardia", "dia", "helium"])
        self.assertEqual(newtab["best"], "parc")
        self.assertEqual(newtab["browsers"]["ardia"]["measured"], "2026-10-19")


if __name__ == "__main__":
    unittest.main()
