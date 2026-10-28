import sqlite3
import tempfile
import unittest
from datetime import datetime
from pathlib import Path
from unittest.mock import patch

import medicine_api


class MedicineApiSafetyTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory()
        self.db_path = str(Path(self.temp_dir.name) / "test.db")
        self.db_patch = patch.object(medicine_api, "DB_PATH", self.db_path)
        self.db_patch.start()
        con = sqlite3.connect(self.db_path)
        try:
            con.executescript(
                """
                CREATE TABLE medicine (
                    id INTEGER PRIMARY KEY,
                    name TEXT NOT NULL,
                    alias TEXT,
                    stock_count INTEGER NOT NULL DEFAULT 0,
                    low_stock_threshold INTEGER NOT NULL DEFAULT 3
                );
                CREATE TABLE reminder (
                    id INTEGER PRIMARY KEY,
                    medicine_id INTEGER NOT NULL,
                    remind_time TEXT NOT NULL,
                    dose TEXT,
                    enabled INTEGER NOT NULL DEFAULT 1,
                    owner_id INTEGER NOT NULL
                );
                CREATE TABLE intakelog (
                    id INTEGER PRIMARY KEY,
                    medicine_id INTEGER NOT NULL,
                    taken_at TEXT NOT NULL,
                    dose TEXT,
                    note TEXT,
                    owner_id INTEGER NOT NULL
                );
                INSERT INTO medicine (id, name, alias, stock_count) VALUES
                    (1, '999感冒灵颗粒', '感冒灵颗粒,三九感冒灵', 10),
                    (2, '布洛芬缓释胶囊', '布洛芬', 8);
                INSERT INTO reminder (id, medicine_id, remind_time, dose, enabled, owner_id) VALUES
                    (1, 1, '08:00:00', '一次一袋', 1, 1),
                    (2, 2, '20:00:00', '一次一粒', 1, 1);
                """
            )
            con.commit()
        finally:
            con.close()

    def tearDown(self) -> None:
        self.db_patch.stop()
        self.temp_dir.cleanup()

    def _log_count(self) -> int:
        con = sqlite3.connect(self.db_path)
        try:
            return int(con.execute("SELECT COUNT(*) FROM intakelog").fetchone()[0])
        finally:
            con.close()

    def test_confirm_without_medicine_asks_and_does_not_log(self) -> None:
        result = medicine_api.confirm(owner_id=1, medicine=None)
        self.assertFalse(result["success"])
        self.assertTrue(result["needs_medicine"])
        self.assertIn("哪种药", result["speech"])
        self.assertEqual(self._log_count(), 0)

    def test_unknown_medicine_does_not_fallback_to_nearest_plan(self) -> None:
        result = medicine_api.confirm(owner_id=1, medicine="维生素C")
        self.assertFalse(result["success"])
        self.assertTrue(result["needs_medicine"])
        self.assertEqual(self._log_count(), 0)

    def test_alias_records_only_the_matching_plan(self) -> None:
        result = medicine_api.confirm(owner_id=1, medicine="我吃了感冒灵")
        self.assertTrue(result["success"])
        self.assertIn("999感冒灵颗粒", result["speech"])
        self.assertEqual(self._log_count(), 1)

        con = sqlite3.connect(self.db_path)
        try:
            medicine_id = con.execute("SELECT medicine_id FROM intakelog").fetchone()[0]
        finally:
            con.close()
        self.assertEqual(medicine_id, 1)

    def test_summary_is_short_and_full_is_opt_in(self) -> None:
        items = medicine_api._today_plans(1)
        summary = medicine_api._speech(
            items,
            detail="summary",
            now=datetime(2026, 10, 26, 9, 0),
        )
        self.assertIn("下一项", summary)
        self.assertIn("布洛芬", summary)
        self.assertNotIn("999感冒灵颗粒", summary)
        self.assertIn("全部用药计划", summary)

        full = medicine_api._speech(items, detail="full")
        self.assertIn("999感冒灵颗粒", full)
        self.assertIn("布洛芬", full)


if __name__ == "__main__":
    unittest.main()
