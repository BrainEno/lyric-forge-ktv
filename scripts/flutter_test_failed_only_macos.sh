#!/bin/bash
set -u

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT" || exit 1

if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: python3 is required to run the macOS failed-test helper." >&2
  echo "Install the Xcode Command Line Tools (xcode-select --install) or make python3 available on PATH." >&2
  exit 127
fi

REPO_ROOT="$REPO_ROOT" python3 - "$@" <<'PY'
from __future__ import annotations

import argparse
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
from datetime import datetime
from pathlib import Path
from urllib.parse import unquote, urlparse

REPO_ROOT = Path(os.environ["REPO_ROOT"]).resolve()
STATE_VERSION = 2


def _supports_color() -> bool:
    return sys.stdout.isatty() and os.environ.get("TERM", "") != "dumb"


_COLOR = _supports_color()
COLORS = {
    "red": "\033[31m" if _COLOR else "",
    "green": "\033[32m" if _COLOR else "",
    "yellow": "\033[33m" if _COLOR else "",
    "cyan": "\033[36m" if _COLOR else "",
    "gray": "\033[90m" if _COLOR else "",
    "reset": "\033[0m" if _COLOR else "",
}


def say(message: str, color: str | None = None, *, end: str = "\n") -> None:
    prefix = COLORS.get(color or "", "")
    suffix = COLORS["reset"] if prefix else ""
    print(f"{prefix}{message}{suffix}", end=end, flush=True)


def warn(message: str) -> None:
    say(f"WARNING: {message}", "yellow")


def ensure_parent(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)


def normalize_test_path(raw: object | None) -> str | None:
    if raw is None:
        return None
    value = str(raw).strip()
    if not value:
        return None

    normalized = value
    if value.lower().startswith("file:"):
        try:
            parsed = urlparse(value)
            normalized = unquote(parsed.path)
        except Exception:
            normalized = value

    candidate = Path(normalized).expanduser()
    try:
        full = candidate.resolve() if candidate.is_absolute() else (REPO_ROOT / candidate).resolve()
        try:
            return full.relative_to(REPO_ROOT).as_posix()
        except ValueError:
            if candidate.is_absolute():
                return full.as_posix()
    except (OSError, RuntimeError):
        pass

    return normalized.replace("\\", "/")


def is_runnable_project_test_path(raw: object | None) -> bool:
    normalized = normalize_test_path(raw)
    if not normalized or normalized.lower().startswith("package:"):
        return False
    if not re.match(r"^(test|integration_test)/.+_test\.dart$", normalized):
        return False
    return (REPO_ROOT / normalized).is_file()


def resolve_project_test_path(*candidates: object | None) -> str | None:
    for candidate in candidates:
        if is_runnable_project_test_path(candidate):
            return normalize_test_path(candidate)
    return None


def run_flutter_test(arguments: list[str]) -> tuple[int, list[str]]:
    command = ["flutter", "test", *arguments, "--machine"]
    rendered = " ".join(shlex.quote(part) for part in command)
    say("")
    say(f"> {rendered}", "cyan")
    say("Running", "gray", end="")

    process = subprocess.Popen(
        command,
        cwd=REPO_ROOT,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        encoding="utf-8",
        errors="replace",
        bufsize=1,
    )
    lines: list[str] = []
    assert process.stdout is not None
    for raw_line in process.stdout:
        line = raw_line.rstrip("\r\n")
        lines.append(line)
        if len(lines) % 200 == 0:
            say(".", "gray", end="")
    exit_code = process.wait()
    say("")
    return exit_code, lines


def _event_property(value: object, name: str) -> object | None:
    return value.get(name) if isinstance(value, dict) else None


def parse_flutter_machine_log(
    lines: list[str], exit_code: int, fallback_file: str | None
) -> list[dict[str, object]]:
    suites_by_id: dict[str, str] = {}
    tests_by_id: dict[str, dict[str, str | None]] = {}
    errors_by_id: dict[str, list[str]] = {}
    failed: list[dict[str, object]] = []
    diagnostic_lines: list[str] = []

    for line in lines:
        if not line.strip():
            continue
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            diagnostic_lines.append(line)
            continue

        event_type = _event_property(event, "type")
        if not event_type:
            diagnostic_lines.append(line)
            continue

        if event_type == "suite":
            suite = _event_property(event, "suite")
            if not isinstance(suite, dict) or suite.get("id") is None:
                diagnostic_lines.append(line)
                continue
            suite_path = suite.get("path") or suite.get("url")
            normalized = normalize_test_path(suite_path)
            if is_runnable_project_test_path(normalized):
                suites_by_id[str(suite["id"])] = str(normalized)
            continue

        if event_type == "testStart":
            test = _event_property(event, "test")
            if not isinstance(test, dict):
                diagnostic_lines.append(line)
                continue
            test_id = test.get("id")
            test_name = test.get("name")
            if test_id is None or not str(test_name or "").strip():
                diagnostic_lines.append(line)
                continue

            suite_file = None
            suite_id = test.get("suiteID")
            if suite_id is not None:
                suite_file = suites_by_id.get(str(suite_id))
            test_url = normalize_test_path(test.get("url"))
            resolved_file = resolve_project_test_path(suite_file, test_url, fallback_file)
            tests_by_id[str(test_id)] = {
                "name": str(test_name),
                "file": resolved_file,
            }
            continue

        if event_type == "error":
            test_id = _event_property(event, "testID")
            if test_id is None:
                diagnostic_lines.append(line)
                continue
            message = str(_event_property(event, "error") or "").strip()
            if not message:
                message = "Flutter reported an error without an error message."
            stack_trace = str(_event_property(event, "stackTrace") or "").strip()
            if stack_trace:
                message = f"{message}\n{stack_trace}"
            errors_by_id.setdefault(str(test_id), []).append(message)
            continue

        if event_type == "testDone":
            test_id = _event_property(event, "testID")
            result = str(_event_property(event, "result") or "")
            if test_id is None or not result:
                diagnostic_lines.append(line)
                continue
            if result in {"success", "skipped"}:
                continue

            test = tests_by_id.get(str(test_id))
            name = str(test.get("name")) if test else f"testID:{test_id}"
            file_path = str(test.get("file")) if test and test.get("file") else None
            if not file_path:
                file_path = resolve_project_test_path(None, None, fallback_file)
            mode = "file" if not file_path or name.startswith("loading ") else "test"
            error_text = "\n\n".join(errors_by_id.get(str(test_id), [])) or f"Result: {result}"
            failed.append(
                {
                    "file": file_path,
                    "name": name,
                    "mode": mode,
                    "error": error_text,
                }
            )

    if exit_code != 0 and not failed:
        candidate_file = resolve_project_test_path(None, None, fallback_file)
        if not candidate_file:
            pattern = re.compile(r"(test[\\/][^:\r\n]+?_test\.dart)")
            for line in lines:
                match = pattern.search(line)
                if not match:
                    continue
                matched_file = normalize_test_path(match.group(1))
                if is_runnable_project_test_path(matched_file):
                    candidate_file = matched_file
                    break

        error_text = "\n".join(line for line in diagnostic_lines if line.strip()).strip()
        if not error_text:
            error_text = (
                f"flutter test exited with code {exit_code} before an individual "
                "failing test result was emitted."
            )
        failed.append(
            {
                "file": candidate_file,
                "name": "[suite load / compile failure]",
                "mode": "file",
                "error": error_text,
            }
        )

    return failed


def unique_failures(failures: list[dict[str, object]]) -> list[dict[str, object]]:
    unique: dict[tuple[str, str, str], dict[str, object]] = {}
    for failure in failures:
        key = (
            str(failure.get("mode") or ""),
            str(failure.get("file") or ""),
            str(failure.get("name") or ""),
        )
        unique[key] = failure
    return sorted(
        unique.values(),
        key=lambda item: (str(item.get("file") or ""), str(item.get("name") or "")),
    )


def save_failure_state(state_path: Path, failures: list[dict[str, object]]) -> None:
    ensure_parent(state_path)
    state = {
        "version": STATE_VERSION,
        "updatedAt": datetime.now().astimezone().isoformat(),
        "failures": failures,
    }
    state_path.write_text(
        json.dumps(state, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


def remove_if_exists(path: Path) -> None:
    try:
        path.unlink()
    except FileNotFoundError:
        pass


def write_failure_report(
    report_path: Path, failures: list[dict[str, object]], run_mode: str
) -> None:
    ensure_parent(report_path)
    output = [
        "Flutter failed-test report",
        f"Generated: {datetime.now().astimezone().strftime('%Y-%m-%d %H:%M:%S %z')}",
        f"Run mode: {run_mode}",
        f"Remaining failures: {len(failures)}",
        "",
    ]
    if not failures:
        output.append("No failing tests remain in the current failure queue.")

    for index, failure in enumerate(failures, start=1):
        file_path = str(failure.get("file") or "")
        name = str(failure.get("name") or "")
        mode = str(failure.get("mode") or "file")
        output.extend(
            [
                f"===== FAILURE {index}/{len(failures)} =====",
                f"File: {file_path or '<unknown>'}",
                f"Test: {name}",
                f"Mode: {mode}",
            ]
        )
        if file_path and mode == "test":
            output.append(
                "Retry: flutter test "
                + shlex.quote(file_path)
                + " --plain-name "
                + shlex.quote(name)
            )
        elif file_path:
            output.append("Retry: flutter test " + shlex.quote(file_path))
        output.extend(["Error:", str(failure.get("error") or ""), ""])

    report_path.write_text("\n".join(output) + "\n", encoding="utf-8")


def run_full_suite(state_path: Path, report_path: Path) -> int:
    say("Running the full Flutter test suite...", "yellow")
    exit_code, lines = run_flutter_test([])
    failures = unique_failures(parse_flutter_machine_log(lines, exit_code, None))
    if failures:
        save_failure_state(state_path, failures)
        write_failure_report(report_path, failures, "full-suite")
        say(f"Full suite finished with {len(failures)} failing test(s).", "red")
        say(f"Failure report: {report_path}", "yellow")
        return 1

    remove_if_exists(state_path)
    write_failure_report(report_path, [], "full-suite")
    say("Full Flutter test suite passed.", "green")
    return 0


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "macOS failed-test-only runner. It mirrors the Windows PowerShell helper, "
            "caches failures from flutter test --machine, and reruns only that queue."
        )
    )
    parser.add_argument("--full", "-Full", action="store_true", dest="full")
    parser.add_argument("--reset", "-Reset", action="store_true", dest="reset")
    parser.add_argument(
        "--no-final-full",
        "-NoFinalFull",
        action="store_true",
        dest="no_final_full",
    )
    parser.add_argument(
        "--state-path",
        "-StatePath",
        default=".test-cache/flutter_failed_tests.json",
    )
    parser.add_argument(
        "--failure-report-path",
        "-FailureReportPath",
        default="test-results/flutter_test_failures.txt",
    )
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    if shutil.which("flutter") is None:
        say("ERROR: flutter was not found on PATH.", "red")
        say("Open a terminal where `flutter doctor` works, then run this script again.", "yellow")
        return 127

    state_path = (REPO_ROOT / args.state_path).resolve()
    report_path = (REPO_ROOT / args.failure_report_path).resolve()

    if args.reset:
        remove_if_exists(state_path)
        remove_if_exists(report_path)
        args.full = True

    if args.full or not state_path.exists():
        return run_full_suite(state_path, report_path)

    try:
        state = json.loads(state_path.read_text(encoding="utf-8-sig"))
        if state.get("version") != STATE_VERSION:
            raise ValueError(
                f"Unsupported failed-test cache version: {state.get('version')}"
            )
        raw_failures = state.get("failures")
        pending = list(raw_failures) if isinstance(raw_failures, list) else []
    except (OSError, ValueError, json.JSONDecodeError, TypeError) as error:
        warn(
            "The failed-test cache is stale or unreadable. "
            f"Rebuilding it from a full test run. ({error})"
        )
        remove_if_exists(state_path)
        return run_full_suite(state_path, report_path)

    if not pending:
        remove_if_exists(state_path)
        return run_full_suite(state_path, report_path)

    invalid = [
        failure
        for failure in pending
        if not is_runnable_project_test_path(failure.get("file"))
    ]
    if invalid:
        warn(
            "The failed-test cache contains "
            f"{len(invalid)} non-project path(s) (for example flutter_test framework files). "
            "Rebuilding the cache from a full suite."
        )
        remove_if_exists(state_path)
        return run_full_suite(state_path, report_path)

    say(f"Re-running only {len(pending)} previously failing test(s)...", "yellow")
    remaining: list[dict[str, object]] = []

    for failure in pending:
        file_path = str(failure.get("file") or "")
        name = str(failure.get("name") or "")
        mode = str(failure.get("mode") or "file")
        arguments = [file_path, "--plain-name", name] if mode == "test" else [file_path]
        exit_code, lines = run_flutter_test(arguments)
        new_failures = unique_failures(
            parse_flutter_machine_log(lines, exit_code, file_path)
        )

        if exit_code == 0 and not new_failures:
            say(f"PASS: {name}", "green")
            continue

        if new_failures:
            remaining.extend(new_failures)
        else:
            remaining.append(failure)
        say(f"FAIL: {name}", "red")

    remaining_unique = unique_failures(remaining)
    if remaining_unique:
        save_failure_state(state_path, remaining_unique)
        write_failure_report(report_path, remaining_unique, "failed-only")
        say(
            f"{len(remaining_unique)} failing test(s) remain. "
            "Passed tests were removed from the queue.",
            "red",
        )
        say(f"Failure report: {report_path}", "yellow")
        return 1

    remove_if_exists(state_path)
    write_failure_report(report_path, [], "failed-only")
    say("All cached failures now pass.", "green")

    if args.no_final_full:
        say("Skipping the final full regression run because --no-final-full was supplied.", "yellow")
        return 0

    say("Failure queue is empty; running one final full regression suite.", "yellow")
    return run_full_suite(state_path, report_path)


try:
    raise SystemExit(main(sys.argv[1:]))
except KeyboardInterrupt:
    say("\nInterrupted.", "yellow")
    raise SystemExit(130)
PY
