import unittest
from datetime import date, datetime, time, timedelta
from unittest.mock import patch

from sqlalchemy.pool import StaticPool
from sqlmodel import SQLModel, Session, create_engine, select

from app.device_agent import MedicineBoxDevice
from app.device_events import (
    DeviceAnnouncement,
    DeviceRuntimeState,
    XiaozhiStateCallback,
    _process_xiaozhi_state,
    next_announcement,
)
from app.medication_scheduler import enqueue_due_medication_announcements
from app.models import Medicine, Reminder, ReminderFrequency, User, UserRole


class MedicationSchedulerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.engine = create_engine(
            "sqlite://",
            connect_args={"check_same_thread": False},
            poolclass=StaticPool,
        )
        SQLModel.metadata.create_all(self.engine)
        self.session = Session(self.engine)
        self.user = User(
            id=2,
            phone="13800000902",
            password_hash="x",
            role=UserRole.elder,
            nickname="elder",
        )
        self.session.add(self.user)
        self.session.commit()
        self.medicine = Medicine(
            id=1,
            name="降压药",
            owner_id=self.user.id,
            stock_count=10,
        )
        self.session.add(self.medicine)
        self.session.commit()
        self.reminder = Reminder(
            id=1,
            medicine_id=self.medicine.id or 1,
            title=self.medicine.name,
            dose="1片",
            remind_time=time(7, 0),
            frequency=ReminderFrequency.daily,
            owner_id=self.user.id,
        )
        self.device = MedicineBoxDevice(
            id=1,
            device_uid="orangepi-schedule",
            name="排程测试药箱",
            owner_id=self.user.id,
            status="online",
        )
        self.session.add(self.reminder)
        self.session.add(self.device)
        self.session.commit()

    def tearDown(self) -> None:
        self.session.close()

    def _due_announcement(self) -> DeviceAnnouncement:
        created = enqueue_due_medication_announcements(
            self.session,
            now=datetime(2026, 10, 28, 7, 0, 15),
        )
        self.assertEqual(len(created), 1)
        announcement = self.session.get(DeviceAnnouncement, created[0])
        self.assertIsNotNone(announcement)
        return announcement

    def test_schedule_is_queued_once_at_seven_and_includes_medicine(self) -> None:
        announcement = self._due_announcement()
        self.assertEqual(announcement.source, "schedule")
        self.assertEqual(announcement.status, "pending")
        self.assertIn("07:00", announcement.text)
        self.assertIn("降压药", announcement.text)
        self.assertIn("1片", announcement.text)
        duplicate = enqueue_due_medication_announcements(
            self.session,
            now=datetime(2026, 10, 28, 7, 0, 45),
        )
        self.assertEqual(duplicate, [])

    def test_schedule_is_not_queued_outside_window_or_for_other_date(self) -> None:
        too_early = enqueue_due_medication_announcements(
            self.session,
            now=datetime(2026, 10, 28, 6, 59, 59),
        )
        self.assertEqual(too_early, [])
        self.reminder.schedule_date = date(2026, 10, 29)
        self.session.add(self.reminder)
        self.session.commit()
        wrong_date = enqueue_due_medication_announcements(
            self.session,
            now=datetime(2026, 10, 28, 7, 0, 15),
        )
        self.assertEqual(wrong_date, [])

    def test_xiaozhi_busy_defers_schedule_until_idle(self) -> None:
        announcement = self._due_announcement()
        busy = _process_xiaozhi_state(
            self.session,
            self.device,
            XiaozhiStateCallback(
                device_uid=self.device.device_uid,
                state="speaking",
            ),
        )
        self.assertTrue(busy["stop_tts"])
        self.assertEqual(busy["deferred"], 1)
        self.session.refresh(announcement)
        self.assertEqual(announcement.status, "pending")
        self.assertEqual(announcement.reason, "waiting_xiaozhi_idle")

        runtime = self.session.exec(
            select(DeviceRuntimeState).where(DeviceRuntimeState.device_id == self.device.id)
        ).first()
        runtime.xiaozhi_state = "idle"
        runtime.last_xiaozhi_at = datetime.utcnow() - timedelta(seconds=3)
        self.session.add(runtime)
        self.session.commit()
        with patch("app.device_events._agent_token_ok", return_value=True):
            response = next_announcement(
                self.device.device_uid,
                self.session,
                "token",
            )
        self.assertIsNotNone(response["announcement"])
        self.assertEqual(response["announcement"]["id"], announcement.id)

    def test_xiaozhi_interrupt_requeues_delivered_schedule(self) -> None:
        announcement = self._due_announcement()
        with patch("app.device_events._agent_token_ok", return_value=True):
            first = next_announcement(
                self.device.device_uid,
                self.session,
                "token",
            )
        self.assertIsNotNone(first["announcement"])
        self.session.refresh(announcement)
        self.assertEqual(announcement.status, "delivered")

        _process_xiaozhi_state(
            self.session,
            self.device,
            XiaozhiStateCallback(
                device_uid=self.device.device_uid,
                state="listening",
            ),
        )
        self.session.refresh(announcement)
        self.assertEqual(announcement.status, "pending")
        self.assertIsNone(announcement.delivered_at)


if __name__ == "__main__":
    unittest.main()