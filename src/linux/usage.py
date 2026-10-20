"""usage.py - the last usage Claude itself recorded in a data folder.

    python3 usage.py <data folder>

Prints "5h 34%, week 12% at 14:10" from the newest sample of plan-usage-history.json, or nothing
when the file is missing or unknown. It is only as fresh as the last time that Claude was open.
"""

import json
import sys
import time
from pathlib import Path


def note(data_dir, now=None):
    try:
        samples = json.loads((Path(data_dir) / "plan-usage-history.json").read_text())["samples"]
        last = max(samples, key=lambda s: s["t"])
        usage = last.get("u", {})
        at = time.localtime(last["t"] / 1000)
    except (OSError, ValueError, KeyError, TypeError):
        return ""
    parts = [f"{label} {usage[key]}%" for key, label in (("fh", "5h"), ("sd", "week")) if key in usage]
    if not parts:
        return ""
    today = time.strftime("%Y-%m-%d", time.localtime(now))
    when = time.strftime("%H:%M" if time.strftime("%Y-%m-%d", at) == today else "%Y-%m-%d %H:%M", at)
    return f"{', '.join(parts)} at {when}"


if __name__ == "__main__":
    text = note(sys.argv[1]) if len(sys.argv) > 1 else ""
    if text:
        print(text)
