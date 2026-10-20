"""Tests for src/linux/usage.py - standard library only. Run: python3 -m unittest discover tests"""
import json
import pathlib
import sys
import tempfile
import time
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / "src" / "linux"))
import usage

NOW = time.mktime((2026, 10, 20, 18, 0, 0, 0, 0, -1))   # a fixed local "now"


def ms(*local):
    return int(time.mktime(local + (0, 0, -1)) * 1000)


class UsageNote(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.path = pathlib.Path(self.dir.name) / "plan-usage-history.json"

    def tearDown(self):
        self.dir.cleanup()

    def write(self, data):
        self.path.write_text(data if isinstance(data, str) else json.dumps(data))

    def test_newest_sample_with_both_windows(self):
        self.write({"version": 2, "samples": [
            {"t": ms(2026, 10, 20, 17, 22, 0), "org": "o", "u": {"fh": 34, "sd": 12}},
            {"t": ms(2026, 10, 20, 9, 0, 0), "org": "o", "u": {"fh": 90, "sd": 80}},
        ]})
        self.assertEqual(usage.note(self.dir.name, NOW), "5h 34%, week 12% at 17:22")

    def test_only_the_windows_it_knows(self):
        self.write({"version": 2, "samples": [{"t": ms(2026, 10, 20, 17, 22, 0), "u": {"fh": 99, "oa": 0, "cw": 0}}]})
        self.assertEqual(usage.note(self.dir.name, NOW), "5h 99% at 17:22")

    def test_date_when_not_today(self):
        self.write({"samples": [{"t": ms(2026, 10, 19, 22, 42, 0), "u": {"sd": 14}}]})
        self.assertEqual(usage.note(self.dir.name, NOW), "week 14% at 2026-10-19 22:42")

    def test_nothing_when_unknown(self):
        self.assertEqual(usage.note(self.dir.name, NOW), "")   # no file
        for data in ("not json", {"samples": []}, {"samples": [{"t": 1, "u": {"xx": 1}}]}, {"other": 1}, [1, 2]):
            self.write(data)
            self.assertEqual(usage.note(self.dir.name, NOW), "", data)


if __name__ == "__main__":
    unittest.main()
