# Adapted from Ardia's apps/browser/scripts/perf/xbench.mjs and scripts/lib/launchEnv.test.mjs (Apache-2.0, Copyright 2026 Mantra Patel; see tests/Performance/NOTICE), modified for Parc.
import contextlib
import io
import json
import math
import os
from pathlib import Path
import plistlib
import tempfile
import unittest

import cdp
import instance
import xbench
from xbench import (bench_json, build_report, build_rows, done_keys, js_number, js_round, key_of, kind_of, median,
                    pending, plan, read_samples, record, round_figure, stringify, summary_line, table, usage_delta)

MACHINE = {"model": "MacBook Pro (Mac17,9)", "chip": "Apple M5 Pro", "cores": 15, "ram": "48 GB", "macOS": "27.2 (26B5112a)"}
WINDOW = (40, 80, 1280, 800)


def options(*argv):
    return xbench.parser().parse_args(["run", *argv])


def browser(name, version):
    return {"name": name, "version": version, "chromium": "155.0.8059.84"}


def launch(browser_name, kind, window, paint, ok=True):
    return {"key": f"r0/{kind}0/{browser_name}", "kind": kind, "browser": browser_name, "ok": ok, "window": window, "firstPaint": paint}


def session(browser_name, new_tab, mb, cpu=0.2, wakeups=7.0):
    usage = {"total": {"cpu": cpu, "wakeups": wakeups}, "kinds": {"browser": {"cpu": cpu, "wakeups": wakeups, "count": 1}}, "processes": 9}
    memory = {"totalMB": mb, "kinds": {"browser": mb / 2, "renderer": mb / 2}}
    return {"key": f"r0/session/{browser_name}", "kind": "session", "browser": browser_name, "ok": True,
            "newTab": new_tab, "tabSwitch": [8, 9, None], "newWindow": [None, None, None], "newWindowOpened": [False] * 3,
            "memory": {"tabs1": memory, "tabs10": memory, "tabs20": memory, "tabs20steady": memory, "closed": memory},
            "idle": {"tabs1": usage, "tabs1steady": usage, "tabs20": usage, "tabs20steady": usage}}


class StatsTests(unittest.TestCase):
    def test_median_of_odd_and_even_counts_skips_what_is_not_a_finite_number(self):
        self.assertEqual(median([3, 1, 2]), 2)
        self.assertEqual(median([4, 1, 3, 2]), 2.5)
        self.assertEqual(median([None, math.nan, 5, True, "7", math.inf]), 5)
        self.assertTrue(math.isnan(median([])))
        self.assertTrue(math.isnan(median([None, math.nan])))

    def test_figures_round_like_javascript_to_whole_units_from_100_and_hundredths_below(self):
        self.assertEqual(round_figure(543.5), 544)
        self.assertIsInstance(round_figure(543.4), int)
        self.assertEqual(round_figure(-100.5), -100)
        self.assertEqual(round_figure(8.505), 8.51)
        self.assertEqual(round_figure(0.125), 0.13)
        self.assertEqual(round_figure(99.994), 99.99)
        self.assertIsNone(round_figure(math.nan))
        self.assertIsNone(round_figure(None))
        self.assertEqual(js_round(2.5), 3)
        self.assertEqual(js_round(-2.5), -2)

    def test_table_cells_show_median_range_and_n(self):
        result = {"browsers": {"parc": browser("Parc", "2.5.0"), "chrome": browser("Google Chrome", "155.0.8059.85")},
                  "rows": [{"label": "New tab → first paint", "unit": "ms",
                            "browsers": {"parc": {"median": 54.5, "min": 46, "max": 63, "n": 5},
                                         "chrome": {"median": 8, "min": 8, "max": 8, "n": 1}}},
                           {"label": "New window → first paint", "unit": "ms",
                            "browsers": {"parc": {"median": None, "min": None, "max": None, "n": 0},
                                         "chrome": {"median": 100, "min": 83, "max": 103, "n": 5}}}]}
        self.assertEqual(table(result, ["parc", "chrome"]).split("\n"), [
            "| Row | Parc 2.5.0 | Google Chrome 155.0.8059.85 |",
            "|---|---|---|",
            "| New tab → first paint | 54.5 ms (46–63, n=5) | 8 ms |",
            "| New window → first paint | – | 100 ms (83–103, n=5) |",
        ])


class RowTests(unittest.TestCase):
    def setUp(self):
        self.names = ["parc", "dia", "chrome"]
        self.browsers = {"parc": browser("Parc", "2.5.0"), "dia": browser("Dia", "1.53.0"), "chrome": browser("Google Chrome", "155")}
        self.samples = [
            launch("parc", "restore", 358, 494), launch("parc", "restore", 372, 505.25),
            launch("dia", "restore", 2262, None), launch("chrome", "restore", 424, 438),
            launch("chrome", "restore", 999, 999, ok=False),
            launch("parc", "link", 400, 543), launch("chrome", "link", 380, 484),
            session("parc", [80, 71, 81], 290.4), session("dia", [89], 480), {**session("chrome", [54, 46, 63], 370), "newWindow": [100, 95.5, None]},
            {"key": "size/parc", "kind": "size", "browser": "parc", "ok": True, "download": 187e6, "bundle": 446e6},
            {"key": "size/dia", "kind": "size", "browser": "dia", "ok": True, "download": None, "bundle": 1414e6},
        ]
        self.rows = {r["id"]: r for r in build_rows(self.samples, self.names, self.browsers)}

    def test_each_row_takes_its_kind_of_sample_and_only_finished_ones(self):
        window = self.rows["launch-window"]["browsers"]
        self.assertEqual((window["parc"]["median"], window["parc"]["min"], window["parc"]["max"], window["parc"]["n"]), (365, 358, 372, 2))
        self.assertEqual(window["chrome"]["n"], 1)
        self.assertEqual(self.rows["launch-restore"]["browsers"]["parc"]["median"], 500)
        self.assertEqual(self.rows["newtab"]["browsers"]["parc"]["median"], 80)
        self.assertEqual(self.rows["switch"]["browsers"]["chrome"]["median"], 8.5)
        self.assertEqual(self.rows["memory-1"]["browsers"]["parc"]["median"], 290)

    def test_entries_carry_the_browser_and_best_is_the_best_median(self):
        newtab = self.rows["newtab"]
        self.assertEqual(list(newtab["browsers"]["parc"]), ["name", "version", "chromium", "median", "min", "max", "n"])
        self.assertEqual(newtab["best"], "chrome")
        self.assertEqual(list(newtab), ["id", "label", "unit", "lowerIsBetter", "browsers", "best"])

    def test_unmeasurable_rows_get_their_notes(self):
        restore = self.rows["launch-restore"]["browsers"]["dia"]
        self.assertEqual((restore["median"], restore["min"], restore["max"], restore["n"]), (None, None, None, 0))
        self.assertTrue(restore["note"].startswith("Dia opens on its start view"))
        self.assertIn("newWindow opens a tab", self.rows["newwindow"]["browsers"]["parc"]["note"])
        self.assertEqual(self.rows["newwindow"]["best"], "chrome")
        self.assertEqual(self.rows["newwindow"]["browsers"]["chrome"]["median"], 97.75)

    def test_rows_nobody_measured_are_dropped_and_size_rows_are_context(self):
        self.assertNotIn("launch-link-missing", self.rows)
        self.assertEqual(self.rows["download"]["context"], True)
        self.assertEqual(self.rows["download"]["browsers"]["parc"]["median"], 187)
        self.assertEqual(self.rows["download"]["browsers"]["dia"]["n"], 0)
        self.assertEqual(self.rows["on-disk"]["browsers"]["dia"]["median"], 1414)
        self.assertEqual(list(self.rows)[:4], ["launch-link", "launch-window", "launch-restore", "newtab"])

    def test_the_row_ids_are_ardias(self):
        self.assertEqual([r["id"] for r in xbench.ROWS], [
            "launch-link", "launch-window", "launch-restore", "newtab", "switch", "newwindow", "memory-1", "memory-10",
            "memory-20", "memory-closed", "idle-cpu-1", "idle-cpu-20", "idle-wakeups-1", "idle-wakeups-20",
            "idle-cpu-1-steady", "idle-cpu-20-steady", "idle-wakeups-1-steady", "idle-wakeups-20-steady", "download", "on-disk"])


class BenchJsonTests(unittest.TestCase):
    def report(self, names, browsers, samples):
        return build_report(samples, names, browsers, MACHINE, "2026-11-15")

    def test_the_shape_matches_ardias_bench_json(self):
        result = self.report(["parc"], {"parc": browser("Parc", "2.5.0")}, [session("parc", [55], 290),
                             {"key": "size/parc", "kind": "size", "browser": "parc", "ok": True, "download": 1e8, "bundle": 4e8}])
        data = bench_json(result, ["parc"])
        self.assertEqual(list(data), ["date", "machine", "harness", "browsers", "rows", "method", "notes"])
        self.assertEqual(data["harness"], 1)
        self.assertEqual(data["method"], "docs/perf/vs-browsers.md")
        self.assertEqual(data["machine"], MACHINE)
        self.assertNotIn("download", [r["id"] for r in data["rows"]])
        self.assertIn("download", [r["id"] for r in result["rows"]])
        self.assertTrue(all(isinstance(n, str) for n in data["notes"]))

    def test_a_lone_variant_is_written_under_its_base_name(self):
        names = ["parc", "helium-bg"]
        browsers = {"parc": browser("Parc", "2.5.0"), "helium-bg": {**browser("Helium", "0.19.3.1"), "variant": "background-only copy"}}
        data = bench_json(self.report(names, browsers, [session("parc", [55], 290), session("helium-bg", [44], 300)]), names)
        self.assertEqual(list(data["browsers"]), ["parc", "helium"])
        newtab = next(r for r in data["rows"] if r["id"] == "newtab")
        self.assertEqual(list(newtab["browsers"]), ["parc", "helium"])
        self.assertEqual(newtab["best"], "helium")
        self.assertEqual(key_of("parc-main", ["parc", "parc-main"]), "parc-main")
        self.assertEqual(key_of("parc-main", ["parc-main", "chrome"]), "parc")

    def test_written_like_json_stringify(self):
        value = {"date": "2026-11-15", "n": 3, "median": 290.0, "min": 54.9, "max": math.nan, "x": [], "o": {}, "ok": True,
                 "rows": [{"id": "newtab", "best": None, "label": "New tab → first paint"}]}
        self.assertEqual(stringify(value, 2), "\n".join([
            "{",
            '  "date": "2026-11-15",',
            '  "n": 3,',
            '  "median": 290,',
            '  "min": 54.9,',
            '  "max": null,',
            '  "x": [],',
            '  "o": {},',
            '  "ok": true,',
            '  "rows": [',
            "    {",
            '      "id": "newtab",',
            '      "best": null,',
            '      "label": "New tab → first paint"',
            "    }",
            "  ]",
            "}",
        ]))
        self.assertEqual(stringify({"a": [1, 2.5, None], "b": "x\n\"y\""}), '{"a":[1,2.5,null],"b":"x\\n\\"y\\""}')

    def test_numbers_print_like_javascript(self):
        cases = {0.1: "0.1", 1e-5: "0.00001", 1.5e-7: "1.5e-7", 1.234e-6: "0.000001234", 1e21: "1e+21",
                 1e20: "100000000000000000000", 1731700000123.0: "1731700000123", -0.0: "0", 2.5e16: "25000000000000000"}
        for value, text in cases.items():
            with self.subTest(value=value):
                self.assertEqual(js_number(value), text)
        self.assertEqual(xbench.to_fixed(0.125, 2), "0.13")
        self.assertEqual(xbench.to_fixed(math.nan, 1), "NaN")


class PlanTests(unittest.TestCase):
    def test_browsers_are_interleaved_per_item_and_rotated_each_round(self):
        keys = [i["key"] for i in plan(["a", "b", "c"], {"link", "restore", "session"}, 2, 2)]
        self.assertEqual(keys, [
            "r0/link0/a", "r0/link0/b", "r0/link0/c", "r0/link1/a", "r0/link1/b", "r0/link1/c",
            "r0/restore0/a", "r0/restore0/b", "r0/restore0/c", "r0/restore1/a", "r0/restore1/b", "r0/restore1/c",
            "r0/session/a", "r0/session/b", "r0/session/c",
            "r1/link0/b", "r1/link0/c", "r1/link0/a", "r1/link1/b", "r1/link1/c", "r1/link1/a",
            "r1/restore0/b", "r1/restore0/c", "r1/restore0/a", "r1/restore1/b", "r1/restore1/c", "r1/restore1/a",
            "r1/session/b", "r1/session/c", "r1/session/a",
        ])

    def test_items_carry_round_kind_and_browser_and_rows_limit_the_plan(self):
        items = plan(["parc", "chrome"], {"session", "size"}, 3, 2)
        self.assertEqual(items[0], {"key": "r0/session/parc", "round": 0, "kind": "session", "browser": "parc"})
        self.assertEqual([i["key"] for i in items], ["r0/session/parc", "r0/session/chrome", "r1/session/chrome",
                                                     "r1/session/parc", "r2/session/parc", "r2/session/chrome"])

    def test_default_plan_counts_match_ardias_runs(self):
        items = plan(["parc", "ardia", "helium", "chrome"], {"link", "restore", "session", "size"}, 3, 2)
        self.assertEqual(len([i for i in items if i["kind"] == "link" and i["browser"] == "parc"]), 6)
        self.assertEqual(len([i for i in items if i["kind"] == "session" and i["browser"] == "parc"]), 3)
        self.assertEqual(xbench.estimate_ms("session", 60), 540_000)
        self.assertEqual(xbench.estimate_ms("link", 60), 25_000)


class ResumeTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.file = os.path.join(self.tmp.name, "samples.jsonl")

    def test_finished_items_are_skipped_and_failed_or_thrown_away_ones_run_again(self):
        record(self.file, {"key": "r0/link0/a", "round": 0, "kind": "link", "browser": "a", "ok": True, "window": math.nan})
        record(self.file, {"key": "r0/link0/b", "round": 0, "kind": "link", "browser": "b", "ok": False, "failed": "died"})
        record(self.file, {"key": "r0/link0/c", "round": 0, "kind": "link", "browser": "c", "ok": False, "aborted": "came back"})
        with open(self.file, "a") as handle:
            handle.write("\n")
        samples = read_samples(self.file)
        self.assertEqual(len(samples), 3)
        self.assertEqual(done_keys(samples), {"r0/link0/a"})
        left = [i["key"] for i in pending(["a", "b", "c"], samples, {"link"}, 1, 1)]
        self.assertEqual(left, ["r0/link0/b", "r0/link0/c"])

    def test_lines_are_compact_json_with_nan_as_null(self):
        record(self.file, {"key": "k", "ok": True, "window": math.nan, "firstPaint": 494.0, "tabSwitch": [8.5, math.nan]})
        self.assertEqual(Path(self.file).read_text(), '{"key":"k","ok":true,"window":null,"firstPaint":494,"tabSwitch":[8.5,null]}\n')
        sample = read_samples(self.file)[0]
        self.assertIsNone(sample["window"])

    def test_samples_read_back_still_make_rows(self):
        record(self.file, {**launch("parc", "restore", math.nan, 500.0)})
        rows = {r["id"]: r for r in build_rows(read_samples(self.file), ["parc"], {"parc": browser("Parc", "2.5.0")})}
        self.assertNotIn("launch-window", rows)
        self.assertEqual(rows["launch-restore"]["browsers"]["parc"]["median"], 500)

    def test_a_missing_file_has_no_samples(self):
        self.assertEqual(read_samples(os.path.join(self.tmp.name, "none.jsonl")), [])


class ProcessTests(unittest.TestCase):
    def test_usage_deltas_sum_per_kind_over_processes_seen_twice(self):
        a = [{"pid": 1, "at": 0, "cpuNs": 0, "idleWakeups": 0, "interruptWakeups": 0, "kind": "browser"},
             {"pid": 2, "at": 0, "cpuNs": 0, "idleWakeups": 0, "interruptWakeups": 0, "kind": "renderer"}]
        b = [{"pid": 1, "at": 2000, "cpuNs": 2e7, "idleWakeups": 10, "interruptWakeups": 2, "kind": "browser"},
             {"pid": 2, "at": 2000, "cpuNs": 4e7, "idleWakeups": 4, "interruptWakeups": 0, "kind": "renderer"},
             {"pid": 3, "at": 2000, "cpuNs": 9e9, "idleWakeups": 99, "interruptWakeups": 0, "kind": "gpu-process"}]
        d = usage_delta(a, b)
        self.assertAlmostEqual(d["total"]["cpu"], 3.0)
        self.assertAlmostEqual(d["total"]["wakeups"], 8.0)
        self.assertEqual(d["kinds"]["browser"], {"cpu": 1.0, "wakeups": 6.0, "count": 1})
        self.assertEqual(d["processes"], 3)
        self.assertNotIn("gpu-process", d["kinds"])

    def test_process_kinds_come_from_chromium_switches(self):
        self.assertEqual(kind_of("/x/Parc.app/Contents/MacOS/Parc --parc-test-instance"), "browser")
        self.assertEqual(kind_of("/x/chrome_crashpad_handler --database=/y"), "crashpad")
        self.assertEqual(kind_of("Helper --type=renderer --extension-process"), "extension")
        self.assertEqual(kind_of("Helper --type=utility --utility-sub-type=network.mojom.NetworkService"), "utility:network")
        self.assertEqual(kind_of("Helper --type=utility"), "utility:?")
        self.assertEqual(kind_of("Helper (GPU) --type=gpu-process"), "gpu-process")
        self.assertEqual(xbench.outside_name("/a/Helium.app/Contents/Frameworks/x/Helpers/chrome_crashpad_handler --d"), "chrome_crashpad_handler")
        self.assertEqual(xbench.outside_name("/a/Google Chrome.app/Contents/Frameworks/x/Helpers/chrome_crashpad_handler --d"), "Google")
        self.assertEqual(xbench.outside_name("/a/Helium.app/Contents/Frameworks/Helium Helper.app/Contents/MacOS/Helium Helper"), "Helium Helper")

    def test_summary_lines(self):
        line = summary_line({"kind": "link", "window": 358.4, "firstPaint": math.nan, "pages": 1, "focusTaken": False})
        self.assertEqual(stringify(line), '{"window":358,"paint":null,"pages":1,"focus":false}')
        s = session("parc", [80, 71, math.nan], 290.4)
        s["newWindow"] = [math.nan, 95.5, 100.0]
        self.assertEqual(stringify(summary_line(s)),
                         '{"idle1":["0.20","7.0"],"idle20":["0.20","7.0"],"mem":[290,290,290,290],"sw":9,"nt":76,"nw":[null,96,100],"opened":[false,false,false]}')

    def test_iso_times_have_milliseconds_and_z(self):
        self.assertEqual(xbench.iso(1731700000123), "2024-11-15T19:46:40.123Z")


class LaunchTests(unittest.TestCase):
    def test_parc_follows_the_test_instance_contract(self):
        self.assertEqual(instance.launch_args("parc", "/r/home", 9461, WINDOW), [
            "--parc-profile", "/r/home/profile", "--parc-test-instance", "--parc-perf-marks=/r/home/perf-marks.jsonl",
            "--remote-debugging-port=9461", "--remote-allow-origins=*",
            "--mute-audio", "--disable-backgrounding-occluded-windows", "--no-first-run", "--no-default-browser-check",
            "--password-store=basic", "--use-mock-keychain", "--window-size=1280,800", "--window-position=40,80"])

    def test_chromium_competitors_get_ardias_switches(self):
        shared = ["--no-first-run", "--no-default-browser-check", "--password-store=basic",
                  "--disable-backgrounding-occluded-windows", "--mute-audio"]
        base = ["--user-data-dir=/r/home/udd", "--remote-debugging-port=9461", "--remote-allow-origins=*", *shared,
                "--use-mock-keychain", "--window-size=1280,800", "--window-position=40,80"]
        self.assertEqual(instance.launch_args("dia", "/r/home", 9461, WINDOW), base)
        self.assertEqual(instance.launch_args("chrome", "/r/home", 9461, WINDOW, True), [*base, "--restore-last-session"])
        self.assertEqual(instance.launch_args("ardia", "/r/home", 9461, WINDOW), [*shared, "-NSAppSleepDisabled", "YES"])

    def test_the_browser_table_restores_the_same_one_tab_session(self):
        flags = {n: bool(s.get("restore_switch")) for n, s in xbench.BROWSERS.items()}
        self.assertEqual(flags, {"parc": False, "ardia": False, "dia": False, "helium": True, "chrome": True})
        self.assertEqual(xbench.BROWSERS["parc"]["bundle"], "parc/Parc.app")
        self.assertEqual(xbench.BROWSERS["parc"]["copy_id"], "org.parc.Browser.bench")

    def test_every_browser_gets_its_own_home_and_extra_environment_merges(self):
        extra = instance.extra_env(["parc=FOO=a=b", "chrome=BAR=1", "parc-main=BAZ=2"], "parc")
        self.assertEqual(extra, [{"FOO": "a=b"}])
        self.assertEqual(instance.launch_env("parc", "/r/home", 9461, "http://127.0.0.1:9462", extra),
                         {"HOME": "/r/home", "CFFIXED_USER_HOME": "/r/home", "FOO": "a=b"})
        self.assertEqual(instance.launch_env("chrome", "/r/home", 9461, "http://127.0.0.1:9462"),
                         {"HOME": "/r/home", "CFFIXED_USER_HOME": "/r/home"})

    def test_open_hands_over_the_environment_url_and_switches(self):
        self.assertEqual(instance.open_argv("/apps/parc/Parc.app", {"HOME": "/h", "X": None}, "http://u", ["--a"]),
                         ["open", "-g", "-n", "--env", "HOME=/h", "-a", "/apps/parc/Parc.app", "http://u", "--args", "--a"])
        self.assertEqual(instance.open_argv("/a.app", {}, None, []), ["open", "-g", "-n", "-a", "/a.app", "--args"])

    def test_parc_keeps_its_engine_data_inside_the_run_home(self):
        self.assertEqual(instance.chromium_dirs("parc", "/h"), ["/h/udd", "/h/profile/Chromium-v1"])
        self.assertEqual(instance.chromium_dirs("chrome", "/h"), ["/h/udd"])
        self.assertEqual(instance.debug_logs("parc", "/h")[-1], "/h/profile/Chromium-v1/chrome_debug.log")


class ArdiaEnvironmentTests(unittest.TestCase):
    def bundle(self, folder, needle: bytes, executable="Ardia"):
        app = Path(folder) / f"{executable}.app"
        (app / "Contents/MacOS").mkdir(parents=True)
        with open(app / "Contents/Info.plist", "wb") as handle:
            plistlib.dump({"CFBundleExecutable": executable, "CFBundleShortVersionString": "0.2.46", "CFBundleIdentifier": "dev.ardia"}, handle)
        (app / "Contents/MacOS" / executable).write_bytes(b"\0" * 64 + needle + b"\0" * 64)
        return str(app)

    def test_ardia_gets_its_background_mode_and_update_feed(self):
        with tempfile.TemporaryDirectory() as folder:
            app = self.bundle(folder, b"ARDIA_INSTANCE")
            env = instance.launch_env("ardia", "/r/home", 9461, "http://127.0.0.1:9462", [{"ARDIA_INSTANCE": "chromiumSwitches=--x"}], app)
        self.assertEqual(env, {"HOME": "/r/home", "CFFIXED_USER_HOME": "/r/home", "ARDIA_BACKGROUND": "1", "ARDIA_DATA_DIR": "/r/home/data",
                               "ARDIA_REMOTE_DEBUGGING_PORT": "9461",
                               "ARDIA_INSTANCE": "updateFeed=http://127.0.0.1:9462/appcast.xml,chromiumSwitches=--x"})

    def test_an_older_ardia_gets_the_old_variables(self):
        with tempfile.TemporaryDirectory() as folder:
            app = self.bundle(folder, b"")
            env = instance.launch_env("ardia", "/r/home", 9461, "http://127.0.0.1:9462", [], app)
            legacy = instance.app_env(self.bundle(Path(folder) / "n", b"", "Netnyahoo"), {"ARDIA_BACKGROUND": "1"})
        self.assertEqual(env["ARDIA_UPDATE_FEED_URL"], "http://127.0.0.1:9462/appcast.xml")
        self.assertNotIn("ARDIA_INSTANCE", env)
        self.assertEqual(legacy, {"ARDIA_BACKGROUND": "1", "NETNYAHOO_BACKGROUND": "1"})

    def test_an_extra_instance_list_adds_to_the_defaults(self):
        base = {"ARDIA_BACKGROUND": "1", **instance.launch_variables(instance={"updateFeed": "http://127.0.0.1:1/appcast.xml", "allowOcclusion": True})}
        merged = instance.merge_launch_env(base, {"ARDIA_INSTANCE": "chromiumSwitches=--enable-features=A,B --x"})
        self.assertEqual(merged["ARDIA_BACKGROUND"], "1")
        self.assertEqual(merged["ARDIA_INSTANCE"], "updateFeed=http://127.0.0.1:1/appcast.xml,allowOcclusion,chromiumSwitches=--enable-features=A,B --x")

    def test_a_later_entry_wins_and_every_list_merges_the_same_way(self):
        merged = instance.merge_launch_env(
            instance.launch_variables(instance={"downloadsDir": "/a"}, test={"reauth": "granted"}, trace=["pip"], switch_overrides={"launchTab": False}),
            {"ARDIA_INSTANCE": "downloadsDir=/b", "ARDIA_TEST": "keychain=file", "ARDIA_TRACE": "visibility,pip", "ARDIA_SWITCHES": "launchTab=on,webkitSignIn=on"})
        self.assertEqual(merged["ARDIA_INSTANCE"], "downloadsDir=/b")
        self.assertEqual(merged["ARDIA_TEST"], "reauth=granted,keychain=file")
        self.assertEqual(merged["ARDIA_TRACE"], "pip,visibility")
        self.assertEqual(merged["ARDIA_SWITCHES"], "launchTab=on,webkitSignIn=on")

    def test_repeated_entries_add_their_keys_and_other_variables_pass_through(self):
        merged = instance.merge_launch_env({"ARDIA_INSTANCE": "allowAudio"}, {"ARDIA_INSTANCE": "allowOcclusion"},
                                           {"ARDIA_TEST": "reauth=granted"}, {"ARDIA_TEST": "contextMenu"})
        self.assertEqual(merged["ARDIA_INSTANCE"], "allowAudio,allowOcclusion")
        self.assertEqual(merged["ARDIA_TEST"], "reauth=granted,contextMenu")
        self.assertEqual(instance.merge_launch_env({"HOME": "/h", "ARDIA_DATA_DIR": "/d"}, {"ARDIA_DATA_DIR": None}),
                         {"HOME": "/h", "ARDIA_DATA_DIR": None})
        merged = instance.merge_launch_env({"ARDIA_TEST": "liveMock=http://x/a,b"}, {"ARDIA_TEST": "appMenu"}, {"ARDIA_TEST": "importDiaWindows=2"})
        self.assertEqual(merged["ARDIA_TEST"], "liveMock=http://x/a,b,appMenu,importDiaWindows=2")


class CdpFrameTests(unittest.TestCase):
    def test_the_handshake_accept_key_is_rfc_6455s(self):
        self.assertEqual(cdp.accept_key("dGhlIHNhbXBsZSBub25jZQ=="), "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=")

    def test_client_frames_are_masked_and_parse_back(self):
        for size in (5, 300, 70_000):
            payload = bytes(range(256)) * (size // 256) + b"x" * (size % 256)
            raw = bytearray(cdp.frame(0x1, payload, b"\x01\x02\x03\x04"))
            self.assertEqual(raw[0], 0x81)
            self.assertTrue(raw[1] & 0x80)
            self.assertEqual(cdp.parse_frame(raw), (True, 0x1, payload))
            self.assertEqual(raw, bytearray())

    def test_server_frames_wait_for_their_whole_payload(self):
        message = b'{"id":1,"result":{}}'
        raw = bytes([0x81, len(message)]) + message
        buffer = bytearray(raw[:7])
        self.assertIsNone(cdp.parse_frame(buffer))
        buffer.extend(raw[7:] + bytes([0x89, 0]))
        self.assertEqual(cdp.parse_frame(buffer), (True, 0x1, message))
        self.assertEqual(cdp.parse_frame(buffer), (True, 0x9, b""))
        self.assertEqual(cdp.mask(b"", b"abcd"), b"")


class StubServer:
    base = "http://127.0.0.1:9462"


class StubCdp:
    def __init__(self, pages):
        self.listed = pages
        self.closed = []

    def pages(self):
        return self.listed

    def call(self, method, params):
        self.closed.append(params["targetId"])


class StubApp:
    def __init__(self, browser_name, pages):
        self.b = xbench.BROWSERS[browser_name]
        self.cdp = StubCdp(pages)


class HarnessTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.harness = xbench.Harness(options("--apps", self.tmp.name, "--out", os.path.join(self.tmp.name, "out")))
        self.harness.server = StubServer()
        self.targets = [
            {"id": "start", "type": "page", "url": "parc://start/"},
            {"id": "seed", "type": "page", "url": "http://127.0.0.1:9462/static?id=seed"},
            {"id": "t1", "type": "page", "url": "http://127.0.0.1:9462/static?id=t1"},
        ]

    def test_the_defaults_are_ardias_with_parc_first(self):
        opt = options()
        self.assertEqual(opt.browsers, "parc,ardia,helium,chrome")
        self.assertEqual((opt.port, opt.page_port, opt.rounds, opt.launches, opt.idle, opt.deadline), (9461, 9462, 3, 2, 60, 100))
        self.assertEqual((opt.gate, opt.away, opt.window, opt.launch_tab, opt.rows), ("away", 600, "40,80", "on", "link,restore,session,size"))
        self.assertEqual(opt.apps, str(Path(xbench.__file__).resolve().parents[2] / "build/perf/xbench/apps"))
        self.assertEqual(self.harness.window, WINDOW)

    def test_without_a_command_it_prints_help_and_exits_64(self):
        with contextlib.redirect_stdout(io.StringIO()) as shown:
            self.assertEqual(xbench.main([]), 64)
        self.assertIn("prepare-parc", shown.getvalue())
        with self.assertRaises(SystemExit):
            xbench.main(["report", "--browsers", "parc,edge"])

    def test_parc_only_touches_the_test_pages(self):
        app = StubApp("parc", self.targets)
        self.assertEqual([t["id"] for t in self.harness.own_targets(app)], ["seed", "t1"])
        self.harness.close_all_but_seed(app)
        self.assertEqual(app.cdp.closed, ["t1"])

    def test_competitors_close_every_other_page_as_ardias_harness_does(self):
        app = StubApp("chrome", self.targets)
        self.harness.close_all_but_seed(app)
        self.assertEqual(app.cdp.closed, ["start", "t1"])

    def copy(self, name, identifier):
        app = Path(self.tmp.name) / name / "Parc.app"
        (app / "Contents/MacOS").mkdir(parents=True)
        with open(app / "Contents/Info.plist", "wb") as handle:
            plistlib.dump({"CFBundleExecutable": "Parc", "CFBundleShortVersionString": "2.5.0", "CFBundleIdentifier": identifier}, handle)
        return app

    def test_a_parc_copy_with_the_installed_bundle_identifier_is_refused(self):
        self.copy("parc", "org.parc.Browser")
        with self.assertRaisesRegex(RuntimeError, "prepare-parc"):
            xbench.Instance(self.harness, "parc", self.tmp.name).check_copy()
        self.copy("parc-main", "org.parc.Browser.bench")
        xbench.Instance(self.harness, "parc-main", self.tmp.name).check_copy()

    def test_copies_are_found_under_apps_and_must_exist(self):
        self.copy("parc", "org.parc.Browser.bench")
        self.assertEqual(self.harness.bundle_of("parc"), os.path.join(self.tmp.name, "parc", "Parc.app"))
        with self.assertRaisesRegex(RuntimeError, "no chrome copy"):
            self.harness.bundle_of("chrome")

    def test_bundle_metadata_is_read_from_the_copy(self):
        app = self.copy("parc", "org.parc.Browser.bench")
        info = xbench.app_info(str(app))
        self.assertEqual((info["version"], info["id"], info["build"]), ("2.5.0", "org.parc.Browser.bench", ""))
        self.assertTrue(info["exe"].endswith("/parc/Parc.app/Contents/MacOS/Parc"))
        self.assertIsNone(xbench.chromium_of(str(app), None))
        self.assertEqual(xbench.chromium_of(str(app), {"browser": "Chrome/155.0.8059.84"}), "155.0.8059.84")

    def test_ardias_session_gets_the_launch_tab_and_window_frame(self):
        file = Path(self.tmp.name) / "session.json"
        file.write_text(json.dumps({"tabs": [{"id": "a", "url": ""}, {"id": "b", "url": "http://127.0.0.1:9462/static?id=seed", "profileId": "default"}],
                                    "windows": [{"tabIds": ["a", "b"]}, {"tabIds": ["b"], "kind": "popup"}]}))
        self.harness.probe = lambda *args: {"w": 1512, "h": 982}
        self.harness.fix_ardia_session(str(file))
        session = json.loads(file.read_text())
        self.assertEqual(session["launchTab"], {"id": "b", "url": "http://127.0.0.1:9462/static?id=seed", "profile": ""})
        self.assertEqual([t["id"] for t in session["tabs"]], ["b"])
        self.assertEqual(session["windows"][0], {"tabIds": ["b"], "frame": [40, 102, 1280, 800]})
        self.assertNotIn("frame", session["windows"][1])


if __name__ == "__main__":
    unittest.main()
