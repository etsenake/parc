#!/usr/bin/env python3
"""Run Python unittest folders in parallel: one job per test, or per class when the class has class fixtures."""
import argparse
import concurrent.futures
import contextlib
import io
import multiprocessing
import os
from pathlib import Path
import sys
import time
import traceback
import unittest


def flatten(suite):
    for item in suite:
        if isinstance(item, unittest.TestSuite):
            yield from flatten(item)
        else:
            yield item


def has_class_fixture(case):
    kind = type(case)
    return any(getattr(kind, name).__func__ is not getattr(unittest.TestCase, name).__func__
               for name in ("setUpClass", "tearDownClass"))


def prepare(folder):
    sys.path.insert(0, folder)


def discover(folder):
    loader = unittest.TestLoader()
    units = []
    for case in flatten(loader.discover(folder, top_level_dir=folder)):
        if isinstance(case, unittest.loader._FailedTest):
            name = case._testMethodName
        elif has_class_fixture(case):
            name = type(case).__module__ + "." + type(case).__qualname__
        else:
            name = case.id()
        if name not in units:
            units.append(name)
    return units


def run(name):
    began = time.monotonic()
    try:
        suite = unittest.TestLoader().loadTestsFromName(name)
        result = unittest.TextTestRunner(stream=io.StringIO(), verbosity=0, buffer=True).run(suite)
    except Exception:
        return {"name": name, "run": 0, "skipped": 0, "seconds": time.monotonic() - began,
                "problems": [("ERROR", name, traceback.format_exc())]}
    problems = ([("FAIL", str(test), text) for test, text in result.failures]
                + [("ERROR", str(test), text) for test, text in result.errors]
                + [("UNEXPECTED SUCCESS", str(test), "") for test in result.unexpectedSuccesses])
    return {"name": name, "run": result.testsRun, "skipped": len(result.skipped),
            "seconds": time.monotonic() - began, "problems": problems}


def interleave(queues):
    queues = [list(queue) for queue in queues]
    while any(queues):
        for queue in queues:
            if queue:
                yield queue.pop(0)


def run_folders(folders, jobs):
    context = multiprocessing.get_context("spawn")
    with contextlib.ExitStack() as stack:
        pools = [stack.enter_context(concurrent.futures.ProcessPoolExecutor(
            jobs, mp_context=context, initializer=prepare, initargs=(folder,))) for folder in folders]
        found = [pool.submit(discover, folder) for pool, folder in zip(pools, folders)]
        pending = interleave([(pool, name) for name in discovery.result()] for pool, discovery in zip(pools, found))
        running, results = {}, []
        while True:
            while len(running) < jobs and (item := next(pending, None)):
                running[item[0].submit(run, item[1])] = item[1]
            if not running:
                return results
            done, _ = concurrent.futures.wait(running, return_when=concurrent.futures.FIRST_COMPLETED)
            for future in done:
                name = running.pop(future)
                try:
                    outcome = future.result()
                except Exception:
                    outcome = {"name": name, "run": 0, "skipped": 0, "seconds": 0.0,
                               "problems": [("ERROR", name, traceback.format_exc())]}
                mark = "F" if outcome["problems"] else ("s" if outcome["skipped"] == outcome["run"] else ".")
                print(mark, end="", flush=True)
                results.append(outcome)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("folders", nargs="+", type=Path, help="Test folders, each discovered like unittest discover -s")
    parser.add_argument("--jobs", type=int, default=os.cpu_count() or 4, help="Worker processes (default: every core)")
    parser.add_argument("--durations", type=int, default=0, metavar="N", help="List the N slowest jobs")
    args = parser.parse_args(argv)
    began = time.monotonic()
    for folder in args.folders:
        if not folder.is_dir():
            parser.error(f"{folder} is not a folder")
    results = run_folders([str(folder.resolve()) for folder in dict.fromkeys(args.folders)], max(1, args.jobs))
    print()
    problems = [problem for outcome in results for problem in outcome["problems"]]
    for kind, test, text in problems:
        print("=" * 70 + f"\n{kind}: {test}\n" + "-" * 70 + f"\n{text}")
    if args.durations:
        print("Slowest jobs\n" + "-" * 70)
        for outcome in sorted(results, key=lambda item: item["seconds"], reverse=True)[:args.durations]:
            print(f"{outcome['seconds']:.3f}s     {outcome['name']}")
    total = sum(outcome["run"] for outcome in results)
    skipped = sum(outcome["skipped"] for outcome in results)
    print("-" * 70 + f"\nRan {total} tests in {time.monotonic() - began:.3f}s with {max(1, args.jobs)} workers\n")
    detail = ", ".join(part for part in (f"problems={len(problems)}" if problems else "",
                                         f"skipped={skipped}" if skipped else "") if part)
    print(("FAILED" if problems else "OK") + (f" ({detail})" if detail else ""))
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
