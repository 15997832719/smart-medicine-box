"""Create device announcements for medication schedules.

The scheduler uses the server's local clock because medication times in the app
are entered as local wall-clock times.  Xiaozhi arbitration remains in
``device_events.next_announcement``: a due announcement is queued here and the
ESP32 only receives it when Xiaozhi is idle.
"""
from __future__ import annotations

import asyncio
import logging
from datetime import datetime, timedelta

from sqlmodel import Session, select

from app.database import engine
from app.device_agent import MedicineBoxDevice
from app.device_events import DeviceAnnouncement
from app.models import Medicine, Reminder

logger = logging.getLogger(__name__)

SCHEDULE_SOURCE = "schedule"
SCHEDULE_WINDOW_SECONDS = 90
SCHEDULE_ANNOUNCEMENT_TTL_SECONDS = 10 * 60
SCHEDULER_POLL_SECONDS = 10.0


def _reminder_is_due(reminder: Reminder, now: datetime) -> bool:
    if not reminder.enabled:
        return False
    if reminder.schedule_date is not None and reminder.schedule_date != now.date():
        return False
    due_at = datetime.combine(now.date(), reminder.remind_time)
    elapsed = (now - due_at).total_seconds()
    return 0 <= elapsed <= SCHEDULE_WINDOW_SECONDS


def _announcement_text(reminder: Reminder, medicine: Medicine | None) -> str:
    name = medicine.name if medicine else reminder.title
    dose = f"，{reminder.dose}" if reminder.dose else ""
    return f"用药提醒：现在是{reminder.remind_time.strftime('%H:%M')}，请服用{name}{dose}。"


def enqueue_due_medication_announcements(
    session: Session,
    *,
    now: datetime | None = None,
) -> list[int]:
    """Queue one announcement per due reminder and device.

    ``dedupe_key`` protects against duplicate scheduler runs and multiple
    backend workers: each reminder can create at most one announcement per
    device per calendar day.
    """
    local_now = now or datetime.now()
    created_ids: list[int] = []
    reminders = session.exec(select(Reminder).where(Reminder.enabled.is_(True))).all()
    for reminder in reminders:
        if reminder.owner_id is None or not _reminder_is_due(reminder, local_now):
            continue
        devices = session.exec(
            select(MedicineBoxDevice).where(MedicineBoxDevice.owner_id == reminder.owner_id)
        ).all()
        medicine = session.get(Medicine, reminder.medicine_id)
        for device in devices:
            if device.id is None:
                continue
            dedupe_key = (
                f"schedule:{device.id}:{reminder.id}:{local_now.date().isoformat()}"
            )
            existing = session.exec(
                select(DeviceAnnouncement).where(
                    DeviceAnnouncement.dedupe_key == dedupe_key
                )
            ).first()
            if existing is not None:
                continue
            announcement = DeviceAnnouncement(
                device_id=device.id,
                user_id=reminder.owner_id,
                text=_announcement_text(reminder, medicine),
                source=SCHEDULE_SOURCE,
                dedupe_key=dedupe_key,
                expires_at=datetime.utcnow()
                + timedelta(seconds=SCHEDULE_ANNOUNCEMENT_TTL_SECONDS),
            )
            session.add(announcement)
            session.flush()
            if announcement.id is not None:
                created_ids.append(announcement.id)
    session.commit()
    return created_ids


async def medication_scheduler_loop() -> None:
    """Run the schedule scanner for the lifetime of the FastAPI process."""
    while True:
        try:
            with Session(engine) as session:
                created = enqueue_due_medication_announcements(session)
            if created:
                logger.info("queued scheduled medication announcements ids=%s", created)
        except asyncio.CancelledError:
            raise
        except Exception:
            logger.exception("scheduled medication scan failed")
        await asyncio.sleep(SCHEDULER_POLL_SECONDS)
