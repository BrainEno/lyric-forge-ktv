#!/usr/bin/env python3
"""Turn CI logs into GitHub annotations after a failed step.

Job logs are not always reachable from where failures get triaged, while
annotations are. For every log that exists this prints the first lines that
look like errors and the tail, as `::error` workflow commands.

  python3 annotate_failure.py build.log separator.log
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

LIMIT = 3500
ERROR = re.compile(r"error|fatal|exception|traceback|LF_ERROR|failed", re.I)


def escape(text: str) -> str:
    return text.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")


def main(paths: list[str]) -> int:
    for name in paths:
        path = Path(name)
        if not path.is_file() or path.stat().st_size == 0:
            continue
        text = path.read_text(encoding="utf-8", errors="replace")
        lines = text.splitlines()
        hits = [line for line in lines if ERROR.search(line)][:40]
        if hits:
            first = "\n".join(hits)[:LIMIT]
            print(f"::error title={path.name} errors::{escape(first)}")
        print(f"::error title={path.name} tail::{escape(text[-LIMIT:])}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
