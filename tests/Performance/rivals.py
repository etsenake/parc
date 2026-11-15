# Adapted from Ardia's apps/browser/scripts/perf/xbench-rivals.mjs (Apache-2.0, Copyright 2026 Mantra Patel; see tests/Performance/NOTICE), modified for Parc.
from datetime import datetime, timezone
import math

RIVALS_MAX_AGE_DAYS = 60
DAY_MS = 86_400_000
MISSING = object()


class RivalsRefused(Exception):
    pass


def _get(value, key):
    return value.get(key, MISSING) if isinstance(value, dict) else MISSING


def _nullish(value) -> bool:
    return value is None or value is MISSING


def _coalesce(*values):
    for value in values[:-1]:
        if not _nullish(value):
            return value
    return values[-1]


def _truthy(value) -> bool:
    if _nullish(value) or value is False or value == "":
        return False
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        return value != 0 and not math.isnan(value)
    return True


def _text(value) -> str:
    if value is MISSING:
        return "undefined"
    if value is None:
        return "null"
    if value is True:
        return "true"
    if value is False:
        return "false"
    if isinstance(value, float) and value.is_integer():
        return str(int(value))
    return str(value)


def _noon(day):
    try:
        return datetime.fromisoformat(f"{_text(day)}T12:00:00+00:00").astimezone(timezone.utc).timestamp() * 1000
    except ValueError:
        return math.nan


def days_between(start, end) -> float:
    span = (_noon(end) - _noon(start)) / DAY_MS
    return span if math.isnan(span) else math.floor(span + 0.5)


def major_minor(version) -> str:
    return ".".join(("" if _nullish(version) else _text(version)).split(".")[:2])


def machine_mismatch(fresh, stored) -> list[str]:
    if not isinstance(stored, (dict, list)):
        return ["the stored machine isn't recorded field by field"]
    return [f'{k}: stored "{_text(_get(stored, k))}", this Mac "{_text(_get(fresh, k))}"'
            for k in ("model", "chip") if _get(fresh, k) != _get(stored, k)]


def refusals(fresh, stored) -> list[str]:
    reasons = [f"different machine ({r})" for r in machine_mismatch(_get(fresh, "machine"), _get(stored, "machine"))]
    stored_harness = _get(stored, "harness")
    if _get(fresh, "harness") != stored_harness:
        reasons.append(f"different harness (stored {_text(_coalesce(stored_harness, 'unrecorded'))}, "
                       f"this one {_text(_get(fresh, 'harness'))})")
    return reasons


def _stamp(entry: dict, measured) -> dict:
    stamped = dict(entry)
    if measured is MISSING:
        stamped.pop("measured", None)
    else:
        stamped["measured"] = measured
    return stamped


def _best_of(row: dict):
    ranked = sorted(((k, b) for k, b in row["browsers"].items()
                     if isinstance(b.get("median"), (int, float)) and not isinstance(b.get("median"), bool)),
                    key=lambda e: e[1]["median"], reverse=not row.get("lowerIsBetter"))
    return ranked[0][0] if ranked else None


def merge_rivals(fresh: dict, stored: dict, force: bool = False) -> dict:
    refused = refusals(fresh, stored)
    if refused and not force:
        raise RivalsRefused(f"won't merge with the stored rivals: {'; '.join(refused)}. Run every browser again, or pass --force")
    own = set(fresh["browsers"])
    stored_browsers = stored.get("browsers") or {}

    def kept_rivals(browsers, entry_measured):
        return {k: _stamp(b, entry_measured(k, b)) for k, b in (browsers or {}).items() if k not in own}

    browsers = {
        **{k: _stamp(b, _get(fresh, "date")) for k, b in fresh["browsers"].items()},
        **kept_rivals(stored_browsers, lambda k, b: _coalesce(_get(b, "measured"), _get(stored, "date"))),
    }

    def measured_of(k, b):
        return _coalesce(_get(b, "measured"), _get(_get(stored_browsers, k), "measured"), _get(stored, "date"))

    fresh_rows = {r["id"]: r for r in fresh["rows"]}
    stored_ids = {r["id"] for r in stored["rows"]}
    merged = []
    for row in stored["rows"]:
        now = fresh_rows.get(row["id"])
        if now is None:
            keep_machine = _truthy(_get(row, "machine")) or machine_mismatch(_get(fresh, "machine"), _get(stored, "machine"))
            machine = _coalesce(_get(row, "machine"), _get(stored, "machine"))
            entry = {**row, **({"machine": machine} if keep_machine else {}),
                     "browsers": {k: _stamp(b, measured_of(k, b)) for k, b in row["browsers"].items()}}
            if entry.get("machine", None) is MISSING:
                entry.pop("machine")
            merged.append(entry)
            continue
        merged.append({**row, **now, "browsers": {
            **{k: _stamp(b, _get(fresh, "date")) for k, b in now["browsers"].items()},
            **kept_rivals(row["browsers"], measured_of),
        }})
    for row in fresh["rows"]:
        if row["id"] not in stored_ids:
            merged.append({**row, "browsers": {k: _stamp(b, _get(fresh, "date")) for k, b in row["browsers"].items()}})
    for row in merged:
        row["best"] = _best_of(row)

    result = {**fresh, "date": _get(fresh, "date"), "browsers": browsers, "rows": merged,
              "notes": _coalesce(_get(stored, "notes"), _get(fresh, "notes"))}
    for key in ("date", "notes"):
        if result[key] is MISSING:
            result.pop(key)
    if refused:
        result["forced"] = refused
    return result


def rival_warnings(merged: dict, installed=None, max_age_days: int = RIVALS_MAX_AGE_DAYS) -> list[str]:
    installed = installed or {}
    warnings = []
    for key, b in merged["browsers"].items():
        measured = _get(b, "measured")
        if measured == _get(merged, "date"):
            continue
        age = days_between(measured, _get(merged, "date"))
        if age > max_age_days:
            warnings.append(f"{_text(_get(b, 'name'))} was measured {_text(age)} days ago ({_text(measured)}), over {max_age_days}: rerun every browser")
        now = installed.get(key)
        version = _get(b, "version")
        if now and major_minor(now) != major_minor(version):
            change = "major" if now.split(".")[0] != _text(version).split(".")[0] else "minor"
            warnings.append(f"{_text(_get(b, 'name'))} is now {now}, measured on {_text(version)}: a new {change} version, rerun every browser")
    return warnings
