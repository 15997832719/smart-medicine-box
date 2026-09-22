from pathlib import Path
base = Path(r'D:\smart-medicine-box')

def patch(path, pairs):
    text = path.read_text(encoding='utf-8')
    for old, new, expected in pairs:
        count = text.count(old)
        if count != expected:
            raise SystemExit(f'{path}: count={count}, expected={expected}: {old[:100]}')
        text = text.replace(old, new)
    path.write_text(text, encoding='utf-8')

patch(base / 'backend/app/models.py', [
    ("    remind_time: time\n    frequency: ReminderFrequency = ReminderFrequency.daily", "    remind_time: time\n    schedule_date: date | None = Field(default=None, index=True)\n    frequency: ReminderFrequency = ReminderFrequency.daily", 1),
])

patch(base / 'backend/app/schemas.py', [
    ("class ReminderCreate(BaseModel):\n    medicine_id: int\n    title: str = Field(min_length=1, max_length=120)\n    dose: str | None = None\n    remind_time: time\n", "class ReminderCreate(BaseModel):\n    medicine_id: int\n    title: str = Field(min_length=1, max_length=120)\n    dose: str | None = None\n    remind_time: time\n    schedule_date: date | None = None\n", 1),
    ("class ReminderUpdate(BaseModel):\n    title: str | None = Field(default=None, min_length=1, max_length=120)\n    dose: str | None = None\n    remind_time: time | None = None\n", "class ReminderUpdate(BaseModel):\n    title: str | None = Field(default=None, min_length=1, max_length=120)\n    dose: str | None = None\n    remind_time: time | None = None\n    schedule_date: date | None = None\n", 1),
    ("class ScheduleUpdate(BaseModel):\n    medicine_id: int | None = None\n    title: str | None = Field(default=None, min_length=1, max_length=120)\n    dose: str | None = None\n    remind_time: time | None = None\n", "class ScheduleUpdate(BaseModel):\n    medicine_id: int | None = None\n    title: str | None = Field(default=None, min_length=1, max_length=120)\n    dose: str | None = None\n    remind_time: time | None = None\n    schedule_date: date | None = None\n", 1),
])

patch(base / 'backend/app/database.py', [
    ('            {"version": "owner-isolation-v1"},', '            {"version": "owner-isolation-v1"},\n        )\n        connection.execute(\n            text("INSERT OR IGNORE INTO schema_migrations(version, applied_at) VALUES (:version, CURRENT_TIMESTAMP)"),\n            {"version": "schedule-date-v1"},', 1),
    ("        if \"source_type\" not in medicine_columns:\n            connection.execute(text('ALTER TABLE \"medicine\" ADD COLUMN \"source_type\" VARCHAR(40)'))", "        if \"source_type\" not in medicine_columns:\n            connection.execute(text('ALTER TABLE \"medicine\" ADD COLUMN \"source_type\" VARCHAR(40)'))\n        reminder_columns = {item[\"name\"] for item in inspector.get_columns(\"reminder\")} if \"reminder\" in inspector.get_table_names() else set()\n        if \"schedule_date\" not in reminder_columns:\n            connection.execute(text('ALTER TABLE \"reminder\" ADD COLUMN \"schedule_date\" DATE'))", 1),
])

routers = base / 'backend/app/routers.py'
patch(routers, [
    ("def _reminder_read(reminder: Reminder) -> ReminderRead:\n    data = reminder.model_dump()\n    data[\"user_id\"] = reminder.owner_id\n    return ReminderRead(**data)\n", "def _reminder_read(reminder: Reminder) -> ReminderRead:\n    data = reminder.model_dump()\n    data[\"user_id\"] = reminder.owner_id\n    return ReminderRead(**data)\n\n\ndef _schedule_matches_day(reminder: Reminder, day: date) -> bool:\n    return reminder.schedule_date is None or reminder.schedule_date == day\n", 1),
    ("    if not reminder:\n        raise HTTPException(status_code=404, detail=\"Schedule not found\")\n    medicine = _medicine_query(session, reminder.owner_id or 0, reminder.medicine_id)", "    if not reminder:\n        raise HTTPException(status_code=404, detail=\"Schedule not found\")\n    if reminder.schedule_date is not None and reminder.schedule_date > date.today():\n        raise HTTPException(status_code=400, detail=\"Schedule date is in the future\")\n    medicine = _medicine_query(session, reminder.owner_id or 0, reminder.medicine_id)", 1),
    ("    reminders = session.exec(\n        select(Reminder).where(Reminder.owner_id == owner_id, Reminder.enabled.is_(True))\n    ).all()\n    for reminder in reminders:\n        due_at = datetime.combine(now.date(), reminder.remind_time)", "    reminders = [\n        reminder\n        for reminder in session.exec(\n            select(Reminder).where(Reminder.owner_id == owner_id, Reminder.enabled.is_(True))\n        ).all()\n        if _schedule_matches_day(reminder, now.date())\n    ]\n    for reminder in reminders:\n        due_at = datetime.combine(now.date(), reminder.remind_time)", 1),
    ("    reminders = session.exec(select(Reminder).where(Reminder.owner_id == owner_id, Reminder.enabled.is_(True))).all()\n", "    reminders = [\n        reminder\n        for reminder in session.exec(\n            select(Reminder).where(Reminder.owner_id == owner_id, Reminder.enabled.is_(True))\n        ).all()\n        if _schedule_matches_day(reminder, today)\n    ]\n", 1),
    ("    reminders = session.exec(\n        select(Reminder)\n        .where(Reminder.owner_id == owner_id, Reminder.enabled.is_(True))\n        .order_by(Reminder.remind_time)\n    ).all()\n    items: list[str] = []", "    reminders = [\n        reminder\n        for reminder in session.exec(\n            select(Reminder)\n            .where(Reminder.owner_id == owner_id, Reminder.enabled.is_(True))\n            .order_by(Reminder.remind_time)\n        ).all()\n        if _schedule_matches_day(reminder, date.today())\n    ]\n    items: list[str] = []", 1),
    ("    reminders = session.exec(\n        select(Reminder)\n        .where(Reminder.owner_id == owner_id, Reminder.enabled.is_(True))\n        .order_by(Reminder.remind_time)\n    ).all()\n    if not reminders:", "    reminders = [\n        reminder\n        for reminder in session.exec(\n            select(Reminder)\n            .where(Reminder.owner_id == owner_id, Reminder.enabled.is_(True))\n            .order_by(Reminder.remind_time)\n        ).all()\n        if _schedule_matches_day(reminder, date.today())\n    ]\n    if not reminders:", 1),
])

dueros = base / 'backend/app/dueros.py'
patch(dueros, [
    ("    reminders = session.exec(query).all()\n    items: list[str] = []", "    reminders = [reminder for reminder in session.exec(query).all() if reminder.schedule_date is None or reminder.schedule_date == date.today()]\n    items: list[str] = []", 1),
    ("    reminders = session.exec(query).all()\n    if not reminders:", "    reminders = [reminder for reminder in session.exec(query).all() if reminder.schedule_date is None or reminder.schedule_date == date.today()]\n    if not reminders:", 1),
])
print('schedule date backend patch applied')
