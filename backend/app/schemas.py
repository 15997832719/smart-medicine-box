from datetime import date, datetime, time

from typing import Literal

from pydantic import BaseModel, Field

from app.models import ReminderFrequency


class UserRead(BaseModel):
    id: int
    phone: str
    nickname: str | None = None
    role: Literal["elder", "child"]
    avatar_url: str | None = None
    gender: Literal["male", "female", "other"] | None = None
    birth_date: date | None = None
    emergency_contact_name: str | None = None
    emergency_contact_phone: str | None = None
    allergy_notes: str | None = None


class UserProfileUpdate(BaseModel):
    nickname: str | None = Field(default=None, min_length=1, max_length=80)
    gender: Literal["male", "female", "other"] | None = None
    birth_date: date | None = None
    emergency_contact_name: str | None = Field(default=None, max_length=80)
    emergency_contact_phone: str | None = Field(default=None, max_length=32)
    allergy_notes: str | None = Field(default=None, max_length=500)


class RegisterRequest(BaseModel):
    phone: str = Field(min_length=6, max_length=32)
    password: str = Field(min_length=6, max_length=128)
    role: Literal["elder", "child"] = "elder"
    nickname: str | None = Field(default=None, max_length=80)


class LoginRequest(BaseModel):
    phone: str = Field(min_length=6, max_length=32)
    password: str = Field(min_length=1, max_length=128)


class AccountDeleteRequest(BaseModel):
    password: str = Field(min_length=1, max_length=128)


class DeviceTokenRequest(BaseModel):
    registration_id: str = Field(min_length=8, max_length=255)
    platform: str = Field(default="android", max_length=32)


class DeviceCredentialRequest(BaseModel):
    device_id: str | None = Field(default=None, max_length=80)
    platform: str = Field(default="unknown", max_length=32)


class DeviceCredentialResponse(BaseModel):
    device_id: str
    device_secret: str
    platform: str


class DeviceLoginRequest(BaseModel):
    device_id: str = Field(min_length=4, max_length=80)
    device_secret: str = Field(min_length=16, max_length=200)
    platform: str = Field(default="unknown", max_length=32)


class AuthResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    user: UserRead
    device_id: str | None = None


class ActivationStartResponse(BaseModel):
    activation_id: int
    activation_code: str
    device_id: str
    device_secret: str
    expires_at: datetime


class ActivationClaimRequest(BaseModel):
    activation_id: int | None = None
    activation_code: str = Field(min_length=6, max_length=6)
    nickname: str = Field(default='??', min_length=1, max_length=80)


class ActivationExchangeRequest(BaseModel):
    activation_id: int
    device_secret: str = Field(min_length=16, max_length=200)
    platform: str = Field(default="unknown", max_length=32)


class AuthDeviceRead(BaseModel):
    id: int
    device_id: str
    platform: str
    last_seen_at: datetime
    created_at: datetime
    revoked_at: datetime | None = None


class BindFamilyRequest(BaseModel):
    bind_code: str = Field(min_length=4, max_length=16)


class BindCodeResponse(BaseModel):
    bind_code: str
    expires_at: datetime


class FamilyMemberRead(UserRead):
    linked_at: datetime | None = None


class FamilyRead(BaseModel):
    elders: list[FamilyMemberRead] = []
    children: list[FamilyMemberRead] = []


class MedicineCreate(BaseModel):
    name: str = Field(min_length=1, max_length=80)
    alias: str | None = None
    category: str | None = None
    manufacturer: str | None = None
    description: str | None = None
    dosage: str | None = None
    precautions: str | None = None
    conflict_tags: list[str] = []
    stock_count: int = Field(default=0, ge=0)
    low_stock_threshold: int = Field(default=3, ge=0)
    expire_date: date | None = None
    information_source: str | None = Field(default=None, max_length=300)
    source_type: str | None = Field(default=None, max_length=40)


class MedicineUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=80)
    alias: str | None = None
    category: str | None = None
    manufacturer: str | None = None
    description: str | None = None
    dosage: str | None = None
    precautions: str | None = None
    conflict_tags: list[str] | None = None
    stock_count: int | None = Field(default=None, ge=0)
    low_stock_threshold: int | None = Field(default=None, ge=0)
    expire_date: date | None = None
    information_source: str | None = Field(default=None, max_length=300)
    source_type: str | None = Field(default=None, max_length=40)


class MedicineRead(MedicineCreate):
    id: int
    owner_id: int | None = None
    user_id: int | None = None
    created_at: datetime
    updated_at: datetime


class ReminderCreate(BaseModel):
    medicine_id: int
    title: str = Field(min_length=1, max_length=120)
    dose: str | None = None
    remind_time: time
    schedule_date: date | None = None
    frequency: ReminderFrequency = ReminderFrequency.daily
    enabled: bool = True
    note: str | None = None


class ReminderUpdate(BaseModel):
    title: str | None = Field(default=None, min_length=1, max_length=120)
    dose: str | None = None
    remind_time: time | None = None
    schedule_date: date | None = None
    frequency: ReminderFrequency | None = None
    enabled: bool | None = None
    note: str | None = None


class ReminderRead(ReminderCreate):
    id: int
    owner_id: int | None = None
    user_id: int | None = None
    created_at: datetime


class IntakeLogCreate(BaseModel):
    medicine_id: int
    dose: str | None = None
    note: str | None = None
    taken_at: datetime | None = None


class IntakeLogRead(BaseModel):
    id: int
    owner_id: int | None = None
    user_id: int | None = None
    medicine_id: int
    dose: str | None
    note: str | None
    taken_at: datetime


class AlertRead(BaseModel):
    type: str
    severity: str
    medicine_id: int
    medicine_name: str
    message: str


class ConflictCheckRequest(BaseModel):
    medicine_ids: list[int] = []
    names: list[str] = []


class ConflictRead(BaseModel):
    medicine_a: str
    medicine_b: str
    reason: str
    severity: str = "medium"


class RecognizeResult(BaseModel):
    medicine: MedicineCreate
    confidence: float
    source: str


class InstructionParseRequest(BaseModel):
    text: str = Field(min_length=1)


class InstructionParseResult(BaseModel):
    name: str | None = None
    dosage: str | None = None
    precautions: list[str] = []
    conflict_tags: list[str] = []
    summary: str


class ScheduleUpdate(BaseModel):
    medicine_id: int | None = None
    title: str | None = Field(default=None, min_length=1, max_length=120)
    dose: str | None = None
    remind_time: time | None = None
    schedule_date: date | None = None
    frequency: ReminderFrequency | None = None
    enabled: bool | None = None
    is_active: bool | None = None
    note: str | None = None


class LogConfirmRequest(BaseModel):
    schedule_id: int
    confirm_method: str = "button"


class DrugInstructionCreate(BaseModel):
    name: str = Field(min_length=1, max_length=120)
    aliases: str | None = Field(default=None, max_length=300)
    specification: str | None = Field(default=None, max_length=160)
    manufacturer: str | None = Field(default=None, max_length=160)
    approval_number: str | None = Field(default=None, max_length=80)
    dosage: str | None = Field(default=None, max_length=2000)
    contraindications: str | None = Field(default=None, max_length=2000)
    precautions: str | None = Field(default=None, max_length=2000)
    adverse_reactions: str | None = Field(default=None, max_length=2000)
    interactions: str | None = Field(default=None, max_length=2000)
    source_url: str = Field(min_length=1, max_length=1000)
    source_type: str = Field(default="nmpa", max_length=60)
    source_file_path: str | None = Field(default=None, max_length=500)
    document_date: date | None = None
    version: str = Field(default="1", max_length=80)
    raw_excerpt: str | None = Field(default=None, max_length=6000)


class DrugInstructionRead(DrugInstructionCreate):
    id: int
    retrieved_at: datetime
    file_hash: str
    review_status: str
    reviewed_by: int | None = None
    reviewed_at: datetime | None = None
    supersedes_id: int | None = None
    effective_until: date | None = None
    created_at: datetime
    updated_at: datetime


class FaceConsentRequest(BaseModel):
    version: str = Field(default="v1", max_length=40)


class FaceStatusRead(BaseModel):
    enabled: bool
    enrolled: bool
    provider: str | None = None
    status: str | None = None
    last_verified_at: datetime | None = None


class SmsSendRequest(BaseModel):
    phone: str = Field(min_length=6, max_length=32)


class SmsLoginRequest(BaseModel):
    phone: str = Field(min_length=6, max_length=32)
    code: str = Field(min_length=4, max_length=8)


class TtsRequest(BaseModel):
    text: str = Field(min_length=1, max_length=600)


class VoiceIntentRequest(BaseModel):
    text: str = Field(min_length=1, max_length=300)
    schedule_id: int | None = None
    session_id: str | None = Field(default=None, max_length=80)
    owner_id: int | None = Field(default=None, ge=1)
    trace_id: str | None = Field(default=None, max_length=80)
