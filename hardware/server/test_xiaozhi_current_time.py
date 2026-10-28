import unittest
from datetime import datetime
from zoneinfo import ZoneInfo

import xiaozhi_current_time as clock


class CurrentTimeTests(unittest.TestCase):
    def test_spoken_clock_uses_24_hour_conversion(self) -> None:
        now = datetime(2026, 10, 28, 19, 33, tzinfo=ZoneInfo("Asia/Shanghai"))
        self.assertEqual(clock.spoken_clock(now), "晚上7点33分")

    def test_reply_uses_beijing_timezone(self) -> None:
        self.assertTrue(clock.current_time_reply().startswith("现在是"))

    def test_time_questions(self) -> None:
        for question in ("现在几点", "现在几点？", "现在几点呢", "北京时间现在几点", "现在是什么时候"):
            self.assertTrue(clock.is_current_time_question(question), question)
        self.assertFalse(clock.is_current_time_question("我几点吃药"))
        self.assertFalse(clock.is_current_time_question("现在吃什么药"))

    def test_identity_questions_are_not_medicine_confirmations(self) -> None:
        for question in ("你是谁", "你是谁？", "你是谁呀", "你是什么东西", "我说你是谁", "请问你是谁"):
            self.assertTrue(clock.is_identity_question(question), question)
        self.assertFalse(clock.is_identity_question("我已经吃过药了"))
        self.assertFalse(clock.is_identity_question("今天吃什么药"))
        self.assertIn("智能药箱", clock.identity_reply())


if __name__ == "__main__":
    unittest.main()
