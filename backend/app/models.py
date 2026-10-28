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
    avatar_url: str | None = Field(default=None, max_length=500)
    gender: str | None = Field(default=None, max_length=16)
    birth_date: date | None = None
    emergency_contact_name: str | None = Field(default=None, max_length=80)
    emergency_contact_phone: str | None = Field(default=None, max_length=32)
    allergy_notes: str | None = Field(default=None, max_length=500)
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

class ActivationRequest(SQLModel, table=True):
    __tablename__ = "activation_requests"

    id: int | None = Field(default=None, primary_key=True)
    device_id: str = Field(index=True, unique=True, max_length=80)
    code_hash: str = Field(max_length=128)
    secret_hash: str = Field(max_length=128)
    elder_id: int | None = Field(default=None, foreign_key="users.id", index=True)
    claimed_at: datetime | None = None
    expires_at: datetime = Field(nullable=False)
    created_at: datetime = Field(default_factory=datetime.utcnow, nullable=False)


class AuthDevice(SQLModel, table=True):
    __tablename__ = "auth_devices"

    id: int | None = Field(default=None, primary_key=True)
    user_id: int = Field(foreign_key="users.id", index=True)
    device_id: str = Field(index=True, unique=True, max_length=80)
    platform: str = Field(default="unknown", max_length=32)
    refresh_token_hash: str = Field(max_length=128)
    last_seen_at: datetime = Field(default_factory=datetime.utcnow, nullable=False)
    expires_at: datetime | None = None
    revoked_at: datetime | None = None
    created_at: datetime = Field(default_factory=datetime.utcnow, nullable=False)


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


class InstructionReviewStatus(str, Enum):
    pending = "pending"
    approved = "approved"
    rejected = "rejected"
    superseded = "superseded"


class DrugInstruction(SQLModel, table=True):
    __tablename__ = "drug_instructions"

    id: int | None = Field(default=None, primary_key=True)
    name: str = Field(index=True, max_length=120)
    aliases: str | None = Field(default=None, max_length=300)
    specification: str | None = Field(default=None, max_length=160)
    manufacturer: str | None = Field(default=None, max_length=160)
    approval_number: str | None = Field(default=None, index=True, max_length=80)
    dosage: str | None = Field(default=None, max_length=2000)
    contraindications: str | None = Field(default=None, max_length=2000)
    precautions: str | None = Field(default=None, max_length=2000)
    adverse_reactions: str | None = Field(default=None, max_length=2000)
    interactions: str | None = Field(default=None, max_length=2000)
    source_url: str = Field(max_length=1000)
    source_type: str = Field(default="nmpa", max_length=60)
    source_file_path: str | None = Field(default=None, max_length=500)
    document_date: date | None = None
    retrieved_at: datetime = Field(default_factory=datetime.utcnow, nullable=False)
    file_hash: str = Field(index=True, max_length=128)
    version: str = Field(default="1", max_length=80)
    review_status: InstructionReviewStatus = Field(default=InstructionReviewStatus.pending, index=True)
    reviewed_by: int | None = Field(default=None, foreign_key="users.id")
    reviewed_at: datetime | None = None
    supersedes_id: int | None = Field(default=None, foreign_key="drug_instructions.id")
    effective_until: date | None = None
    raw_excerpt: str | None = Field(default=None, max_length=6000)
    created_at: datetime = Field(default_factory=datetime.utcnow, nullable=False)
    updated_at: datetime = Field(default_factory=datetime.utcnow, nullable=False)


class FaceConsent(SQLModel, table=True):
    __tablename__ = "face_consents"

    id: int | None = Field(default=None, primary_key=True)
    user_id: int = Field(foreign_key="users.id", unique=True, index=True)
    version: str = Field(default="v1", max_length=40)
    agreed_at: datetime = Field(default_factory=datetime.utcnow, nullable=False)
    client_ip: str | None = Field(default=None, max_length=80)
    user_agent: str | None = Field(default=None, max_length=300)


class FaceProfile(SQLModel, table=True):
    __tablename__ = "face_profiles"

    id: int | None = Field(default=None, primary_key=True)
    user_id: int = Field(foreign_key="users.id", unique=True, index=True)
    provider: str = Field(default="tencent", max_length=40)
    person_id_encrypted: str = Field(max_length=1000)
    face_id_encrypted: str | None = Field(default=None, max_length=1000)
    status: str = Field(default="active", index=True, max_length=32)
    created_at: datetime = Field(default_factory=datetime.utcnow, nullable=False)
    updated_at: datetime = Field(default_factory=datetime.utcnow, nullable=False)
    last_verified_at: datetime | None = None


class FaceLoginAttempt(SQLModel, table=True):
    __tablename__ = "face_login_attempts"

    id: int | None = Field(default=None, primary_key=True)
    device_key: str = Field(index=True, max_length=120)
    client_ip: str | None = Field(default=None, max_length=80)
    success: bool = Field(default=False, index=True)
    score: int | None = None
    reason: str | None = Field(default=None, max_length=120)
    matched_user_id: int | None = Field(default=None, foreign_key="users.id")
    created_at: datetime = Field(default_factory=datetime.utcnow, nullable=False, index=True)


class FaceLoginLock(SQLModel, table=True):
    __tablename__ = "face_login_locks"

    id: int | None = Field(default=None, primary_key=True)
    device_key: str = Field(unique=True, index=True, max_length=120)
    failures: int = Field(default=0, ge=0)
    blocked_until: datetime | None = None
    updated_at: datetime = Field(default_factory=datetime.utcnow, nullable=False)


class SmsLoginCode(SQLModel, table=True):
    __tablename__ = "sms_login_codes"

    id: int | None = Field(default=None, primary_key=True)
    phone: str = Field(index=True, max_length=32)
    code_hash: str = Field(max_length=128)
    expires_at: datetime = Field(nullable=False, index=True)
    attempts: int = Field(default=0, ge=0)
    used_at: datetime | None = None
    created_at: datetime = Field(default_factory=datetime.utcnow, nullable=False, index=True)


class AuditLog(SQLModel, table=True):
    __tablename__ = "audit_logs"
    id: int | None = Field(default=None, primary_key=True)
    user_id: int | None = Field(default=None, foreign_key="users.id", index=True)
    action: str = Field(max_length=80, index=True)
    resource_type: str = Field(max_length=80)
    resource_id: int | None = None
    detail: str | None = Field(default=None, max_length=1000)
    created_at: datetime = Field(default_factory=datetime.utcnow, nullable=False, index=True)
