from __future__ import annotations

import asyncio
import base64
import json
import logging
import time as _time
from datetime import date, datetime, timedelta
from pathlib import Path
from typing import Any, Literal

from fastapi import APIRouter, Depends, Header, HTTPException, Query, Request, WebSocket, WebSocketDisconnect, status
from app.auth import _bearer_token, _jie_xi_ling_pai, accessible_owner_ids, get_current_user
from pydantic import BaseModel, Field as PydanticField
from sqlmodel import Field, Session, SQLModel, select

from app.auth import accessible_owner_ids, get_current_user
from app.config import get_settings
from app.database import engine, get_session
from app.device_agent import DeviceCommand, DeviceFaceProfile, MedicineBoxDevice, _agent_token_ok
from app.models import FamilyLink, Medicine, Reminder, User

router = APIRouter(prefix="/hardware-devices", tags=["hardware-devices"])
agent_router = APIRouter(prefix="/device-agent", tags=["device-agent"])
logger = logging.getLogger(__name__)

XiaozhiState = Literal["idle", "listening", "speaking"]
Syn6288State = Literal["idle", "speaking", "error"]
PRESENCE_DISTANCE_CM = 150
ANNOUNCEMENT_TTL_SECONDS = 10
XIAOZHI_IDLE_SETTLE_SECONDS = 1.5
PREVIEW_SESSION_SECONDS = 30


class DeviceRuntimeState(SQLModel, table=True):
    __tablename__ = "device_runtime_states"

    id: int | None = Field(default=None, primary_key=True)
    device_id: int = Field(foreign_key="medicine_box_devices.id", unique=True, index=True)
    radar_present: bool = False
    radar_distance_cm: int | None = None
    radar_episode: int = Field(default=0, ge=0)
    xiaozhi_state: str = Field(default="idle", max_length=24)
    syn6288_state: str = Field(default="idle", max_length=24)
    last_xiaozhi_at: datetime | None = None
    last_radar_at: datetime | None = None
    last_syn6288_at: datetime | None = None
    stop_tts_requested_at: datetime | None = None
    last_recognition_user_id: int | None = Field(default=None, foreign_key="users.id")
    last_recognition_at: datetime | None = None
    updated_at: datetime = Field(default_factory=datetime.utcnow, nullable=False)


class DeviceRecognitionEvent(SQLModel, table=True):
    __tablename__ = "device_recognition_events"

    id: int | None = Field(default=None, primary_key=True)
    device_id: int = Field(foreign_key="medicine_box_devices.id", index=True)
    user_id: int | None = Field(default=None, foreign_key="users.id", index=True)
    face_key: str | None = Field(default=None, max_length=80, index=True)
    event_type: str = Field(default="recognized", max_length=32, index=True)
    score: float = Field(default=0.0, ge=0.0, le=1.0)
    radar_episode: int = Field(default=0, ge=0)
    occurred_at: datetime = Field(default_factory=datetime.utcnow, nullable=False, index=True)
    metadata_json: str = Field(default="{}", max_length=12000)
    created_at: datetime = Field(default_factory=datetime.utcnow, nullable=False)


class DeviceTelemetryEvent(SQLModel, table=True):
    __tablename__ = "device_telemetry_events"

    id: int | None = Field(default=None, primary_key=True)
    device_id: int = Field(foreign_key="medicine_box_devices.id", index=True)
    event_type: str = Field(max_length=40, index=True)
    payload_json: str = Field(default="{}", max_length=12000)
    occurred_at: datetime = Field(default_factory=datetime.utcnow, nullable=False, index=True)
    created_at: datetime = Field(default_factory=datetime.utcnow, nullable=False)


class DeviceAnnouncement(SQLModel, table=True):
    __tablename__ = "device_announcements"

    id: int | None = Field(default=None, primary_key=True)
    device_id: int = Field(foreign_key="medicine_box_devices.id", index=True)
    user_id: int | None = Field(default=None, foreign_key="users.id", index=True)
    text: str = Field(max_length=500)
    source: str = Field(default="manual", max_length=40)
    status: str = Field(default="pending", max_length=24, index=True)
    dedupe_key: str | None = Field(default=None, unique=True, index=True, max_length=160)
    reason: str | None = Field(default=None, max_length=200)
    expires_at: datetime = Field(nullable=False, index=True)
    delivered_at: datetime | None = None
    cancelled_at: datetime | None = None
    created_at: datetime = Field(default_factory=datetime.utcnow, nullable=False, index=True)


class DevicePreviewSession(SQLModel, table=True):
    __tablename__ = "device_preview_sessions"

    id: int | None = Field(default=None, primary_key=True)
    device_id: int = Field(foreign_key="medicine_box_devices.id", unique=True, index=True)
    active_until: datetime = Field(nullable=False, index=True)
    updated_at: datetime = Field(default_factory=datetime.utcnow, nullable=False)


class DevicePreviewFrame(SQLModel, table=True):
    __tablename__ = "device_preview_frames"

    id: int | None = Field(default=None, primary_key=True)
    device_id: int = Field(foreign_key="medicine_box_devices.id", unique=True, index=True)
    storage_name: str = Field(max_length=500)
    content_type: str = Field(default="image/jpeg", max_length=80)
    size_bytes: int = Field(default=0, ge=0)
    captured_at: datetime = Field(default_factory=datetime.utcnow, nullable=False, index=True)
    updated_at: datetime = Field(default_factory=datetime.utcnow, nullable=False)


class RecognitionEventCreate(BaseModel):
    device_uid: str
    face_key: str | None = PydanticField(default=None, max_length=80)
    user_id: int | None = PydanticField(default=None, ge=1)
    event_type: Literal["recognized", "unknown", "no_face", "error"] = "recognized"
    score: float = PydanticField(default=0.0, ge=0.0, le=1.0)
    occurred_at: datetime | None = None
    metadata: dict[str, Any] = PydanticField(default_factory=dict)


class RadarEventCreate(BaseModel):
    device_uid: str
    present: bool
    distance_cm: int | None = PydanticField(default=None, ge=0, le=1000)
    moving_cm: int | None = PydanticField(default=None, ge=0, le=1000)
    static_cm: int | None = PydanticField(default=None, ge=0, le=1000)
    occurred_at: datetime | None = None


class XiaozhiStateCallback(BaseModel):
    device_uid: str
    state: XiaozhiState
    event_id: str | None = PydanticField(default=None, max_length=120)


class Syn6288StateCallback(BaseModel):
    device_uid: str
    state: Syn6288State
    announcement_id: int | None = None


class AnnouncementCreate(BaseModel):
    text: str = PydanticField(min_length=1, max_length=300)
    user_id: int | None = PydanticField(default=None, ge=1)
    ttl_seconds: int = PydanticField(default=10, ge=1, le=60)


class PreviewStartResponse(BaseModel):
    active: bool
    active_until: datetime

def _json_dump(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"))


def _json_load(value: str | None, fallback: Any) -> Any:
    if not value:
        return fallback
    try:
        return json.loads(value)
    except Exception:
        return fallback


def _device_for_user(session: Session, user: User, device_id: int) -> MedicineBoxDevice:
    device = session.get(MedicineBoxDevice, device_id)
    if not device or device.owner_id not in accessible_owner_ids(session, user):
        raise HTTPException(status_code=404, detail="设备不存在")
    return device


def _device_by_uid(session: Session, device_uid: str) -> MedicineBoxDevice:
    device = session.exec(select(MedicineBoxDevice).where(MedicineBoxDevice.device_uid == device_uid)).first()
    if not device:
        raise HTTPException(status_code=404, detail="设备未在 App 中添加")
    return device


def _runtime(session: Session, device_id: int) -> DeviceRuntimeState:
    runtime = session.exec(select(DeviceRuntimeState).where(DeviceRuntimeState.device_id == device_id)).first()
    if runtime is None:
        runtime = DeviceRuntimeState(device_id=device_id)
        session.add(runtime)
        session.commit()
        session.refresh(runtime)
    return runtime


def _allowed_device_user_ids(session: Session, device: MedicineBoxDevice) -> set[int]:
    allowed = {device.owner_id}
    links = session.exec(select(FamilyLink).where(FamilyLink.elder_id == device.owner_id)).all()
    allowed.update(link.child_id for link in links)
    return allowed


def _preview_root() -> Path:
    settings = get_settings()
    base = Path(getattr(settings, "device_camera_dir", "data/camera_assets")).expanduser().resolve()
    root = base / "preview"
    root.mkdir(parents=True, exist_ok=True)
    return root


def _preview_path(relative: str) -> Path:
    root = _preview_root()
    target = (root / relative).resolve()
    if target != root and root not in target.parents:
        raise HTTPException(status_code=400, detail="预览帧路径无效")
    return target


def _next_medication_text(session: Session, user_id: int) -> str:
    now = datetime.now()
    reminders = [
        reminder
        for reminder in session.exec(
            select(Reminder)
            .where(Reminder.owner_id == user_id, Reminder.enabled.is_(True))
            .order_by(Reminder.remind_time)
        ).all()
        if reminder.schedule_date is None or reminder.schedule_date == date.today()
    ]
    items: list[tuple[Reminder, Medicine]] = []
    for reminder in reminders:
        medicine = session.get(Medicine, reminder.medicine_id)
        if medicine:
            items.append((reminder, medicine))
    if not items:
        return "今天没有需要服用的药，请注意休息。"
    current = now.time()
    upcoming = [item for item in items if item[0].remind_time >= current]
    reminder, medicine = upcoming[0] if upcoming else items[-1]
    dose = f"，{reminder.dose}" if reminder.dose else ""
    prefix = "下一项用药是" if upcoming else "今天最后一项用药是"
    return f"{prefix}{reminder.remind_time.strftime('%H:%M')}服用{medicine.name}{dose}。"


def _enqueue_medication_announcement(
    session: Session,
    device: MedicineBoxDevice,
    user_id: int,
    episode: int,
) -> DeviceAnnouncement | None:
    if user_id not in _allowed_device_user_ids(session, device):
        return None
    dedupe_key = f"recognition:{device.id}:{episode}:{user_id}"
    existing = session.exec(select(DeviceAnnouncement).where(DeviceAnnouncement.dedupe_key == dedupe_key)).first()
    if existing:
        return existing
    now = datetime.utcnow()
    announcement = DeviceAnnouncement(
        device_id=device.id or 0,
        user_id=user_id,
        text=_next_medication_text(session, user_id),
        source="recognition",
        dedupe_key=dedupe_key,
        expires_at=now + timedelta(seconds=ANNOUNCEMENT_TTL_SECONDS),
    )
    session.add(announcement)
    session.commit()
    session.refresh(announcement)
    return announcement


def _process_radar_event(session: Session, device: MedicineBoxDevice, payload: RadarEventCreate) -> dict[str, Any]:
    runtime = _runtime(session, device.id or 0)
    was_present = runtime.radar_present
    now = payload.occurred_at or datetime.utcnow()
    entered = payload.present and not was_present
    if entered:
        runtime.radar_episode += 1
    runtime.radar_present = payload.present
    runtime.radar_distance_cm = payload.distance_cm
    runtime.last_radar_at = now
    runtime.updated_at = now
    event = DeviceTelemetryEvent(
        device_id=device.id or 0,
        event_type="radar_present" if payload.present else "radar_absent",
        payload_json=_json_dump(payload.model_dump(mode="json")),
        occurred_at=now,
    )
    device.last_seen_at = now
    device.radar_ready = True
    device.updated_at = now
    device.status = "online"
    session.add(runtime)
    session.add(event)
    session.add(device)
    session.commit()
    recognition_command_id = None
    if entered and payload.distance_cm is not None and payload.distance_cm <= PRESENCE_DISTANCE_CM:
        active = session.exec(
            select(DeviceCommand).where(
                DeviceCommand.device_id == device.id,
                DeviceCommand.command_type == "face_recognize",
                DeviceCommand.status.in_(["pending", "claimed"]),
            )
        ).first()
        if active is None:
            recognition_command = DeviceCommand(
                device_id=device.id or 0,
                requested_by=device.owner_id,
                command_type="face_recognize",
                payload_json=_json_dump({"trigger": "radar", "episode": runtime.radar_episode}),
                expires_at=datetime.utcnow() + timedelta(seconds=30),
            )
            session.add(recognition_command)
            session.commit()
            session.refresh(recognition_command)
            recognition_command_id = recognition_command.id
    return {
        "episode": runtime.radar_episode,
        "present": runtime.radar_present,
        "distance_cm": runtime.radar_distance_cm,
        "recognition_command_id": recognition_command_id,
    }


def _process_recognition_event(
    session: Session,
    device: MedicineBoxDevice,
    payload: RecognitionEventCreate,
) -> dict[str, Any]:
    runtime = _runtime(session, device.id or 0)
    profile = None
    if payload.face_key:
        profile = session.exec(
            select(DeviceFaceProfile).where(
                DeviceFaceProfile.device_id == device.id,
                DeviceFaceProfile.face_key == payload.face_key,
                DeviceFaceProfile.status == "active",
            )
        ).first()
    allowed_ids = _allowed_device_user_ids(session, device)
    identity_role = profile.role if profile else None
    user_id: int | None = None
    event_type = payload.event_type
    if profile is not None:
        if identity_role == "stranger":
            event_type = "stranger"
        elif identity_role in {"elder", "child"}:
            target_id = profile.announce_user_id or profile.user_id
            target = session.get(User, target_id)
            if target and target.is_active and target.role.value == identity_role and target_id in allowed_ids:
                user_id = target_id
                event_type = "recognized"
            else:
                event_type = "unknown"
        else:
            event_type = "unknown"
    elif payload.user_id in allowed_ids:
        user_id = payload.user_id
        target = session.get(User, user_id)
        identity_role = target.role.value if target else None
        event_type = "recognized" if payload.event_type == "recognized" else payload.event_type
    elif payload.event_type == "recognized":
        event_type = "unknown"
    occurred_at = payload.occurred_at or datetime.utcnow()
    event = DeviceRecognitionEvent(
        device_id=device.id or 0,
        user_id=user_id,
        face_key=payload.face_key,
        event_type=event_type,
        score=payload.score,
        radar_episode=runtime.radar_episode,
        occurred_at=occurred_at,
        metadata_json=_json_dump({
            **(payload.metadata or {}),
            "identity_role": identity_role,
            "face_profile_user_id": profile.user_id if profile else None,
        }),
    )
    runtime.last_recognition_user_id = user_id
    runtime.last_recognition_at = occurred_at
    runtime.updated_at = occurred_at
    device.last_seen_at = datetime.utcnow()
    device.updated_at = device.last_seen_at
    device.status = "online"
    session.add(event)
    session.add(runtime)
    session.add(device)
    session.commit()
    session.refresh(event)

    announcement = None
    if (
        user_id is not None
        and event_type == "recognized"
        and runtime.radar_present
        and runtime.radar_distance_cm is not None
        and runtime.radar_distance_cm <= PRESENCE_DISTANCE_CM
    ):
        announcement = _enqueue_medication_announcement(session, device, user_id, runtime.radar_episode)
    return {
        "event": _recognition_read(event),
        "announcement_id": announcement.id if announcement else None,
    }


def _process_xiaozhi_state(session: Session, device: MedicineBoxDevice, payload: XiaozhiStateCallback) -> dict[str, Any]:
    runtime = _runtime(session, device.id or 0)
    now = datetime.utcnow()
    runtime.xiaozhi_state = payload.state
    runtime.last_xiaozhi_at = now
    runtime.updated_at = now
    stop_tts = payload.state in {"listening", "speaking"}
    cancelled = 0
    deferred = 0
    if stop_tts:
        runtime.stop_tts_requested_at = now
        pending = session.exec(
            select(DeviceAnnouncement).where(
                DeviceAnnouncement.device_id == device.id,
                DeviceAnnouncement.status.in_(["pending", "delivered"]),
            )
        ).all()
        for announcement in pending:
            if announcement.source == "schedule":
                # Scheduled medication reminders are deferred rather than lost.
                # If Xiaozhi interrupts playback, the ESP32 stops SYN6288 and
                # the reminder becomes pending again for the next idle window.
                if announcement.status == "delivered":
                    announcement.status = "pending"
                    announcement.delivered_at = None
                announcement.reason = "waiting_xiaozhi_idle"
                session.add(announcement)
                deferred += 1
                continue
            announcement.status = "cancelled"
            announcement.reason = "xiaozhi_busy"
            announcement.cancelled_at = now
            session.add(announcement)
            cancelled += 1
    event = DeviceTelemetryEvent(
        device_id=device.id or 0,
        event_type="xiaozhi_state",
        payload_json=_json_dump({"state": payload.state, "event_id": payload.event_id}),
        occurred_at=now,
    )
    session.add(runtime)
    session.add(event)
    session.commit()
    return {
        "stop_tts": stop_tts,
        "cancelled": cancelled,
        "deferred": deferred,
        "state": payload.state,
    }


def _process_syn_state(session: Session, device: MedicineBoxDevice, payload: Syn6288StateCallback) -> dict[str, Any]:
    runtime = _runtime(session, device.id or 0)
    now = datetime.utcnow()
    runtime.syn6288_state = payload.state
    device.tts_ready = True
    runtime.last_syn6288_at = now
    runtime.updated_at = now
    session.add(runtime)
    if payload.announcement_id is not None:
        announcement = session.get(DeviceAnnouncement, payload.announcement_id)
        if announcement and announcement.device_id == device.id and payload.state == "idle":
            announcement.status = "finished"
            session.add(announcement)
    session.commit()
    return {"state": payload.state}


def _recognition_read(event: DeviceRecognitionEvent) -> dict[str, Any]:
    metadata = _json_load(event.metadata_json, {})
    return {
        "id": event.id,
        "device_id": event.device_id,
        "user_id": event.user_id,
        "face_key": event.face_key,
        "event_type": event.event_type,
        "score": event.score,
        "radar_episode": event.radar_episode,
        "occurred_at": event.occurred_at,
        "identity_role": metadata.get("identity_role"),
        "metadata": metadata,
    }



def _runtime_read(runtime: DeviceRuntimeState) -> dict[str, Any]:
    return {
        "device_id": runtime.device_id,
        "radar_present": runtime.radar_present,
        "radar_distance_cm": runtime.radar_distance_cm,
        "radar_episode": runtime.radar_episode,
        "xiaozhi_state": runtime.xiaozhi_state,
        "syn6288_state": runtime.syn6288_state,
        "last_radar_at": runtime.last_radar_at,
        "last_xiaozhi_at": runtime.last_xiaozhi_at,
        "last_syn6288_at": runtime.last_syn6288_at,
        "stop_tts_requested_at": runtime.stop_tts_requested_at,
        "last_recognition_user_id": runtime.last_recognition_user_id,
        "last_recognition_at": runtime.last_recognition_at,
        "updated_at": runtime.updated_at,
    }

def _gb2312_base64(text: str) -> str:
    candidate = text
    encoded = candidate.encode("gb2312", errors="replace")
    while len(encoded) > 198 and candidate:
        candidate = candidate[:-1]
        encoded = candidate.encode("gb2312", errors="replace")
    return base64.b64encode(encoded).decode("ascii")


@router.get("/{device_id}/runtime")
def get_device_runtime(
    device_id: int,
    user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
) -> dict[str, Any]:
    _device_for_user(session, user, device_id)
    return _runtime_read(_runtime(session, device_id))


@router.get("/{device_id}/recognition-events")
def list_recognition_events(
    device_id: int,
    limit: int = Query(default=30, ge=1, le=100),
    user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
) -> list[dict[str, Any]]:
    _device_for_user(session, user, device_id)
    events = session.exec(
        select(DeviceRecognitionEvent)
        .where(DeviceRecognitionEvent.device_id == device_id)
        .order_by(DeviceRecognitionEvent.occurred_at.desc())
        .limit(limit)
    ).all()
    return [_recognition_read(event) for event in events]


@router.post("/{device_id}/announcements", status_code=status.HTTP_201_CREATED)
def create_announcement(
    device_id: int,
    payload: AnnouncementCreate,
    user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
) -> dict[str, Any]:
    device = _device_for_user(session, user, device_id)
    user_id = payload.user_id or device.owner_id
    if user_id not in _allowed_device_user_ids(session, device):
        raise HTTPException(status_code=403, detail="该成员不属于此药箱家庭")
    now = datetime.utcnow()
    announcement = DeviceAnnouncement(
        device_id=device.id or 0,
        user_id=user_id,
        text=payload.text.strip(),
        source="app",
        expires_at=now + timedelta(seconds=payload.ttl_seconds),
    )
    session.add(announcement)
    session.commit()
    session.refresh(announcement)
    return {
        "id": announcement.id,
        "text": announcement.text,
        "status": announcement.status,
        "expires_at": announcement.expires_at,
    }


@router.post("/{device_id}/camera/preview/start", response_model=PreviewStartResponse)
def start_preview(
    device_id: int,
    user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
) -> PreviewStartResponse:
    _device_for_user(session, user, device_id)
    now = datetime.utcnow()
    active_until = now + timedelta(seconds=PREVIEW_SESSION_SECONDS)
    preview = session.exec(select(DevicePreviewSession).where(DevicePreviewSession.device_id == device_id)).first()
    if preview is None:
        preview = DevicePreviewSession(device_id=device_id, active_until=active_until)
    else:
        preview.active_until = active_until
        preview.updated_at = now
    session.add(preview)
    session.commit()
    return PreviewStartResponse(active=True, active_until=active_until)


@router.post("/{device_id}/camera/preview/stop")
def stop_preview(
    device_id: int,
    user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
) -> dict[str, Any]:
    _device_for_user(session, user, device_id)
    preview = session.exec(select(DevicePreviewSession).where(DevicePreviewSession.device_id == device_id)).first()
    if preview:
        preview.active_until = datetime.utcnow() - timedelta(seconds=1)
        preview.updated_at = datetime.utcnow()
        session.add(preview)
        session.commit()
    return {"active": False}


@router.get("/{device_id}/camera/preview/status")
def app_preview_status(
    device_id: int,
    user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
) -> dict[str, Any]:
    _device_for_user(session, user, device_id)
    return _preview_status(session, device_id)


@router.get("/{device_id}/camera/preview/frame")
def app_preview_frame(
    device_id: int,
    user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
) -> FileResponse:
    _device_for_user(session, user, device_id)
    frame = session.exec(select(DevicePreviewFrame).where(DevicePreviewFrame.device_id == device_id)).first()
    if not frame:
        raise HTTPException(status_code=404, detail="还没有预览画面")
    path = _preview_path(frame.storage_name)
    if not path.is_file():
        raise HTTPException(status_code=404, detail="预览画面已丢失")
    return FileResponse(
        path,
        media_type=frame.content_type,
        headers={"Cache-Control": "no-store", "Content-Disposition": "inline"},
    )


def _preview_status(session: Session, device_id: int) -> dict[str, Any]:
    now = datetime.utcnow()
    preview = session.exec(select(DevicePreviewSession).where(DevicePreviewSession.device_id == device_id)).first()
    frame = session.exec(select(DevicePreviewFrame).where(DevicePreviewFrame.device_id == device_id)).first()
    active = bool(preview and preview.active_until > now)
    return {
        "active": active,
        "active_until": preview.active_until if preview else None,
        "frame_updated_at": frame.captured_at if frame else None,
    }


_PREVIEW_DB_UPDATES: dict[int, float] = {}


def _write_preview_file(device_id: int, body: bytes) -> str:
    relative = f"{device_id}/latest.jpg"
    target = _preview_path(relative)
    target.parent.mkdir(parents=True, exist_ok=True)
    temp = target.with_suffix(".tmp")
    temp.write_bytes(body)
    temp.replace(target)
    return relative


@router.websocket("/{device_id}/camera/preview/ws")
async def app_preview_websocket(websocket: WebSocket, device_id: int) -> None:
    try:
        payload = _jie_xi_ling_pai(_bearer_token(websocket.headers.get("authorization")))
    except HTTPException:
        await websocket.close(code=1008)
        return
    with Session(engine) as session:
        user = session.get(User, int(str(payload["sub"])))
        device = session.get(MedicineBoxDevice, device_id)
        if not user or not user.is_active or not device or device.owner_id not in accessible_owner_ids(session, user):
            await websocket.close(code=1008)
            return
    await websocket.accept()
    await websocket.send_json({"type": "connected", "device_id": device_id})
    frame_path = _preview_path(f"{device_id}/latest.jpg")
    last_signature: tuple[int, int, int] | None = None
    last_heartbeat = _time.monotonic()
    sent_frames = 0
    try:
        while True:
            try:
                stat = frame_path.stat()
                signature = (stat.st_mtime_ns, stat.st_size, stat.st_ino)
                if signature != last_signature:
                    frame = frame_path.read_bytes()
                    if frame.startswith(b"\xff\xd8\xff"):
                        await websocket.send_bytes(frame)
                        last_signature = signature
                        sent_frames += 1
                        if sent_frames == 1:
                            logger.info(
                                "preview viewer connected device_id=%s frame_bytes=%s",
                                device_id,
                                len(frame),
                            )
            except FileNotFoundError:
                pass
            except OSError:
                # The device replaces latest.jpg atomically; a transient read miss is harmless.
                pass

            now = _time.monotonic()
            if now - last_heartbeat >= 5.0:
                await websocket.send_json({"type": "heartbeat", "device_id": device_id})
                last_heartbeat = now
            await asyncio.sleep(0.06)
    except WebSocketDisconnect:
        pass
    except Exception:
        pass
    finally:
        logger.info(
            "preview viewer disconnected device_id=%s frames=%s",
            device_id,
            sent_frames,
        )


def _store_preview_frame(session: Session, device: MedicineBoxDevice, body: bytes) -> datetime:
    relative = _write_preview_file(device.id or 0, body)
    now = datetime.utcnow()
    frame = session.exec(select(DevicePreviewFrame).where(DevicePreviewFrame.device_id == device.id)).first()
    should_update = frame is None or (now - frame.captured_at).total_seconds() >= 2.0
    if should_update:
        if frame is None:
            frame = DevicePreviewFrame(device_id=device.id or 0, storage_name=relative)
        frame.storage_name = relative
        frame.content_type = "image/jpeg"
        frame.size_bytes = len(body)
        frame.captured_at = now
        frame.updated_at = now
        session.add(frame)
        session.commit()
    return now


@agent_router.get("/preview/status")
def agent_preview_status(
    device_uid: str = Query(min_length=3, max_length=80),
    session: Session = Depends(get_session),
    x_agent_token: str | None = Header(default=None, alias="X-Agent-Token"),
) -> dict[str, Any]:
    _require_agent(x_agent_token)
    device = _device_by_uid(session, device_uid)
    return _preview_status(session, device.id or 0)


@agent_router.post("/camera/preview-frame")
async def upload_preview_frame(
    request: Request,
    device_uid: str = Query(min_length=3, max_length=80),
    session: Session = Depends(get_session),
    x_agent_token: str | None = Header(default=None, alias="X-Agent-Token"),
) -> dict[str, Any]:
    _require_agent(x_agent_token)
    device = _device_by_uid(session, device_uid)
    preview = _preview_status(session, device.id or 0)
    if not preview["active"]:
        raise HTTPException(status_code=409, detail="实时预览未开启")
    body = await request.body()
    if not body or len(body) > 5 * 1024 * 1024:
        raise HTTPException(status_code=413, detail="预览帧大小无效")
    if not body.startswith(b"\xff\xd8\xff"):
        raise HTTPException(status_code=400, detail="预览帧必须是 JPEG")
    now = _store_preview_frame(session, device, body)
    return {"ok": True, "captured_at": now}


def _require_agent(x_agent_token: str | None) -> None:
    if not _agent_token_ok(x_agent_token):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="设备代理令牌无效")


@agent_router.post("/recognition-events")
def upload_recognition_event(
    payload: RecognitionEventCreate,
    session: Session = Depends(get_session),
    x_agent_token: str | None = Header(default=None, alias="X-Agent-Token"),
) -> dict[str, Any]:
    _require_agent(x_agent_token)
    device = _device_by_uid(session, payload.device_uid)
    return _process_recognition_event(session, device, payload)


@agent_router.post("/radar/events")
def upload_radar_event(
    payload: RadarEventCreate,
    session: Session = Depends(get_session),
    x_agent_token: str | None = Header(default=None, alias="X-Agent-Token"),
) -> dict[str, Any]:
    _require_agent(x_agent_token)
    device = _device_by_uid(session, payload.device_uid)
    return _process_radar_event(session, device, payload)


@agent_router.post("/xiaozhi/state")
async def xiaozhi_state_callback(
    payload: XiaozhiStateCallback,
    session: Session = Depends(get_session),
    x_agent_token: str | None = Header(default=None, alias="X-Agent-Token"),
) -> dict[str, Any]:
    _require_agent(x_agent_token)
    device = _device_by_uid(session, payload.device_uid)
    result = _process_xiaozhi_state(session, device, payload)
    if result["stop_tts"]:
        await device_connections.send(payload.device_uid, {"type": "stop_tts", "reason": "xiaozhi_busy"})
    return result


@agent_router.post("/syn6288/state")
def syn6288_state_callback(
    payload: Syn6288StateCallback,
    session: Session = Depends(get_session),
    x_agent_token: str | None = Header(default=None, alias="X-Agent-Token"),
) -> dict[str, Any]:
    _require_agent(x_agent_token)
    device = _device_by_uid(session, payload.device_uid)
    return _process_syn_state(session, device, payload)


@agent_router.get("/runtime")
def agent_runtime(
    device_uid: str = Query(min_length=3, max_length=80),
    session: Session = Depends(get_session),
    x_agent_token: str | None = Header(default=None, alias="X-Agent-Token"),
) -> dict[str, Any]:
    _require_agent(x_agent_token)
    device = _device_by_uid(session, device_uid)
    runtime = _runtime(session, device.id or 0)
    return _runtime_read(runtime)


@agent_router.get("/announcements/next")
def next_announcement(
    device_uid: str = Query(min_length=3, max_length=80),
    session: Session = Depends(get_session),
    x_agent_token: str | None = Header(default=None, alias="X-Agent-Token"),
) -> dict[str, Any]:
    _require_agent(x_agent_token)
    device = _device_by_uid(session, device_uid)
    runtime = _runtime(session, device.id or 0)
    now = datetime.utcnow()
    expired = session.exec(
        select(DeviceAnnouncement).where(
            DeviceAnnouncement.device_id == device.id,
            DeviceAnnouncement.status == "pending",
            DeviceAnnouncement.expires_at < now,
        )
    ).all()
    for announcement in expired:
        announcement.status = "dropped"
        announcement.reason = "ttl_expired"
        announcement.cancelled_at = now
        session.add(announcement)
    if runtime.xiaozhi_state != "idle":
        session.commit()
        return {"announcement": None, "reason": "xiaozhi_busy"}
    if runtime.last_xiaozhi_at and (now - runtime.last_xiaozhi_at).total_seconds() < XIAOZHI_IDLE_SETTLE_SECONDS:
        session.commit()
        return {"announcement": None, "reason": "xiaozhi_settling"}
    announcement = session.exec(
        select(DeviceAnnouncement)
        .where(
            DeviceAnnouncement.device_id == device.id,
            DeviceAnnouncement.status == "pending",
            DeviceAnnouncement.expires_at >= now,
        )
        .order_by(DeviceAnnouncement.created_at)
    ).first()
    if not announcement:
        session.commit()
        return {"announcement": None}
    announcement.status = "delivered"
    announcement.delivered_at = now
    session.add(announcement)
    session.commit()
    return {
        "announcement": {
            "id": announcement.id,
            "text": announcement.text,
            "user_id": announcement.user_id,
            "source": announcement.source,
            "text_gb2312_base64": _gb2312_base64(announcement.text),
        }
    }

class DeviceConnectionManager:
    def __init__(self) -> None:
        self._connections: dict[str, WebSocket] = {}

    async def connect(self, device_uid: str, websocket: WebSocket) -> None:
        await websocket.accept()
        old = self._connections.get(device_uid)
        if old is not None:
            try:
                await old.close(code=1000)
            except Exception:
                pass
        self._connections[device_uid] = websocket

    def disconnect(self, device_uid: str, websocket: WebSocket) -> None:
        if self._connections.get(device_uid) is websocket:
            self._connections.pop(device_uid, None)

    async def send(self, device_uid: str, payload: dict[str, Any]) -> bool:
        websocket = self._connections.get(device_uid)
        if websocket is None:
            return False
        try:
            await websocket.send_json(payload)
            return True
        except Exception:
            self._connections.pop(device_uid, None)
            return False


device_connections = DeviceConnectionManager()


@agent_router.websocket("/ws")
async def device_websocket(websocket: WebSocket, device_uid: str = Query(min_length=3, max_length=80)) -> None:
    device_id: int | None = None
    token = websocket.headers.get("x-agent-token")
    if not _agent_token_ok(token):
        await websocket.close(code=1008)
        return
    with Session(engine) as session:
        device = session.exec(select(MedicineBoxDevice).where(MedicineBoxDevice.device_uid == device_uid)).first()
        if not device:
            await websocket.close(code=1008)
            return
        device.status = "online"
        device_id = device.id
        device.last_seen_at = datetime.utcnow()
        device.updated_at = device.last_seen_at
        session.add(device)
        session.commit()
    await device_connections.connect(device_uid, websocket)
    await websocket.send_json({"type": "connected", "device_uid": device_uid})
    try:
        while True:
            event = await websocket.receive()
            if event.get("bytes") is not None:
                frame_bytes = event["bytes"]
                if (
                    device_id is not None
                    and len(frame_bytes) <= 5 * 1024 * 1024
                    and frame_bytes.startswith(b"\xff\xd8\xff")
                ):
                    now_monotonic = _time.monotonic()
                    last_db_update = _PREVIEW_DB_UPDATES.get(device_id, 0.0)
                    if now_monotonic - last_db_update >= 2.0:
                        with Session(engine) as session:
                            device = _device_by_uid(session, device_uid)
                            _store_preview_frame(session, device, frame_bytes)
                        _PREVIEW_DB_UPDATES[device_id] = now_monotonic
                    else:
                        _write_preview_file(device_id, frame_bytes)
                continue
            text = event.get("text")
            if not text:
                continue
            message = json.loads(text)
            message_type = message.get("type")
            with Session(engine) as session:
                device = _device_by_uid(session, device_uid)
                if message_type == "radar_event":
                    result = _process_radar_event(session, device, RadarEventCreate(device_uid=device_uid, **message.get("data", {})))
                elif message_type == "recognition_event":
                    result = _process_recognition_event(session, device, RecognitionEventCreate(device_uid=device_uid, **message.get("data", {})))
                elif message_type == "xiaozhi_state":
                    result = _process_xiaozhi_state(session, device, XiaozhiStateCallback(device_uid=device_uid, **message.get("data", {})))
                    if result["stop_tts"]:
                        await websocket.send_json({"type": "stop_tts", "reason": "xiaozhi_busy"})
                elif message_type == "syn6288_state":
                    result = _process_syn_state(session, device, Syn6288StateCallback(device_uid=device_uid, **message.get("data", {})))
                elif message_type == "ping":
                    result = {"type": "pong", "now": datetime.utcnow().isoformat()}
                else:
                    result = {"error": "unsupported_message_type"}
            await websocket.send_json({"type": "ack", "request_type": message_type, "result": result})
    except WebSocketDisconnect:
        pass
    except Exception as exc:
        try:
            await websocket.send_json({"type": "error", "detail": str(exc)[:300]})
        except Exception:
            pass
    finally:
        device_connections.disconnect(device_uid, websocket)
