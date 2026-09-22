import unittest
from datetime import date, time, timedelta

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
        result = _voice_intent(VoiceIntentRequest(text="今天吃什么药"), self.user, self.session)
        self.assertTrue(result["success"])
        self.assertEqual(result["intent"], "today_medicine")
        self.assertIn("阿司匹林", result["reply"])
        self.assertIn("今天需要服用的药是", result["reply"])

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

        result = _voice_intent(VoiceIntentRequest(text='今天吃什么药'), self.user, self.session)
        self.assertTrue(result['success'])
        self.assertNotIn('未来药', result['reply'])
        self.assertIn('阿司匹林', result['reply'])

    def test_stock_reply_is_chinese(self) -> None:
        result = _voice_intent(VoiceIntentRequest(text="库存还剩多少"), self.user, self.session)
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

        result = _voice_intent(
            VoiceIntentRequest(text="确认服药", schedule_id=self.reminder.id),
            self.user,
            self.session,
        )
        self.assertTrue(result["success"])
        self.assertEqual(result["intent"], "confirm_taken")
        self.assertEqual(result["schedule_id"], self.reminder.id)
        self.session.refresh(self.medicine)
        self.session.refresh(second_medicine)
        self.assertEqual(self.medicine.stock_count, 9)
        self.assertEqual(second_medicine.stock_count, 5)
        logs = self.session.exec(select(IntakeLog)).all()
        self.assertEqual(len(logs), 1)


if __name__ == "__main__":
    unittest.main()
