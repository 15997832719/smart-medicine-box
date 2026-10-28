from collections.abc import Generator

from sqlalchemy import inspect, text
from sqlmodel import Session, SQLModel, create_engine

from app.config import get_settings


settings = get_settings()
engine = create_engine(settings.database_url, echo=False, connect_args={"check_same_thread": False})


def init_db() -> None:
    SQLModel.metadata.create_all(engine)
    _migrate_ownership_columns()
    _migrate_user_profile_columns()
    _migrate_device_face_identity()
    _record_schema_version()


def _record_schema_version() -> None:

    with engine.begin() as connection:
        connection.execute(text("CREATE TABLE IF NOT EXISTS schema_migrations (version TEXT PRIMARY KEY, applied_at TEXT NOT NULL)"))
        connection.execute(
            text("INSERT OR IGNORE INTO schema_migrations(version, applied_at) VALUES (:version, CURRENT_TIMESTAMP)"),
            {"version": "owner-isolation-v1"},
        )
        connection.execute(
            text("INSERT OR IGNORE INTO schema_migrations(version, applied_at) VALUES (:version, CURRENT_TIMESTAMP)"),
            {"version": "schedule-date-v1"},
        )
        connection.execute(
            text("INSERT OR IGNORE INTO schema_migrations(version, applied_at) VALUES (:version, CURRENT_TIMESTAMP)"),
            {"version": "device-face-identity-v1"},
        )
        connection.execute(
            text("INSERT OR IGNORE INTO schema_migrations(version, applied_at) VALUES (:version, CURRENT_TIMESTAMP)"),
            {"version": "user-profile-v1"},
        )


def _migrate_ownership_columns() -> None:






    table_columns = {
        "medicine": "owner_id",
        "reminder": "owner_id",
        "intakelog": "owner_id",
    }
    inspector = inspect(engine)
    with engine.begin() as connection:
        for table, column in table_columns.items():
            if table not in inspector.get_table_names():
                continue
            existing = {item["name"] for item in inspector.get_columns(table)}
            if column not in existing:
                connection.execute(text(f'ALTER TABLE "{table}" ADD COLUMN "{column}" INTEGER'))
        medicine_columns = {item["name"] for item in inspector.get_columns("medicine")} if "medicine" in inspector.get_table_names() else set()
        if "information_source" not in medicine_columns:
            connection.execute(text('ALTER TABLE "medicine" ADD COLUMN "information_source" VARCHAR(300)'))
        if "source_type" not in medicine_columns:
            connection.execute(text('ALTER TABLE "medicine" ADD COLUMN "source_type" VARCHAR(40)'))
        reminder_columns = {item["name"] for item in inspector.get_columns("reminder")} if "reminder" in inspector.get_table_names() else set()
        if "schedule_date" not in reminder_columns:
            connection.execute(text('ALTER TABLE "reminder" ADD COLUMN "schedule_date" DATE'))
        if "reminder" in inspector.get_table_names() and "medicine" in inspector.get_table_names():
            connection.execute(text('UPDATE reminder SET title = (SELECT name FROM medicine WHERE medicine.id = reminder.medicine_id) WHERE EXISTS (SELECT 1 FROM medicine WHERE medicine.id = reminder.medicine_id)'))


def _migrate_user_profile_columns() -> None:
    inspector = inspect(engine)
    if "users" not in inspector.get_table_names():
        return
    columns = {item["name"] for item in inspector.get_columns("users")}
    additions = {
        "avatar_url": "VARCHAR(500)",
        "gender": "VARCHAR(16)",
        "birth_date": "DATE",
        "emergency_contact_name": "VARCHAR(80)",
        "emergency_contact_phone": "VARCHAR(32)",
        "allergy_notes": "VARCHAR(500)",
    }
    with engine.begin() as connection:
        for column, sql_type in additions.items():
            if column not in columns:
                connection.execute(text(f'ALTER TABLE "users" ADD COLUMN "{column}" {sql_type}'))


def _migrate_device_face_identity() -> None:
    inspector = inspect(engine)
    if "device_face_profiles" not in inspector.get_table_names():
        return
    columns = {item["name"] for item in inspector.get_columns("device_face_profiles")}
    with engine.begin() as connection:
        if "announce_user_id" not in columns:
            connection.execute(text('ALTER TABLE "device_face_profiles" ADD COLUMN "announce_user_id" INTEGER'))
        connection.execute(
            text(
                'UPDATE "device_face_profiles" SET "announce_user_id" = "user_id" '
                'WHERE "announce_user_id" IS NULL AND "role" IN (\'elder\', \'child\')'
            )
        )


def get_session() -> Generator[Session, None, None]:
    with Session(engine) as session:
        yield session
