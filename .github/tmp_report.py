import json
import sys

path = sys.argv[1]
tests = {}
suites = {}
errors = {}
prints = {}
passed = failed = skipped = 0
with open(path, encoding="utf-8", errors="replace") as handle:
    for raw in handle:
        raw = raw.strip()
        if not raw.startswith("{"):
            continue
        try:
            event = json.loads(raw)
        except ValueError:
            continue
        kind = event.get("type")
        if kind == "suite":
            suites[event["suite"]["id"]] = event["suite"].get("path")
        elif kind == "testStart":
            test = event["test"]
            tests[test["id"]] = (test.get("name"), suites.get(test.get("suiteID")))
        elif kind == "print":
            prints.setdefault(event["testID"], []).append(event.get("message", ""))
        elif kind == "error":
            errors.setdefault(event["testID"], []).append(
                (event.get("error", "") + "\n" + event.get("stackTrace", ""))[:1500]
            )
        elif kind == "testDone":
            if event.get("hidden"):
                continue
            if event.get("skipped"):
                skipped += 1
            elif event.get("result") == "success":
                passed += 1
            else:
                failed += 1
                name, suite = tests.get(event["testID"], ("?", "?"))
                message = " | ".join(errors.get(event["testID"], ["(no message)"]))
                printed = "\n".join(prints.get(event["testID"], []))
                if "See exception logs above" in message and printed:
                    keep = [l for l in printed.splitlines() if l.strip() and not l.startswith("#") and "package:flutter/" not in l]
                    message = " ⏎ ".join(keep[:40])
                message = message.replace("\n", " ⏎ ")[:1800]
                print(f"::error title={suite}::{name} :: {message}")
print(f"::notice::{path}: passed={passed} failed={failed} skipped={skipped}")
