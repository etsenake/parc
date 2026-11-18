#!/usr/bin/env python3
"""Check a notarytool Keychain profile with Apple, waiting out notary service outages."""
import argparse
import datetime
import json
import re
import subprocess
import sys
import time

INTERVAL = 120
LIMIT = 2 * 60 * 60
EXIT_DOWN = 75
EXIT_CREDENTIALS = 3
UPLOAD_TIMEOUT = 60 * 60
OK, UNAVAILABLE, CREDENTIALS, FAILED = "ok", "unavailable", "credentials", "failed"
STATUS = re.compile(r"(?:statusCode:\s*(?:Optional\()?|HTTP status code:?\s*|<title>\s*)(\d{3})\b")
CREDENTIAL = re.compile(r"No Keychain password item found|errSecItemNotFound|could not be found in the keychain"
                        r"|Unable to authenticate|Invalid credentials", re.I)
TIMEOUT = re.compile(r"timed out|NSURLErrorTimedOut", re.I)
NETWORK = re.compile(r"NSURLErrorDomain Code=-10(?:03|04|05|09)\b|Internet connection appears to be offline"
                     r"|network connection was lost|Could not connect to the server|hostname could not be found"
                     r"|networkError", re.I)
DOWN = ("Apple's notary service is down{reason} and stayed unavailable for 2 hours; nothing is wrong with the "
        "notary profile or the release. Rerun the same command once Apple's service is back and the release "
        "resumes where it stopped")


class Refusal(RuntimeError):
    pass


class Unavailable(Refusal):
    def __init__(self, reason=None):
        super().__init__(DOWN.format(reason=" (" + reason + ")" if reason else ""))
        self.reason = reason


def announce(message):
    print(message, flush=True)


def classify(code, output):
    if code == 0:
        return OK, None
    output = output or ""
    found = STATUS.search(output)
    if found:
        status = int(found.group(1))
        if 500 <= status <= 599 or status == 429:
            return UNAVAILABLE, "HTTP " + str(status)
        if status in (401, 403):
            return CREDENTIALS, "HTTP " + str(status)
        return FAILED, "HTTP " + str(status)
    if CREDENTIAL.search(output):
        return CREDENTIALS, None
    if TIMEOUT.search(output):
        return UNAVAILABLE, "timed out"
    if NETWORK.search(output):
        return UNAVAILABLE, "network error"
    return FAILED, None


def waiting(reason):
    return "Apple's notary service is unavailable (" + reason + "); waiting and retrying"


def wait(attempt, log=announce, started=None, limit=LIMIT, interval=INTERVAL):
    started = time.monotonic() if started is None else started
    while True:
        result = attempt()
        kind, reason = classify(result.returncode, result.stdout + result.stderr)
        if kind != UNAVAILABLE:
            return kind, result
        waited = time.monotonic() - started
        if waited >= limit:
            raise Unavailable(reason)
        log(waiting(reason))
        time.sleep(min(interval, limit - waited))


def run(args, log=None, timeout=300):
    args = [str(arg) for arg in args]
    try:
        result = subprocess.run(args, capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        result = subprocess.CompletedProcess(args, 124, "", "notarytool timed out after " + str(timeout) + " seconds\n")
    if log:
        log.write_text(result.stdout + result.stderr)
    return result


def call(args, log=None, report=announce, started=None):
    return wait(lambda: run(args, log), report, started)


def history(profile):
    return ["xcrun", "notarytool", "history", "--keychain-profile", profile, "--output-format", "json"]


def utc():
    return datetime.datetime.now(datetime.timezone.utc)


def moment(value):
    return datetime.datetime.fromisoformat(value.replace("Z", "+00:00"))


def uploads(name, since, profile, report, started):
    kind, result = call(history(profile), report=report, started=started)
    if kind != OK:
        raise Refusal("Could not read notarytool history to look for an unconfirmed upload of " + name
                      + "; nothing was uploaded again")
    try:
        entries = json.loads(result.stdout).get("history", [])
        cutoff = moment(since) - datetime.timedelta(minutes=10)
        return [entry.get("id") for entry in entries if entry.get("name") == name
                and moment(entry.get("createdDate") or "1970-01-01T00:00:00Z") >= cutoff]
    except (ValueError, AttributeError, TypeError):
        raise Refusal("notarytool history returned data this release can't read while looking for an unconfirmed "
                      "upload of " + name + "; nothing was uploaded again") from None


def submit(path, profile, log, receipt, record, unconfirmed, report=announce):
    started = time.monotonic()
    while True:
        if receipt.get("submit_failure"):
            found = uploads(path.name, receipt["unconfirmed_since"], profile, report, started)
            if found:
                raise Refusal("Apple's notary service failed during an upload of " + path.name
                              + " and its history now lists " + ", ".join(map(str, found))
                              + "; nothing was uploaded again. Check it with notarytool info, record it as the "
                              "receipt's submission_id and rerun")
            del receipt["submit_failure"]
        receipt.update(phase="submitting", submit_started_utc=utc().isoformat())
        receipt.setdefault("unconfirmed_since", receipt["submit_started_utc"])
        record(receipt)
        result = run(["xcrun", "notarytool", "submit", path, "--keychain-profile", profile, "--output-format", "json"],
                     log, timeout=UPLOAD_TIMEOUT)
        try:
            identity = json.loads(result.stdout).get("id")
        except (ValueError, AttributeError):
            identity = None
        if identity:
            receipt.update(submission_id=identity, phase="submitted")
            receipt.pop("unconfirmed_since", None)
            record(receipt)
            if result.returncode == 0:
                return identity
            raise Refusal("notarytool submit failed after Apple confirmed submission " + identity
                          + "; see " + str(log) + ". Rerun to resume it without uploading again")
        kind, reason = classify(result.returncode, result.stdout + result.stderr)
        if kind not in (UNAVAILABLE, CREDENTIALS):
            raise Refusal(unconfirmed)
        receipt["submit_failure"] = reason or kind
        record(receipt)
        if kind == CREDENTIALS:
            raise Refusal("notarytool could not use its Keychain profile for the upload; see " + str(log)
                          + ". Fix the profile and rerun; the rerun checks notarytool history before uploading again")
        waited = time.monotonic() - started
        if waited >= LIMIT:
            raise Unavailable(reason)
        report(waiting(reason))
        time.sleep(min(INTERVAL, LIMIT - waited))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("operation", choices=("check",))
    parser.add_argument("--profile", required=True, help="notarytool Keychain profile; never a password")
    args = parser.parse_args()
    try:
        kind, result = call(history(args.profile))
    except Unavailable as error:
        print(error, file=sys.stderr)
        return EXIT_DOWN
    if kind == OK:
        return 0
    sys.stderr.write(result.stdout + result.stderr)
    return EXIT_CREDENTIALS if kind == CREDENTIALS else 2


if __name__ == "__main__":
    raise SystemExit(main())
