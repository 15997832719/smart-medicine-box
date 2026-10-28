from __future__ import annotations

import hmac
import json
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Literal
from uuid import uuid4

from fastapi import APIRouter, Depends, File, Form, Header, HTTPException, Query, UploadFile, status
from fastapi.responses import FileResponse
from pydantic import BaseModel, Field as PydanticField
from sqlmodel import Field, Session, SQLModel, select

from app.auth import accessible_owner_ids, get_current_user, require_owner_access
from app.config import get_settings
from app.database import get_session
from app.models import FamilyLink, User, UserRole

router = APIRouter(prefix="/hardware-devices", tags=["hardware-devices"])
agent_router = APIRouter(prefix="/device-agent", tags=["device-agent"])

CommandType = Literal["face_enroll", "face_recognize", "face_delete", "camera_snapshot", "intake_record"]

CAMERA_ASSET_KINDS = {"camera_snapshot", "intake_video"}


class MedicineBoxDevice(SQLModel, table=True):
    __tablename__ = "medicine_box_devices"

    id: int | None = Field(default=None, primary_key=True)
    device_uid: str = Field(index=True, unique=True, max_length=80)
    name: str = Field(default="智能药箱", max_length=80)
    owner_id: int = Field(foreign_key="users.id", index=True)
    status: str = Field(default="offline", max_length=24, index=True)
    camera_ready: bool = False
    radar_ready: bool = False
    tts_ready: bool = False
    firmware_version: str | None = Field(default=None, max_length=80)
    last_seen_at: datetime | None = None
    created_at: datetime = Field(default_factory=datetime.utcnow, nullable=False)
    updated_at: datetime = Field(default_factory=datetime.utcnow, nullable=False)


class DeviceCommand(SQLModel, table=True):
    __tablename__ = "device_commands"

    id: int | None = Field(default=None, primary_key=True)
    device_id: int = Field(foreign_key="medicine_box_devices.id", index=True)
    requested_by: int = Field(foreign_key="users.id", index=True)
    command_type: str = Field(max_length=40, index=True)
    payload_json: str = Field(default="{}", max_length=12000)
    status: str = Field(default="pending", max_length=24, index=True)
    result_json: str | None = Field(default=None, max_length=20000)
    error: str | None = Field(default=None, max_length=1000)
    created_at: datetime = Field(default_factory=datetime.utcnow, nullable=False, index=True)
    claimed_at: datetime | None = None
    completed_at: datetime | None = None
    expires_at: datetime = Field(nullable=False)


class DeviceFaceProfile(SQLModel, table=True):
    __tablename__ = "device_face_profiles"

    id: int | None = Field(default=None, primary_key=True)
    device_id: int = Field(foreign_key="medicine_box_devices.id", index=True)
    user_id: int = Field(foreign_key="users.id", index=True)
    face_key: str = Field(max_length=80, index=True)
    display_name: str = Field(max_length=80)
    announce_user_id: int | None = Field(default=None, foreign_key="users.id", index=True)
    role: str = Field(max_length=20)
    sample_count: int = Field(default=0, ge=0)
    status: str = Field(default="active", max_length=24, index=True)
    quality_json: str | None = Field(default=None, max_length=8000)
    created_at: datetime = Field(default_factory=datetime.utcnow, nullable=False)
    updated_at: datetime = Field(default_factory=datetime.utcnow, nullable=False)


class DeviceCameraAsset(SQLModel, table=True):
    __tablename__ = "device_camera_assets"

    id: int | None = Field(default=None, primary_key=True)
    device_id: int = Field(foreign_key="medicine_box_devices.id", index=True)
    command_id: int | None = Field(default=None, foreign_key="device_commands.id", index=True)
    user_id: int | None = Field(default=None, foreign_key="users.id", index=True)
    kind: str = Field(max_length=24, index=True)
    status: str = Field(default="possible_taken", max_length=32, index=True)
    storage_name: str = Field(max_length=500)
    thumbnail_name: str | None = Field(default=None, max_length=500)
    original_name: str | None = Field(default=None, max_length=255)
    content_type: str = Field(default="application/octet-stream", max_length=100)
    size_bytes: int = Field(default=0, ge=0)
    duration_seconds: float | None = Field(default=None, ge=0)
    metadata_json: str = Field(default="{}", max_length=16000)
    review_note: str | None = Field(default=None, max_length=500)
    reviewed_by: int | None = Field(default=None, foreign_key="users.id")
    reviewed_at: datetime | None = None
    captured_at: datetime = Field(default_factory=datetime.utcnow, nullable=False, index=True)
    created_at: datetime = Field(default_factory=datetime.utcnow, nullable=False)
    updated_at: datetime = Field(default_factory=datetime.utcnow, nullable=False)


class HardwareDeviceCreate(BaseModel):
    device_uid: str = PydanticField(min_length=3, max_length=80)
    name: str = PydanticField(default="智能药箱", min_length=1, max_length=80)
    owner_id: int | None = PydanticField(default=None, ge=1)


class DeviceCommandCreate(BaseModel):
    command_type: CommandType
    payload: dict[str, Any] = PydanticField(default_factory=dict)



class DeviceFaceIdentityUpdate(BaseModel):
    role: Literal["elder", "child", "stranger"]
    announce_user_id: int | None = PydanticField(default=None, ge=1)

class AgentHeartbeat(BaseModel):
    device_uid: str
    camera_ready: bool = False
    radar_ready: bool = False
    tts_ready: bool = False
    firmware_version: str | None = None


class AgentCommandResult(BaseModel):
    device_uid: str
    success: bool
    result: dict[str, Any] = PydanticField(default_factory=dict)
    error: str | None = None


class AgentFacesSync(BaseModel):
    device_uid: str
    faces: list[dict[str, Any]] = PydanticField(default_factory=list)


class CameraAssetReview(BaseModel):
    status: Literal["confirmed_taken", "not_taken", "possible_taken"]
    note: str | None = PydanticField(default=None, max_length=500)


def _json_dump(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"))


def _json_load(value: str | None, fallback: Any) -> Any:
    if not value:
        return fallback
    try:
        return json.loads(value)
    except Exception:
        return fallback


def _camera_root() -> Path:
    settings = get_settings()
    configured = getattr(settings, "device_camera_dir", "data/camera_assets")
    root = Path(configured).expanduser().resolve()
    root.mkdir(parents=True, exist_ok=True)
    return root


def _camera_path(relative: str | None) -> Path | None:
    if not relative:
        return None
    root = _camera_root()
    target = (root / relative).resolve()
    if target != root and root not in target.parents:
        raise HTTPException(status_code=400, detail="摄像头素材路径无效")
    return target


async def _save_upload(upload: UploadFile, target: Path, max_bytes: int) -> int:
    target.parent.mkdir(parents=True, exist_ok=True)
    total = 0
    try:
        with target.open("wb") as output:
            while True:
                chunk = await upload.read(1024 * 1024)
                if not chunk:
                    break
                total += len(chunk)
                if total > max_bytes:
                    raise HTTPException(status_code=413, detail="摄像头素材超过上传大小限制")
                output.write(chunk)
        if total <= 0:
            raise HTTPException(status_code=400, detail="摄像头素材为空")
    except Exception:
        target.unlink(missing_ok=True)
        raise
    finally:
        await upload.close()
    return total


def _normalize_captured_at(value: str | None) -> datetime:
    if not value:
        return datetime.utcnow()
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as exc:
        raise HTTPException(status_code=400, detail="captured_at 时间格式无效") from exc
    if parsed.tzinfo is not None:
        parsed = parsed.astimezone(timezone.utc).replace(tzinfo=None)
    return parsed


def _device_camera_user_ids(session: Session, device: MedicineBoxDevice) -> set[int]:
    allowed = {device.owner_id}
    links = session.exec(select(FamilyLink).where(FamilyLink.elder_id == device.owner_id)).all()
    allowed.update(link.child_id for link in links)
    return allowed


def _agent_token_ok(token: str | None) -> bool:
    expected = get_settings().device_agent_token
    if not token or not expected:
        return False
    return hmac.compare_digest(token, expected)


def require_agent_token(x_agent_token: str | None = Header(default=None, alias="X-Agent-Token")) -> None:
    if not _agent_token_ok(x_agent_token):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="设备代理令牌无效")


def _default_owner(session: Session, user: User, owner_id: int | None) -> int:
    if owner_id is not None:
        return require_owner_access(session, user, owner_id)
    if user.role == UserRole.elder:
        return user.id or 0
    allowed = accessible_owner_ids(session, user)
    for candidate in allowed:
        if candidate != user.id:
            return candidate
    raise HTTPException(status_code=400, detail="请先绑定老人账号")


def _user_can_access_device(session: Session, user: User, device: MedicineBoxDevice) -> bool:
    return device.owner_id in accessible_owner_ids(session, user)


def _get_device_for_user(session: Session, user: User, device_id: int) -> MedicineBoxDevice:
    device = session.get(MedicineBoxDevice, device_id)
    if not device or not _user_can_access_device(session, user, device):
        raise HTTPException(status_code=404, detail="设备不存在")
    return device


def _device_read(session: Session, device: MedicineBoxDevice) -> dict[str, Any]:
    faces = session.exec(
        select(DeviceFaceProfile).where(
            DeviceFaceProfile.device_id == device.id,
            DeviceFaceProfile.status == "active",
        )
    ).all()
    latest_camera_asset = session.exec(
        select(DeviceCameraAsset)
        .where(DeviceCameraAsset.device_id == device.id)
        .order_by(DeviceCameraAsset.captured_at.desc())
    ).first()
    latest_intake_asset = session.exec(
        select(DeviceCameraAsset)
        .where(DeviceCameraAsset.device_id == device.id, DeviceCameraAsset.kind == "intake_video")
        .order_by(DeviceCameraAsset.captured_at.desc())
    ).first()
    return {
        "id": device.id,
        "device_uid": device.device_uid,
        "name": device.name,
        "owner_id": device.owner_id,
        "status": device.status,
        "camera_ready": device.camera_ready,
        "radar_ready": device.radar_ready,
        "tts_ready": device.tts_ready,
        "firmware_version": device.firmware_version,
        "last_seen_at": device.last_seen_at,
        "latest_camera_asset": _camera_asset_read(latest_camera_asset) if latest_camera_asset else None,
        "latest_intake_video_at": latest_intake_asset.captured_at if latest_intake_asset else None,
        "faces": [
            {
                "id": face.id,
                "user_id": face.user_id,
                "announce_user_id": face.announce_user_id or face.user_id,
                "face_key": face.face_key,
                "display_name": face.display_name,
                "role": face.role,
                "sample_count": face.sample_count,
                "status": face.status,
                "updated_at": face.updated_at,
            }
            for face in faces
        ],
    }


def _command_read(command: DeviceCommand) -> dict[str, Any]:
    return {
        "id": command.id,
        "device_id": command.device_id,
        "command_type": command.command_type,
        "payload": _json_load(command.payload_json, {}),
        "status": command.status,
        "result": _json_load(command.result_json, None),
        "error": command.error,
        "created_at": command.created_at,
        "claimed_at": command.claimed_at,
        "completed_at": command.completed_at,
    }


def _camera_asset_read(asset: DeviceCameraAsset) -> dict[str, Any]:
    prefix = getattr(get_settings(), "api_prefix", "/api/v1").rstrip("/")
    base = f"{prefix}/hardware-devices/{asset.device_id}/camera/assets/{asset.id}"
    return {
        "id": asset.id,
        "device_id": asset.device_id,
        "command_id": asset.command_id,
        "user_id": asset.user_id,
        "kind": asset.kind,
        "status": asset.status,
        "file_url": f"{base}/file",
        "thumbnail_url": f"{base}/thumbnail" if asset.thumbnail_name else None,
        "content_type": asset.content_type,
        "size_bytes": asset.size_bytes,
        "duration_seconds": asset.duration_seconds,
        "captured_at": asset.captured_at,
        "review_note": asset.review_note,
        "reviewed_by": asset.reviewed_by,
        "reviewed_at": asset.reviewed_at,
        "metadata": _json_load(asset.metadata_json, {}),
    }


@router.get("")
def list_hardware_devices(
    user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
) -> list[dict[str, Any]]:
    allowed = accessible_owner_ids(session, user)
    devices = session.exec(
        select(MedicineBoxDevice)
        .where(MedicineBoxDevice.owner_id.in_(allowed))
        .order_by(MedicineBoxDevice.updated_at.desc())
    ).all()
    return [_device_read(session, device) for device in devices]


@router.post("", status_code=status.HTTP_201_CREATED)
def create_hardware_device(
    payload: HardwareDeviceCreate,
    user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
) -> dict[str, Any]:
    owner_id = _default_owner(session, user, payload.owner_id)
    device = session.exec(select(MedicineBoxDevice).where(MedicineBoxDevice.device_uid == payload.device_uid)).first()
    if device and device.owner_id != owner_id:
        raise HTTPException(status_code=409, detail="该设备已绑定其他药箱")
    if device is None:
        device = MedicineBoxDevice(device_uid=payload.device_uid, name=payload.name, owner_id=owner_id)
        session.add(device)
    else:
        device.name = payload.name
        device.updated_at = datetime.utcnow()
        session.add(device)
    session.commit()
    session.refresh(device)
    return _device_read(session, device)


@router.get("/{device_id}")
def get_hardware_device(
    device_id: int,
    user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
) -> dict[str, Any]:
    return _device_read(session, _get_device_for_user(session, user, device_id))


@router.post("/{device_id}/commands", status_code=status.HTTP_201_CREATED)
def create_device_command(
    device_id: int,
    payload: DeviceCommandCreate,
    user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
) -> dict[str, Any]:
    device = _get_device_for_user(session, user, device_id)
    command_payload = dict(payload.payload)
    if payload.command_type in {"face_enroll", "face_delete"}:
        target_id = command_payload.get("user_id")
        if not isinstance(target_id, int):
            raise HTTPException(status_code=400, detail="user_id 无效")
        target = session.get(User, target_id)
        allowed = _device_camera_user_ids(session, device)
        if not target or not target.is_active or target_id not in allowed:
            raise HTTPException(status_code=403, detail="无权为该成员注册人脸")
        if payload.command_type == "face_enroll":
            command_payload.update(
                {
                    "user_id": target.id,
                    "face_key": f"smb-user-{target.id}",
                    "display_name": target.nickname or target.phone,
                    "role": target.role.value,
                    "samples": int(command_payload.get("samples") or 5),
                }
            )
        else:
            command_payload.update(
                {
                    "user_id": target.id,
                    "face_key": f"smb-user-{target.id}",
                }
            )
    if payload.command_type == "intake_record":
        target_id = command_payload.get("user_id", device.owner_id)
        if not isinstance(target_id, int) or target_id not in _device_camera_user_ids(session, device):
            raise HTTPException(status_code=403, detail="无权为该成员录制服药视频")
        command_payload["user_id"] = target_id
        try:
            duration = int(command_payload.get("duration") or 20)
        except (TypeError, ValueError) as exc:
            raise HTTPException(status_code=400, detail="录像时长无效") from exc
        command_payload["duration"] = max(3, min(60, duration))
    command = DeviceCommand(
        device_id=device_id,
        requested_by=user.id or 0,
        command_type=payload.command_type,
        payload_json=_json_dump(command_payload),
        expires_at=datetime.utcnow() + timedelta(minutes=30),
    )
    session.add(command)
    session.commit()
    session.refresh(command)
    return _command_read(command)


@router.get("/{device_id}/commands/{command_id}")
def get_device_command(
    device_id: int,
    command_id: int,
    user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
) -> dict[str, Any]:
    _get_device_for_user(session, user, device_id)
    command = session.get(DeviceCommand, command_id)
    if not command or command.device_id != device_id:
        raise HTTPException(status_code=404, detail="命令不存在")
    return _command_read(command)


@router.get("/{device_id}/faces")
def list_device_faces(
    device_id: int,
    user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
) -> list[dict[str, Any]]:
    _get_device_for_user(session, user, device_id)
    faces = session.exec(
        select(DeviceFaceProfile)
        .where(DeviceFaceProfile.device_id == device_id, DeviceFaceProfile.status == "active")
        .order_by(DeviceFaceProfile.updated_at.desc())
    ).all()
    return [
        {
            "id": face.id,
            "user_id": face.user_id,
            "announce_user_id": face.announce_user_id or face.user_id,
            "face_key": face.face_key,
            "display_name": face.display_name,
            "role": face.role,
            "sample_count": face.sample_count,
            "status": face.status,
            "updated_at": face.updated_at,
        }
        for face in faces
    ]


@router.patch("/{device_id}/faces/{face_id}")
def update_device_face_identity(
    device_id: int,
    face_id: int,
    payload: DeviceFaceIdentityUpdate,
    user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
) -> dict[str, Any]:
    device = _get_device_for_user(session, user, device_id)
    face = session.get(DeviceFaceProfile, face_id)
    if not face or face.device_id != device_id or face.status != "active":
        raise HTTPException(status_code=404, detail="设备人脸不存在")
    if payload.role == "stranger":
        face.role = "stranger"
        face.announce_user_id = None
        face.display_name = "陌生人"
    else:
        target_id = payload.announce_user_id
        if target_id is None:
            raise HTTPException(status_code=400, detail="请选择播报对应的家庭成员")
        target = session.get(User, target_id)
        allowed = _device_camera_user_ids(session, device)
        if not target or not target.is_active or target_id not in allowed:
            raise HTTPException(status_code=403, detail="无权绑定该家庭成员")
        if target.role.value != payload.role:
            raise HTTPException(status_code=400, detail="身份类型与成员角色不匹配")
        face.role = payload.role
        face.announce_user_id = target.id
        face.display_name = target.nickname or target.phone
    face.updated_at = datetime.utcnow()
    session.add(face)
    session.commit()
    session.refresh(face)
    return {
        "id": face.id,
        "user_id": face.user_id,
        "announce_user_id": face.announce_user_id,
        "face_key": face.face_key,
        "display_name": face.display_name,
        "role": face.role,
        "sample_count": face.sample_count,
        "status": face.status,
        "updated_at": face.updated_at,
    }


@router.get("/{device_id}/camera/assets")
def list_camera_assets(
    device_id: int,
    kind: str | None = Query(default=None),
    limit: int = Query(default=50, ge=1, le=100),
    user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
) -> list[dict[str, Any]]:
    _get_device_for_user(session, user, device_id)
    if kind is not None and kind not in CAMERA_ASSET_KINDS:
        raise HTTPException(status_code=400, detail="摄像头素材类型无效")
    query = select(DeviceCameraAsset).where(DeviceCameraAsset.device_id == device_id)
    if kind is not None:
        query = query.where(DeviceCameraAsset.kind == kind)
    assets = session.exec(query.order_by(DeviceCameraAsset.captured_at.desc()).limit(limit)).all()
    return [_camera_asset_read(asset) for asset in assets]


@router.get("/{device_id}/camera/assets/{asset_id}/file")
def get_camera_asset_file(
    device_id: int,
    asset_id: int,
    user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
) -> FileResponse:
    _get_device_for_user(session, user, device_id)
    asset = session.get(DeviceCameraAsset, asset_id)
    if not asset or asset.device_id != device_id:
        raise HTTPException(status_code=404, detail="摄像头素材不存在")
    path = _camera_path(asset.storage_name)
    if path is None or not path.is_file():
        raise HTTPException(status_code=404, detail="摄像头素材文件已丢失")
    return FileResponse(
        path,
        media_type=asset.content_type,
        headers={"Cache-Control": "private, max-age=60", "Content-Disposition": "inline"},
    )


@router.get("/{device_id}/camera/assets/{asset_id}/thumbnail")
def get_camera_asset_thumbnail(
    device_id: int,
    asset_id: int,
    user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
) -> FileResponse:
    _get_device_for_user(session, user, device_id)
    asset = session.get(DeviceCameraAsset, asset_id)
    if not asset or asset.device_id != device_id:
        raise HTTPException(status_code=404, detail="摄像头素材不存在")
    path = _camera_path(asset.thumbnail_name)
    if path is None or not path.is_file():
        raise HTTPException(status_code=404, detail="缩略图不存在")
    return FileResponse(
        path,
        media_type="image/jpeg",
        headers={"Cache-Control": "private, max-age=300", "Content-Disposition": "inline"},
    )


@router.patch("/{device_id}/camera/assets/{asset_id}/review")
def review_camera_asset(
    device_id: int,
    asset_id: int,
    payload: CameraAssetReview,
    user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
) -> dict[str, Any]:
    _get_device_for_user(session, user, device_id)
    asset = session.get(DeviceCameraAsset, asset_id)
    if not asset or asset.device_id != device_id:
        raise HTTPException(status_code=404, detail="摄像头素材不存在")
    if asset.kind != "intake_video":
        raise HTTPException(status_code=400, detail="只有服药录像需要家属确认")
    asset.status = payload.status
    asset.review_note = payload.note
    asset.reviewed_by = user.id
    asset.reviewed_at = datetime.utcnow()
    asset.updated_at = asset.reviewed_at
    session.add(asset)
    session.commit()
    session.refresh(asset)
    return _camera_asset_read(asset)


@agent_router.post("/camera-assets", status_code=status.HTTP_201_CREATED)
async def agent_upload_camera_asset(
    device_uid: str = Form(...),
    kind: str = Form(...),
    command_id: int | None = Form(default=None),
    user_id: int | None = Form(default=None),
    captured_at: str | None = Form(default=None),
    duration_seconds: float | None = Form(default=None),
    metadata_json: str | None = Form(default=None),
    file: UploadFile = File(...),
    thumbnail: UploadFile | None = File(default=None),
    _: None = Depends(require_agent_token),
    session: Session = Depends(get_session),
) -> dict[str, Any]:
    if kind not in CAMERA_ASSET_KINDS:
        raise HTTPException(status_code=400, detail="摄像头素材类型无效")
    device = session.exec(select(MedicineBoxDevice).where(MedicineBoxDevice.device_uid == device_uid)).first()
    if not device:
        raise HTTPException(status_code=404, detail="设备未在 App 中添加")

    command: DeviceCommand | None = None
    command_payload: dict[str, Any] = {}
    expected_command_type = "camera_snapshot" if kind == "camera_snapshot" else "intake_record"
    if command_id is not None:
        command = session.get(DeviceCommand, command_id)
        if not command or command.device_id != device.id:
            raise HTTPException(status_code=404, detail="命令不存在")
        if command.command_type != expected_command_type:
            raise HTTPException(status_code=400, detail="命令类型与素材类型不匹配")
        command_payload = _json_load(command.payload_json, {})

    if user_id is None:
        raw_user_id = command_payload.get("user_id")
        user_id = int(raw_user_id) if isinstance(raw_user_id, int) else device.owner_id
    if user_id not in _device_camera_user_ids(session, device):
        raise HTTPException(status_code=403, detail="该成员不属于此药箱家庭")

    suffix = Path(file.filename or "").suffix.lower()
    if kind == "camera_snapshot":
        if suffix not in {".jpg", ".jpeg"}:
            raise HTTPException(status_code=400, detail="抓拍图必须是 JPEG")
        content_type = "image/jpeg"
        asset_status = "snapshot"
    else:
        if suffix != ".mp4":
            raise HTTPException(status_code=400, detail="服药录像必须是 MP4")
        content_type = "video/mp4"
        asset_status = "possible_taken"

    if metadata_json:
        if len(metadata_json) > 16000:
            raise HTTPException(status_code=400, detail="素材附加信息过长")
        try:
            metadata = json.loads(metadata_json)
        except json.JSONDecodeError as exc:
            raise HTTPException(status_code=400, detail="素材附加信息格式无效") from exc
        if not isinstance(metadata, dict):
            raise HTTPException(status_code=400, detail="素材附加信息必须是对象")
    else:
        metadata = {}

    token = uuid4().hex
    relative = f"{device.id}/{token}{suffix}"
    target = _camera_path(relative)
    if target is None:
        raise HTTPException(status_code=500, detail="摄像头存储目录不可用")
    max_bytes = int(getattr(get_settings(), "device_camera_max_upload_mb", 200)) * 1024 * 1024
    saved_files: list[Path] = []
    try:
        size_bytes = await _save_upload(file, target, max_bytes)
        saved_files.append(target)
        thumbnail_relative: str | None = None
        if thumbnail is not None:
            thumb_suffix = Path(thumbnail.filename or "").suffix.lower()
            if thumb_suffix not in {".jpg", ".jpeg"}:
                raise HTTPException(status_code=400, detail="录像缩略图必须是 JPEG")
            thumbnail_relative = f"{device.id}/{token}_thumb.jpg"
            thumb_target = _camera_path(thumbnail_relative)
            if thumb_target is None:
                raise HTTPException(status_code=500, detail="摄像头存储目录不可用")
            await _save_upload(thumbnail, thumb_target, max_bytes)
            saved_files.append(thumb_target)
        asset = DeviceCameraAsset(
            device_id=device.id or 0,
            command_id=command.id if command else None,
            user_id=user_id,
            kind=kind,
            status=asset_status,
            storage_name=relative,
            thumbnail_name=thumbnail_relative,
            original_name=(file.filename or "")[:255] or None,
            content_type=content_type,
            size_bytes=size_bytes,
            duration_seconds=max(0.0, float(duration_seconds)) if duration_seconds is not None else None,
            metadata_json=_json_dump(metadata),
            captured_at=_normalize_captured_at(captured_at),
        )
        session.add(asset)
        session.commit()
        session.refresh(asset)
        return _camera_asset_read(asset)
    except Exception:
        session.rollback()
        for saved in saved_files:
            saved.unlink(missing_ok=True)
        raise


@agent_router.post("/heartbeat")
def agent_heartbeat(
    payload: AgentHeartbeat,
    _: None = Depends(require_agent_token),
    session: Session = Depends(get_session),
) -> dict[str, Any]:
    device = session.exec(select(MedicineBoxDevice).where(MedicineBoxDevice.device_uid == payload.device_uid)).first()
    if not device:
        raise HTTPException(status_code=404, detail="设备未在 App 中添加")
    device.status = "online"
    device.camera_ready = payload.camera_ready
    device.radar_ready = payload.radar_ready
    device.tts_ready = payload.tts_ready
    device.firmware_version = payload.firmware_version
    device.last_seen_at = datetime.utcnow()
    device.updated_at = device.last_seen_at
    session.add(device)
    session.commit()
    return {"success": True}


@agent_router.get("/commands/next")
def agent_next_command(
    device_uid: str = Query(min_length=3, max_length=80),
    _: None = Depends(require_agent_token),
    session: Session = Depends(get_session),
) -> dict[str, Any]:
    device = session.exec(select(MedicineBoxDevice).where(MedicineBoxDevice.device_uid == device_uid)).first()
    if not device:
        raise HTTPException(status_code=404, detail="设备未在 App 中添加")
    now = datetime.utcnow()
    expired = session.exec(
        select(DeviceCommand).where(
            DeviceCommand.device_id == device.id,
            DeviceCommand.status == "pending",
            DeviceCommand.expires_at < now,
        )
    ).all()
    for command in expired:
        command.status = "expired"
        command.completed_at = now
        session.add(command)
    command = session.exec(
        select(DeviceCommand)
        .where(
            DeviceCommand.device_id == device.id,
            DeviceCommand.status == "pending",
            DeviceCommand.expires_at >= now,
        )
        .order_by(DeviceCommand.created_at)
    ).first()
    if not command:
        session.commit()
        return {"command": None}
    command.status = "claimed"
    command.claimed_at = now
    session.add(command)
    device.status = "online"
    device.last_seen_at = now
    session.add(device)
    session.commit()
    session.refresh(command)
    return {"command": _command_read(command)}


@agent_router.post("/commands/{command_id}/result")
def agent_command_result(
    command_id: int,
    payload: AgentCommandResult,
    _: None = Depends(require_agent_token),
    session: Session = Depends(get_session),
) -> dict[str, Any]:
    device = session.exec(select(MedicineBoxDevice).where(MedicineBoxDevice.device_uid == payload.device_uid)).first()
    if not device:
        raise HTTPException(status_code=404, detail="设备未在 App 中添加")
    command = session.get(DeviceCommand, command_id)
    if not command or command.device_id != device.id:
        raise HTTPException(status_code=404, detail="命令不存在")
    command.status = "completed" if payload.success else "failed"
    command.result_json = _json_dump(payload.result)
    command.error = payload.error
    command.completed_at = datetime.utcnow()
    session.add(command)
    if payload.success and command.command_type == "face_enroll":
        command_payload = _json_load(command.payload_json, {})
        user_id = command_payload.get("user_id")
        face_key = command_payload.get("face_key")
        if user_id and face_key:
            existing = session.exec(
                select(DeviceFaceProfile).where(
                    DeviceFaceProfile.device_id == device.id,
                    DeviceFaceProfile.user_id == int(user_id),
                )
            ).first()
            if existing is None:
                existing = DeviceFaceProfile(
                    device_id=device.id or 0,
                    user_id=int(user_id),
                    face_key=str(face_key),
                    display_name=str(command_payload.get("display_name") or "家庭成员"),
                    role=str(command_payload.get("role") or "elder"),
                    announce_user_id=int(user_id),
                )
            existing.face_key = str(face_key)
            existing.display_name = str(command_payload.get("display_name") or existing.display_name)
            existing.role = str(command_payload.get("role") or existing.role)
            existing.announce_user_id = int(user_id)
            existing.sample_count = int(payload.result.get("sample_count") or 0)
            existing.status = "active"
            existing.quality_json = _json_dump(payload.result)
            existing.updated_at = datetime.utcnow()
            session.add(existing)
    elif payload.success and command.command_type == "face_delete":
        command_payload = _json_load(command.payload_json, {})
        user_id = command_payload.get("user_id")
        if user_id:
            existing = session.exec(
                select(DeviceFaceProfile).where(
                    DeviceFaceProfile.device_id == device.id,
                    DeviceFaceProfile.user_id == int(user_id),
                )
            ).first()
            if existing:
                existing.status = "deleted"
                existing.updated_at = datetime.utcnow()
                session.add(existing)
    session.commit()
    session.refresh(command)
    return _command_read(command)


@agent_router.post("/faces/sync")
def agent_sync_faces(
    payload: AgentFacesSync,
    _: None = Depends(require_agent_token),
    session: Session = Depends(get_session),
) -> dict[str, Any]:
    device = session.exec(select(MedicineBoxDevice).where(MedicineBoxDevice.device_uid == payload.device_uid)).first()
    if not device:
        raise HTTPException(status_code=404, detail="设备未在 App 中添加")
    current = session.exec(select(DeviceFaceProfile).where(DeviceFaceProfile.device_id == device.id)).all()
    for face in current:
        face.status = "missing"
        face.updated_at = datetime.utcnow()
        session.add(face)
    for item in payload.faces:
        user_id = item.get("user_id")
        face_key = str(item.get("face_key") or "")
        if not user_id or not face_key:
            continue
        existing = next((face for face in current if face.user_id == int(user_id)), None)
        if existing is None:
            existing = DeviceFaceProfile(
                device_id=device.id or 0,
                user_id=int(user_id),
                face_key=face_key,
                display_name=str(item.get("display_name") or "家庭成员"),
                role=str(item.get("role") or "elder"),
                announce_user_id=int(user_id),
            )
        existing.face_key = face_key
        existing.announce_user_id = existing.announce_user_id or int(user_id)
        existing.sample_count = int(item.get("sample_count") or 0)
        existing.status = "active"
        existing.updated_at = datetime.utcnow()
        session.add(existing)
    session.commit()
    return {"success": True}
