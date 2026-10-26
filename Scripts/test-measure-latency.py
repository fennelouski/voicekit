#!/usr/bin/env python3
import importlib.util
import json
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("measure_latency", Path(__file__).with_name("measure-latency.py"))
latency = importlib.util.module_from_spec(spec)
spec.loader.exec_module(latency)


class LatencyReportTests(unittest.TestCase):
    def event(self, identity, stage, start, stop=None):
        text = f"transaction={identity} stage={stage} start_ms={start}"
        if stop is not None:
            text += f" stop_ms={stop}"
        return json.dumps({"eventMessage": text})

    def test_warm_percentiles_deduplicate_and_exclude_cancelled_samples(self):
        rows = []
        for identity, value in [("one", 100), ("two", 300), ("three", 200)]:
            rows += [self.event(identity, "analyzer_ready_warm", 20), self.event(identity, "paste_posted", 1000 + value, value)]
        rows += [rows[-1], self.event("cancel", "cancelled", 50), self.event("cancel", "paste_posted", 99999, 99999)]
        result = latency.summarize(rows)
        self.assertEqual(result["metrics"]["stop_to_paste_posted_warm_ms"], {"count": 3, "p50": 200, "p95": 300, "max": 300})
        self.assertEqual(result["outcomes"], {"paste_posted": 3, "cancelled": 1})

    def test_manual_copy_does_not_count_as_paste(self):
        result = latency.summarize([self.event("one", "manual_paste_required", 200, 100)])
        self.assertEqual(result["outcomes"], {"manual_paste_required": 1})
        self.assertNotIn("stop_to_paste_posted_ms", result["metrics"])

    def test_compact_output_and_unrelated_lines(self):
        rows = ['unrelated log entry', 'timestamp transaction=one stage=first_audio_buffer start_ms=25.5 stop_ms=-900']
        self.assertEqual(latency.summarize(rows)["metrics"]["request_to_first_audio_ms"]["p50"], 25.5)
        self.assertEqual(latency.summarize([])["transactions"], 0)


if __name__ == "__main__":
    unittest.main()
