import asyncio
import unittest
from datetime import date, time, timedelta
from unittest.mock import AsyncMock, patch

from sqlalchemy.pool import StaticPool
from sqlmodel import SQLModel, Session, create_engine, select

from app.models import IntakeLog, Medicine, Reminder, User, UserRole
from app.routers import _voice_intent
from app.schemas import VoiceIntentRequest
from app.voice_intents import VoiceIntent, shi_bie_yu_yin_yi_tu


class VoiceIntentClassificationTests(unittest.TestCase):
    def test_time_word_alone_does_not_trigger_medicine_intent(self) -> None:
        self.assertEqual(
            shi_bie_yu_yin_yi_tu("今天天气怎么样"),
            VoiceIntent.unknown,
        )

    def test_non_medical_remaining_question_is_unknown(self) -> None:
        self.assertEqual(
            shi_bie_yu_yin_yi_tu("今天还剩几个苹果"),
            VoiceIntent.unknown,
        )

    def test_supported_intents_are_classified(self) -> None:
        self.assertEqual(
            shi_bie_yu_yin_yi_tu("我今天该吃什么药"),
            VoiceIntent.today_medicine,
        )
        self.assertEqual(
            shi_bie_yu_yin_yi_tu("我的库存还剩多少"),
            VoiceIntent.stock_check,
        )
        self.assertEqual(
            shi_bie_yu_yin_yi_tu("确认服用阿司匹林"),
            VoiceIntent.confirm_taken,
        )

    def test_real_spoken_question_matrix(self) -> None:
        cases = {
            VoiceIntent.today_medicine: [
                "今天该吃什么药",
                "今日需要服用什么药",
                "我今天吃什么药",
                "今天吃啥药",
                "今天的用药计划是什么",
                "今天服药安排",
                "我今天吃药计划",
                "我要吃什么药",
            ],
            VoiceIntent.stock_check: [
                "我的药库存还剩多少",
                "药品还剩多少",
                "库存还有几盒",
                "存货余量是多少",
                "阿司匹林还剩多少片",
                "药快吃完了吗",
                "药够不够",
                "还有多少药片",
            ],
            VoiceIntent.expiry_check: [
                "哪些药快过期了",
                "药品有效期到什么时候",
                "药保质期还有多久",
                "有药到期了吗",
                "哪些药临近有效期",
                "过期药有哪些",
                "有效期查询",
                "阿司匹林什么时候过期",
            ],
            VoiceIntent.confirm_taken: [
                "确认服用阿司匹林",
                "记录我吃药了",
                "登记服药",
                "帮我记一下吃药",
                "我已经吃过药了",
                "我刚服了药",
                "我吃药了",
                "确认服药",
            ],
        }
        checked = 0
        for expected, questions in cases.items():
            for question in questions:
                self.assertEqual(shi_bie_yu_yin_yi_tu(question), expected, question)
                checked += 1
        self.assertGreaterEqual(checked, 30)


class VoiceEndpointTests(unittest.TestCase):
    def setUp(self) -> None:
        self.engine = create_engine(
            "sqlite://",
            connect_args={"check_same_thread": False},
            poolclass=StaticPool,
        )
        SQLModel.metadata.create_all(self.engine)
        self.session = Session(self.engine)
        self.user = User(
            id=1,
            phone="13800000001",
            password_hash="test",
            role=UserRole.elder,
            nickname="测试老人",
        )
        self.medicine = Medicine(
            name="阿司匹林",
            alias="阿司匹林片,阿司匹林肠溶片",
            dosage="一次1片，每日1次",
            owner_id=1,
            stock_count=10,
            low_stock_threshold=3,
        )
        self.session.add(self.user)
        self.session.add(self.medicine)
        self.session.commit()
        self.session.refresh(self.medicine)
        self.reminder = Reminder(
            owner_id=1,
            medicine_id=self.medicine.id or 0,
            title="早晨用药",
            dose="1片",
            remind_time=time(8, 0),
            enabled=True,
        )
        self.session.add(self.reminder)
        self.session.commit()
        self.session.refresh(self.reminder)

    def tearDown(self) -> None:
        self.session.close()

    def test_today_medicine_reply_is_chinese(self) -> None:
        result = asyncio.run(_voice_intent(VoiceIntentRequest(text="今天吃什么药", session_id="today-test"), self.user, self.session))
        self.assertTrue(result["success"])
        self.assertEqual(result["intent"], "today_medicine")
        self.assertIn("阿司匹林", result["reply"])
        self.assertIn("今天只有一项用药", result["reply"])

    def test_future_specific_date_is_not_in_today_summary(self) -> None:
        future_medicine = Medicine(
            name='未来药',
            owner_id=1,
            stock_count=5,
            low_stock_threshold=1,
        )
        self.session.add(future_medicine)
        self.session.commit()
        self.session.refresh(future_medicine)
        future_reminder = Reminder(
            owner_id=1,
            medicine_id=future_medicine.id or 0,
            title='明天用药',
            dose='1片',
            remind_time=time(8, 0),
            schedule_date=date.today() + timedelta(days=1),
            enabled=True,
        )
        self.session.add(future_reminder)
        self.session.commit()

        result = asyncio.run(_voice_intent(VoiceIntentRequest(text='今天吃什么药', session_id='future-test'), self.user, self.session))
        self.assertTrue(result['success'])
        self.assertNotIn('未来药', result['reply'])
        self.assertIn('阿司匹林', result['reply'])

    def test_stock_reply_is_chinese(self) -> None:
        result = asyncio.run(_voice_intent(VoiceIntentRequest(text="库存还剩多少", session_id="stock-test"), self.user, self.session))
        self.assertTrue(result["success"])
        self.assertEqual(result["intent"], "stock_check")
        self.assertIn("剩余10", result["reply"])

    def test_confirm_taken_uses_schedule_id_updates_stock_and_log(self) -> None:
        second_medicine = Medicine(
            name="布洛芬",
            owner_id=1,
            stock_count=5,
            low_stock_threshold=1,
        )
        self.session.add(second_medicine)
        self.session.commit()
        self.session.refresh(second_medicine)
        second_reminder = Reminder(
            owner_id=1,
            medicine_id=second_medicine.id or 0,
            title="午间用药",
            dose="1片",
            remind_time=time(12, 0),
            enabled=True,
        )
        self.session.add(second_reminder)
        self.session.commit()

        first = asyncio.run(_voice_intent(
            VoiceIntentRequest(text="确认服药", schedule_id=self.reminder.id, session_id="confirm-test"),
            self.user,
            self.session,
        ))
        self.assertTrue(first["needs_confirmation"])
        self.assertEqual(first["schedule_id"], self.reminder.id)
        self.session.refresh(self.medicine)
        self.assertEqual(self.medicine.stock_count, 10)

        second = asyncio.run(_voice_intent(
            VoiceIntentRequest(text="确认", session_id="confirm-test"),
            self.user,
            self.session,
        ))
        self.assertTrue(second["success"])
        self.assertEqual(second["intent"], "confirm_taken")
        self.assertEqual(second["schedule_id"], self.reminder.id)
        self.session.refresh(self.medicine)
        self.session.refresh(second_medicine)
        self.assertEqual(self.medicine.stock_count, 9)
        self.assertEqual(second_medicine.stock_count, 5)
        logs = self.session.exec(select(IntakeLog)).all()
        self.assertEqual(len(logs), 1)

    def test_confirm_without_medicine_asks_instead_of_using_single_plan(self) -> None:
        first = asyncio.run(_voice_intent(
            VoiceIntentRequest(text="我吃过药了", session_id="missing-medicine-test"),
            self.user,
            self.session,
        ))
        self.assertFalse(first["success"])
        self.assertTrue(first["needs_medicine"])
        self.assertIn("哪种药", first["reply"])
        self.session.refresh(self.medicine)
        self.assertEqual(self.medicine.stock_count, 10)
        self.assertEqual(self.session.exec(select(IntakeLog)).all(), [])

        second = asyncio.run(_voice_intent(
            VoiceIntentRequest(text="阿司匹林", session_id="missing-medicine-test"),
            self.user,
            self.session,
        ))
        self.assertTrue(second["needs_confirmation"])
        self.assertEqual(second["medicine_id"], self.medicine.id)

        third = asyncio.run(_voice_intent(
            VoiceIntentRequest(text="确认", session_id="missing-medicine-test"),
            self.user,
            self.session,
        ))
        self.assertTrue(third["success"])
        self.session.refresh(self.medicine)
        self.assertEqual(self.medicine.stock_count, 9)
        self.assertEqual(len(self.session.exec(select(IntakeLog)).all()), 1)

    def test_today_plan_can_expand_on_follow_up(self) -> None:
        second_medicine = Medicine(
            name="布洛芬",
            owner_id=1,
            stock_count=5,
            low_stock_threshold=1,
        )
        self.session.add(second_medicine)
        self.session.commit()
        self.session.refresh(second_medicine)
        self.session.add(Reminder(
            owner_id=1,
            medicine_id=second_medicine.id or 0,
            title="午间用药",
            dose="1片",
            remind_time=time(12, 0),
            enabled=True,
        ))
        self.session.commit()

        summary = asyncio.run(_voice_intent(
            VoiceIntentRequest(text="今天的用药计划", session_id="detail-test"),
            self.user,
            self.session,
        ))
        self.assertIn("想听全部", summary["reply"])
        self.assertNotIn("阿司匹林", summary["reply"])

        full = asyncio.run(_voice_intent(
            VoiceIntentRequest(text="全部用药计划", session_id="detail-test"),
            self.user,
            self.session,
        ))
        self.assertIn("阿司匹林", full["reply"])
        self.assertIn("布洛芬", full["reply"])
    def test_medicine_alias_correction_answers_from_database(self) -> None:
        result = asyncio.run(_voice_intent(
            VoiceIntentRequest(text="阿司匹林片怎么吃", session_id="medicine-info-test"),
            self.user,
            self.session,
        ))
        self.assertTrue(result["success"])
        self.assertEqual(result["intent"], "medicine_info")
        self.assertEqual(result["source"], "database")
        self.assertIn("一次1片", result["reply"])

    def test_high_risk_question_is_blocked(self) -> None:
        result = asyncio.run(_voice_intent(
            VoiceIntentRequest(text="我能不能加量吃阿司匹林", session_id="risk-test"),
            self.user,
            self.session,
        ))
        self.assertFalse(result["success"])
        self.assertEqual(result["intent"], "high_risk_medical_question")
        self.assertIn("医生", result["reply"])

    def test_ai_fallback_failure_returns_safe_reply(self) -> None:
        with patch("app.routers.answer_voice_ai", new=AsyncMock(return_value=None)):
            result = asyncio.run(_voice_intent(
                VoiceIntentRequest(text="这个药适合我吗", session_id="fallback-test"),
                self.user,
                self.session,
            ))
        self.assertFalse(result["success"])
        self.assertEqual(result["source"], "rule")
        self.assertIn("无法确认", result["reply"])
        self.assertIn("speak_text", result)


if __name__ == "__main__":
    unittest.main()
