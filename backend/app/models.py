from datetime import date, datetime, time
from enum import Enum

from sqlmodel import Field, SQLModel


class ReminderFrequency(str, Enum):
    once = "once"
    daily = "daily"
    weekly = "weekly"


class UserRole(str, Enum):
    elder = "elder"
    child = "child"


class User(SQLModel, table=True):
    __tablename__ = "users"

    id: int | None = Field(default=None, primary_key=True)
    phone: str = Field(index=True, unique=True, max_length=32)
    password_hash: str = Field(max_length=300)
    role: UserRole = Field(default=UserRole.elder, index=True)
    nickname: str | None = Field(default=None, max_length=80)
    bind_code_hash: str | None = Field(default=None, max_length=128)
    bind_code_expires_at: datetime | None = None
    is_active: bool = True
    created_at: datetime = Field(default_factory=datetime.utcnow, nullable=False)
    updated_at: datetime = Field(default_factory=datetime.utcnow, nullable=False)


class DeviceToken(SQLModel, table=True):

    __tablename__ = "device_tokens"
    id: int | None = Field(default=None, primary_key=True)
    user_id: int = Field(foreign_key="users.id", index=True)
    registration_id: str = Field(index=True, max_length=255)
    platform: str = Field(default="android", max_length=32)
    updated_at: datetime = Field(default_factory=datetime.utcnow, nullable=False)

class SpeakerBinding(SQLModel, table=True):
    __tablename__ = "speaker_bindings"
    id: int | None = Field(default=None, primary_key=True)
    speaker_id: str = Field(index=True, max_length=255, unique=True)
    platform: str = Field(default="dueros", max_length=40)
    user_id: int = Field(foreign_key="users.id", index=True)
    pairing_code: str | None = Field(default=None, max_length=12)
    code_expires_at: datetime | None = None
    created_at: datetime = Field(default_factory=datetime.utcnow, nullable=False)


class FamilyLink(SQLModel, table=True):
    __tablename__ = "family_links"

    id: int | None = Field(default=None, primary_key=True)
    elder_id: int = Field(foreign_key="users.id", index=True)
    child_id: int = Field(foreign_key="users.id", index=True)
    created_at: datetime = Field(default_factory=datetime.utcnow, nullable=False)


class MedicineBase(SQLModel):
    name: str = Field(index=True, min_length=1, max_length=80)
    alias: str | None = Field(default=None, max_length=120)
    category: str | None = Field(default=None, max_length=80)
    manufacturer: str | None = Field(default=None, max_length=120)
    description: str | None = Field(default=None, max_length=500)
    dosage: str | None = Field(default=None, max_length=160)
    precautions: str | None = Field(default=None, max_length=500)
    conflict_tags: str | None = Field(default=None, max_length=300)
    stock_count: int = Field(default=0, ge=0)
    low_stock_threshold: int = Field(default=3, ge=0)
    expire_date: date | None = None
    information_source: str | None = Field(default=None, max_length=300)
    source_type: str | None = Field(default=None, max_length=40)


class Medicine(MedicineBase, table=True):
    id: int | None = Field(default=None, primary_key=True)
    owner_id: int | None = Field(default=None, foreign_key="users.id", index=True)
    created_at: datetime = Field(default_factory=datetime.utcnow, nullable=False)
    updated_at: datetime = Field(default_factory=datetime.utcnow, nullable=False)


class ReminderBase(SQLModel):
    medicine_id: int = Field(foreign_key="medicine.id")
    title: str = Field(min_length=1, max_length=120)
    dose: str | None = Field(default=None, max_length=80)
    remind_time: time
    schedule_date: date | None = Field(default=None, index=True)
    frequency: ReminderFrequency = ReminderFrequency.daily
    enabled: bool = True
    note: str | None = Field(default=None, max_length=300)


class Reminder(ReminderBase, table=True):
    id: int | None = Field(default=None, primary_key=True)
    owner_id: int | None = Field(default=None, foreign_key="users.id", index=True)
    created_at: datetime = Field(default_factory=datetime.utcnow, nullable=False)


class IntakeLog(SQLModel, table=True):
    id: int | None = Field(default=None, primary_key=True)
    owner_id: int | None = Field(default=None, foreign_key="users.id", index=True)
    medicine_id: int = Field(foreign_key="medicine.id")
    taken_at: datetime = Field(default_factory=datetime.utcnow, nullable=False)
    dose: str | None = Field(default=None, max_length=80)
    note: str | None = Field(default=None, max_length=300)


class AuditLog(SQLModel, table=True):
    __tablename__ = "audit_logs"
    id: int | None = Field(default=None, primary_key=True)
    user_id: int | None = Field(default=None, foreign_key="users.id", index=True)
    action: str = Field(max_length=80, index=True)
    resource_type: str = Field(max_length=80)
    resource_id: int | None = None
    detail: str | None = Field(default=None, max_length=1000)
    created_at: datetime = Field(default_factory=datetime.utcnow, nullable=False, index=True)
