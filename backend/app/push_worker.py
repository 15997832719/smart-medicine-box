
from datetime import datetime, timedelta
from pathlib import Path
import json

from sqlmodel import Session, select

from app.database import engine, init_db
from app.models import DeviceToken, Medicine, Reminder
from app.push import send_push

STATE = Path(__file__).resolve().parents[1] / ".push-delivery-state.json"


def run() -> int:
    init_db()
    now = datetime.now()
    minute = now.replace(second=0, microsecond=0)
    state = {}
    if STATE.exists():
        try: state = json.loads(STATE.read_text(encoding="utf-8"))
        except Exception: state = {}
    sent = 0
    with Session(engine) as session:
        reminders = session.exec(select(Reminder).where(Reminder.enabled.is_(True))).all()
        for reminder in reminders:
            due = datetime.combine(now.date(), reminder.remind_time)
            if abs((due - minute).total_seconds()) > 60:
                continue
            key = f"{reminder.id}:{minute.isoformat()}"
            if state.get(str(reminder.id)) == key:
                continue
            tokens = session.exec(select(DeviceToken.registration_id).where(DeviceToken.user_id == reminder.owner_id)).all()
            if not tokens:
                continue
            medicine = session.get(Medicine, reminder.medicine_id)
            name = medicine.name if medicine else reminder.title
            body = f"该服用{name}了" + (f"，剂量：{reminder.dose}" if reminder.dose else "")
            if send_push(list(tokens), "智能药箱用药提醒", body):
                state[str(reminder.id)] = key
                sent += 1
    STATE.write_text(json.dumps(state, ensure_ascii=False), encoding="utf-8")
    return sent


if __name__ == "__main__":
    print(f"sent={run()}")
