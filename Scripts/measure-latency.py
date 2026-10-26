#!/usr/bin/env python3
"""Summarize Dictate's local unified-log timing events; never reads transcript storage."""
import argparse
from collections import Counter, defaultdict
import json
import math
from pathlib import Path
import re
import subprocess
import sys

EVENT = re.compile(r"transaction=([\w-]+) stage=(\w+) start_ms=([\d.eE+-]+)(?: stop_ms=([\d.eE+-]+))?")


def summarize(lines):
    transactions = defaultdict(dict)
    for line in lines:
        try:
            entry = json.loads(line)
            message = entry.get("eventMessage", "") if isinstance(entry, dict) else ""
        except (ValueError, TypeError):
            message = line  # Also accepts compact `log stream` output.
        match = EVENT.search(message)
        if not match:
            continue
        identity, stage, start, stop = match.groups()
        start, stop = float(start), float(stop) if stop is not None else None
        if math.isfinite(start) and (stop is None or math.isfinite(stop)):
            transactions[identity][stage] = (start, stop)

    samples = defaultdict(list)
    outcomes = Counter()
    for stages in transactions.values():
        if "cancelled" in stages:
            outcomes["cancelled"] += 1
            continue
        if "paste_posted" in stages:
            outcomes["paste_posted"] += 1
            posted = stages["paste_posted"]
            if posted[1] is not None and posted[1] >= 0:
                samples["stop_to_paste_posted_ms"].append(posted[1])
                kind = "warm" if "analyzer_ready_warm" in stages else "cold" if "analyzer_ready_cold" in stages else "unknown"
                samples[f"stop_to_paste_posted_{kind}_ms"].append(posted[1])
        elif "manual_paste_required" in stages:
            outcomes["manual_paste_required"] += 1
        elif "start_failed" in stages:
            outcomes["start_failed"] += 1
        else:
            outcomes["incomplete_or_empty"] += 1
        if "first_audio_buffer" in stages:
            samples["request_to_first_audio_ms"].append(stages["first_audio_buffer"][0])
        if "recognition_finished" in stages and stages["recognition_finished"][1] is not None:
            samples["stop_to_recognition_finished_ms"].append(stages["recognition_finished"][1])
        for metric, begin, end in [
            ("processing_queue_wait_ms", "recognition_finished", "processing_started"),
            ("ai_polishing_ms", "ai_cleanup_started", "ai_cleanup_finished"),
            ("ai_deadline_ms", "ai_cleanup_started", "ai_cleanup_deadline"),
            ("paste_gate_wait_ms", "insertion_wait_started", "paste_ready"),
        ]:
            if begin in stages and end in stages:
                samples[metric].append(max(0, stages[end][0] - stages[begin][0]))

    def stats(values):
        values = sorted(values)
        def percentile(p):
            return round(values[max(0, math.ceil(len(values) * p) - 1)], 2)
        return {"count": len(values), "p50": percentile(.5), "p95": percentile(.95), "max": round(values[-1], 2)}

    return {"transactions": len(transactions), "outcomes": dict(outcomes),
            "metrics": {key: stats(values) for key, values in sorted(samples.items())},
            "note": "Paste timings end when keyboard events are posted, not when the editor acknowledges insertion."}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--last", default="15m", help="unified-log window, e.g. 15m or 1h")
    parser.add_argument("--input", help="saved log file, or - for stdin")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()
    if args.input:
        lines = sys.stdin if args.input == "-" else Path(args.input).read_text().splitlines()
    else:
        if not re.fullmatch(r"\d+[smhd]", args.last):
            parser.error("--last must be a duration such as 15m or 1h")
        result = subprocess.run(["/usr/bin/log", "show", "--style", "ndjson", "--last", args.last,
                                 "--predicate", 'process == "Dictate" AND subsystem == "Dictate" AND category == "Latency"'],
                                capture_output=True, text=True)
        if result.returncode:
            print(result.stderr, file=sys.stderr)
            return result.returncode
        lines = result.stdout.splitlines()
    report = summarize(lines)
    if args.json:
        print(json.dumps(report, indent=2))
    else:
        print(f"Transactions: {report['transactions']}  Outcomes: {report['outcomes']}")
        for metric, values in report["metrics"].items():
            print(f"{metric}: n={values['count']} p50={values['p50']:.2f} p95={values['p95']:.2f} max={values['max']:.2f}")
        print(report["note"])
    return 0 if report["transactions"] else 2


if __name__ == "__main__":
    sys.exit(main())
