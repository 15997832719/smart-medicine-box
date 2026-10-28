

from __future__ import annotations

import base64
import hashlib
import hmac
import json
import os
import secrets
import time
from pathlib import Path
from datetime import datetime, timedelta, timezone
from typing import Annotated

from fastapi import APIRouter, Depends, File, Header, HTTPException, UploadFile, status
from sqlmodel import Session, select

from app.config import get_settings
from app.database import get_session
from app.models import ActivationRequest, AuditLog, AuthDevice, DeviceToken, FamilyLink, IntakeLog, Medicine, Reminder, SpeakerBinding, User, UserRole
from app.schemas import (
    AccountDeleteRequest,
    ActivationClaimRequest,
    ActivationExchangeRequest,
    ActivationStartResponse,
    AuthDeviceRead,
    AuthResponse,
    BindCodeResponse,
    BindFamilyRequest,
    DeviceCredentialRequest,
    DeviceCredentialResponse,
    DeviceLoginRequest,
    FamilyMemberRead,
    FamilyRead,
    LoginRequest,
    RegisterRequest,
    UserProfileUpdate,
    UserRead,
)


router = APIRouter(prefix="/auth", tags=["auth"])
_PBKDF2_ROUNDS = 240_000


def _bian_ma_base64(value: bytes) -> str:
    return base64.urlsafe_b64encode(value).rstrip(b"=").decode("ascii")


def _jie_ma_base64(value: str) -> bytes:
    return base64.urlsafe_b64decode(value + "=" * (-len(value) % 4))


def sheng_cheng_mi_ma_zhai_yao(password: str) -> str:
    salt = os.urandom(16)
    digest = hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), salt, _PBKDF2_ROUNDS)
    return f"pbkdf2_sha256${_PBKDF2_ROUNDS}${_bian_ma_base64(salt)}${digest.hex()}"


def jiao_yan_mi_ma_zhai_yao(password: str, encoded: str) -> bool:
    try:
        algorithm, rounds_text, salt_text, digest_text = encoded.split("$", 3)
        if algorithm != "pbkdf2_sha256":
            return False
        rounds = int(rounds_text)
        salt = _jie_ma_base64(salt_text)
        candidate = hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), salt, rounds).hex()
        return hmac.compare_digest(candidate, digest_text)
    except (TypeError, ValueError):
        return False


def _secret_digest(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def _sheng_cheng_ling_pai(user: User) -> str:
    now = datetime.now(timezone.utc)
    payload = {
        "sub": str(user.id),
        "role": user.role.value,
        "iat": int(now.timestamp()),
        "exp": int((now + timedelta(minutes=get_settings().jwt_expire_minutes)).timestamp()),
    }
    header = {"alg": "HS256", "typ": "JWT"}
    encoded_header = _bian_ma_base64(json.dumps(header, separators=(",", ":")).encode("utf-8"))
    encoded_payload = _bian_ma_base64(json.dumps(payload, separators=(",", ":")).encode("utf-8"))
    unsigned = f"{encoded_header}.{encoded_payload}"
    signature = hmac.new(get_settings().jwt_secret.encode("utf-8"), unsigned.encode("ascii"), hashlib.sha256).digest()
    return f"{unsigned}.{_bian_ma_base64(signature)}"


def _jie_xi_ling_pai(token: str) -> dict[str, object]:
    try:
        encoded_header, encoded_payload, encoded_signature = token.split(".", 2)
        unsigned = f"{encoded_header}.{encoded_payload}"
        expected = hmac.new(get_settings().jwt_secret.encode("utf-8"), unsigned.encode("ascii"), hashlib.sha256).digest()
        if not hmac.compare_digest(_jie_ma_base64(encoded_signature), expected):
            raise ValueError("signature")
        header = json.loads(_jie_ma_base64(encoded_header))
        payload = json.loads(_jie_ma_base64(encoded_payload))
        if header.get("alg") != "HS256" or not isinstance(payload, dict):
            raise ValueError("format")
        exp = payload.get("exp")
        if not isinstance(exp, (int, float)) or exp <= datetime.now(timezone.utc).timestamp():
            raise ValueError("expired")
        if not str(payload.get("sub", "")).isdigit():
            raise ValueError("subject")
        return payload
    except (ValueError, TypeError, KeyError, json.JSONDecodeError, UnicodeDecodeError) as exc:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="登录已失效，请重新登录") from exc


def yong_hu_zhuan_du_qu(user: User) -> UserRead:
    return UserRead(
        id=user.id or 0,
        phone=user.phone,
        nickname=user.nickname,
        role=user.role.value,
        avatar_url=user.avatar_url,
        gender=user.gender if user.gender in {"male", "female", "other"} else None,
        birth_date=user.birth_date,
        emergency_contact_name=user.emergency_contact_name,
        emergency_contact_phone=user.emergency_contact_phone,
        allergy_notes=user.allergy_notes,
    )


def _claim_legacy_data(session: Session, owner_id: int) -> None:

    for medicine in session.exec(select(Medicine).where(Medicine.owner_id.is_(None))).all():
        medicine.owner_id = owner_id
        session.add(medicine)
    for reminder in session.exec(select(Reminder).where(Reminder.owner_id.is_(None))).all():
        medicine = session.get(Medicine, reminder.medicine_id)
        reminder.owner_id = medicine.owner_id if medicine else owner_id
        session.add(reminder)
    for log in session.exec(select(IntakeLog).where(IntakeLog.owner_id.is_(None))).all():
        medicine = session.get(Medicine, log.medicine_id)
        log.owner_id = medicine.owner_id if medicine else owner_id
        session.add(log)


def _bearer_token(authorization: str | None) -> str:
    if not authorization or not authorization.lower().startswith("bearer "):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="请先登录")
    return authorization[7:].strip()


def get_current_user(
    authorization: Annotated[str | None, Header()] = None,
    session: Session = Depends(get_session),
) -> User:
    payload = _jie_xi_ling_pai(_bearer_token(authorization))
    user = session.get(User, int(str(payload["sub"])))
    if not user or not user.is_active:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="用户不存在或已停用")
    return user


CurrentUser = Annotated[User, Depends(get_current_user)]

_AVATAR_DIR = Path(__file__).resolve().parents[1] / "uploads" / "avatars"
_AVATAR_DIR.mkdir(parents=True, exist_ok=True)
_AVATAR_TYPES = {
    "image/jpeg": "jpg",
    "image/jpg": "jpg",
    "image/png": "png",
    "image/webp": "webp",
}


@router.get("/profile", response_model=UserRead)
def get_profile(user: CurrentUser) -> UserRead:
    return yong_hu_zhuan_du_qu(user)


@router.patch("/profile", response_model=UserRead)
def update_profile(
    payload: UserProfileUpdate,
    user: CurrentUser,
    session: Session = Depends(get_session),
) -> UserRead:
    changes = payload.model_dump(exclude_unset=True)
    if "nickname" in changes:
        nickname = (changes["nickname"] or "").strip()
        if not nickname:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="昵称不能为空")
        user.nickname = nickname
    for field in ("emergency_contact_name", "emergency_contact_phone", "allergy_notes"):
        if field in changes:
            value = changes[field]
            if isinstance(value, str):
                value = value.strip() or None
            setattr(user, field, value)
    if "gender" in changes:
        user.gender = changes["gender"]
    if "birth_date" in changes:
        user.birth_date = changes["birth_date"]
    user.updated_at = datetime.utcnow()
    session.add(user)
    session.add(
        AuditLog(
            user_id=user.id,
            action="update_profile",
            resource_type="user",
            resource_id=user.id,
            detail=",".join(sorted(changes.keys())),
        )
    )
    session.commit()
    session.refresh(user)
    return yong_hu_zhuan_du_qu(user)


@router.post("/profile/avatar", response_model=UserRead)
async def upload_profile_avatar(
    user: CurrentUser,
    image: UploadFile = File(...),
    session: Session = Depends(get_session),
) -> UserRead:
    payload = await image.read()
    if not payload:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="头像图片为空")
    if len(payload) > 5 * 1024 * 1024:
        raise HTTPException(status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE, detail="头像不能超过 5MB")
    ext = _AVATAR_TYPES.get((image.content_type or "").lower())
    if ext is None:
        suffix = Path(image.filename or "").suffix.lower().lstrip(".")
        ext = suffix if suffix in {"jpg", "jpeg", "png", "webp"} else None
    if ext is None:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="仅支持 JPG、PNG 或 WebP 图片")
    if ext == "jpeg":
        ext = "jpg"
    for old in _AVATAR_DIR.glob(f"user_{user.id}.*"):
        old.unlink(missing_ok=True)
    target = _AVATAR_DIR / f"user_{user.id}.{ext}"
    target.write_bytes(payload)
    user.avatar_url = f"/uploads/avatars/{target.name}?v={int(time.time())}"
    user.updated_at = datetime.utcnow()
    session.add(user)
    session.add(
        AuditLog(
            user_id=user.id,
            action="update_profile_avatar",
            resource_type="user",
            resource_id=user.id,
            detail=f"size={len(payload)};type={ext}",
        )
    )
    session.commit()
    session.refresh(user)
    return yong_hu_zhuan_du_qu(user)


@router.delete("/profile/avatar", response_model=UserRead)
def delete_profile_avatar(
    user: CurrentUser,
    session: Session = Depends(get_session),
) -> UserRead:
    for old in _AVATAR_DIR.glob(f"user_{user.id}.*"):
        old.unlink(missing_ok=True)
    user.avatar_url = None
    user.updated_at = datetime.utcnow()
    session.add(user)
    session.add(
        AuditLog(
            user_id=user.id,
            action="delete_profile_avatar",
            resource_type="user",
            resource_id=user.id,
            detail="avatar_removed",
        )
    )
    session.commit()
    session.refresh(user)
    return yong_hu_zhuan_du_qu(user)


def accessible_owner_ids(session: Session, user: User) -> list[int]:

    own_id = user.id or 0
    if user.role == UserRole.elder:
        return [own_id]
    linked_ids = list(
        session.exec(
            select(FamilyLink.elder_id).where(FamilyLink.child_id == user.id)
        ).all()
    )
    return [own_id, *[owner_id for owner_id in linked_ids if owner_id != own_id]]


def require_owner_access(session: Session, user: User, requested_owner_id: int | None = None) -> int:
    allowed = accessible_owner_ids(session, user)
    if requested_owner_id is not None:
        if requested_owner_id not in allowed:
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="无权访问该药箱数据")
        return requested_owner_id
    return user.id or 0


@router.post("/register", response_model=AuthResponse, status_code=status.HTTP_201_CREATED)
def register(payload: RegisterRequest, session: Session = Depends(get_session)) -> AuthResponse:
    phone = payload.phone.strip()
    if session.exec(select(User).where(User.phone == phone)).first():
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="该手机号已注册")
    user = User(
        phone=phone,
        password_hash=sheng_cheng_mi_ma_zhai_yao(payload.password),
        role=UserRole(payload.role),
        nickname=payload.nickname.strip() if payload.nickname else None,
    )
    session.add(user)
    session.commit()
    session.refresh(user)
    if user.role == UserRole.elder and session.exec(select(User.id).where(User.id != user.id)).first() is None:
        _claim_legacy_data(session, user.id or 0)
        session.commit()
    return AuthResponse(access_token=_sheng_cheng_ling_pai(user), user=yong_hu_zhuan_du_qu(user))


@router.post("/login", response_model=AuthResponse)
def login(payload: LoginRequest, session: Session = Depends(get_session)) -> AuthResponse:
    user = session.exec(select(User).where(User.phone == payload.phone.strip())).first()
    if not user or not user.is_active or not jiao_yan_mi_ma_zhai_yao(payload.password, user.password_hash):
        if user:
            session.add(
                AuditLog(
                    user_id=user.id,
                    action="login_failed",
                    resource_type="session",
                    detail="method=password",
                )
            )
            session.commit()
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="手机号或密码错误")
    session.add(
        AuditLog(
            user_id=user.id,
            action="login",
            resource_type="session",
            detail="method=password",
        )
    )
    session.commit()
    return AuthResponse(access_token=_sheng_cheng_ling_pai(user), user=yong_hu_zhuan_du_qu(user))


@router.post("/device/enable", response_model=DeviceCredentialResponse)
def enable_device_credential(
    payload: DeviceCredentialRequest,
    user: CurrentUser,
    session: Session = Depends(get_session),
) -> DeviceCredentialResponse:
    device_secret = secrets.token_urlsafe(32)
    device_id = payload.device_id.strip() if payload.device_id else secrets.token_urlsafe(12)
    now = datetime.utcnow()
    device = session.exec(select(AuthDevice).where(AuthDevice.device_id == device_id)).first()
    if device and device.user_id != user.id:
        device = None
        device_id = secrets.token_urlsafe(12)
    if device is None:
        device = AuthDevice(
            user_id=user.id or 0,
            device_id=device_id,
            platform=payload.platform,
            refresh_token_hash=_secret_digest(device_secret),
            last_seen_at=now,
        )
        session.add(device)
    else:
        device.platform = payload.platform
        device.refresh_token_hash = _secret_digest(device_secret)
        device.revoked_at = None
        device.last_seen_at = now
        session.add(device)
    session.add(
        AuditLog(
            user_id=user.id,
            action="device_enabled",
            resource_type="auth_device",
            detail=f"device_id={device_id};platform={payload.platform}",
        )
    )
    session.commit()
    return DeviceCredentialResponse(
        device_id=device_id,
        device_secret=device_secret,
        platform=payload.platform,
    )


@router.post("/device/login", response_model=AuthResponse)
def login_with_device(
    payload: DeviceLoginRequest,
    session: Session = Depends(get_session),
) -> AuthResponse:
    device = session.exec(select(AuthDevice).where(AuthDevice.device_id == payload.device_id)).first()
    if not device or device.revoked_at is not None:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="?????????")
    if not hmac.compare_digest(device.refresh_token_hash, _secret_digest(payload.device_secret)):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="??????")
    user = session.get(User, device.user_id)
    if not user or not user.is_active:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="?????????")
    device.platform = payload.platform
    device.last_seen_at = datetime.utcnow()
    session.add(device)
    session.add(
        AuditLog(
            user_id=user.id,
            action="login",
            resource_type="session",
            detail=f"method=device;device_id={payload.device_id}",
        )
    )
    session.commit()
    return AuthResponse(
        access_token=_sheng_cheng_ling_pai(user),
        user=yong_hu_zhuan_du_qu(user),
        device_id=device.device_id,
    )


@router.post("/activation/start", response_model=ActivationStartResponse)
def start_activation(session: Session = Depends(get_session)) -> ActivationStartResponse:
    now = datetime.utcnow()
    expires_at = now + timedelta(minutes=15)
    code = ""
    code_hash = ""
    for _ in range(10):
        code = f"{secrets.randbelow(1_000_000):06d}"
        code_hash = _secret_digest(code)
        collision = session.exec(
            select(ActivationRequest).where(
                ActivationRequest.elder_id.is_(None),
                ActivationRequest.code_hash == code_hash,
                ActivationRequest.expires_at > now,
            )
        ).first()
        if collision is None:
            break
    else:
        raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail="暂时无法生成开通码，请稍后重试")
    device_id = secrets.token_urlsafe(12)
    device_secret = secrets.token_urlsafe(32)
    activation = ActivationRequest(
        device_id=device_id,
        code_hash=code_hash,
        secret_hash=_secret_digest(device_secret),
        expires_at=expires_at,
    )
    session.add(activation)
    session.commit()
    session.refresh(activation)
    return ActivationStartResponse(
        activation_id=activation.id or 0,
        activation_code=code,
        device_id=device_id,
        device_secret=device_secret,
        expires_at=expires_at,
    )


@router.post("/activation/claim")
def claim_activation(
    payload: ActivationClaimRequest,
    user: CurrentUser,
    session: Session = Depends(get_session),
) -> dict[str, object]:
    if user.role != UserRole.child:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="只有家属账号可以代办开通")
    code_hash = _secret_digest(payload.activation_code.strip())
    if payload.activation_id is not None:
        activation = session.get(ActivationRequest, payload.activation_id)
        if activation and not hmac.compare_digest(activation.code_hash, code_hash):
            activation = None
    else:
        activation = session.exec(
            select(ActivationRequest)
            .where(
                ActivationRequest.elder_id.is_(None),
                ActivationRequest.expires_at > datetime.utcnow(),
            )
            .order_by(ActivationRequest.created_at.desc())
        ).all()
        activation = next(
            (item for item in activation if hmac.compare_digest(item.code_hash, code_hash)),
            None,
        )
    if activation is None:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="开通码不正确")
    if activation.expires_at <= datetime.utcnow():
        raise HTTPException(status_code=status.HTTP_410_GONE, detail="开通码已过期，请重新生成")
    if activation.elder_id is not None:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="该开通码已经被使用")

    now = datetime.utcnow()
    elder = User(
        phone=f"act-{activation.device_id}",
        password_hash=sheng_cheng_mi_ma_zhai_yao(secrets.token_urlsafe(24)),
        role=UserRole.elder,
        nickname=payload.nickname.strip(),
    )
    session.add(elder)
    session.flush()
    activation.elder_id = elder.id
    activation.claimed_at = now
    session.add(activation)
    if not session.exec(
        select(FamilyLink).where(
            FamilyLink.elder_id == elder.id,
            FamilyLink.child_id == user.id,
        )
    ).first():
        session.add(FamilyLink(elder_id=elder.id or 0, child_id=user.id or 0))
    session.commit()
    session.refresh(elder)
    return {"success": True, "elder_id": elder.id, "elder": yong_hu_zhuan_du_qu(elder).model_dump()}


@router.post("/activation/exchange", response_model=AuthResponse)
def exchange_activation(
    payload: ActivationExchangeRequest,
    session: Session = Depends(get_session),
) -> AuthResponse:
    activation = session.get(ActivationRequest, payload.activation_id)
    if not activation:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="开通请求不存在")
    if activation.elder_id is None:
        if activation.expires_at <= datetime.utcnow():
            raise HTTPException(status_code=status.HTTP_410_GONE, detail="开通码已过期，请重新生成")
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="家属还没有完成代办开通")
    if not hmac.compare_digest(activation.secret_hash, _secret_digest(payload.device_secret)):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="设备凭据无效")

    elder = session.get(User, activation.elder_id)
    if not elder or not elder.is_active:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="账号不存在或已停用")

    now = datetime.utcnow()
    device = session.exec(select(AuthDevice).where(AuthDevice.device_id == activation.device_id)).first()
    if device is None:
        device = AuthDevice(
            user_id=elder.id or 0,
            device_id=activation.device_id,
            platform=payload.platform,
            refresh_token_hash=activation.secret_hash,
            last_seen_at=now,
        )
        session.add(device)
    elif device.revoked_at is not None:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="该设备已被撤销")
    elif not hmac.compare_digest(device.refresh_token_hash, activation.secret_hash):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="设备凭据无效")
    else:
        device.platform = payload.platform
        device.last_seen_at = now
        session.add(device)
    session.commit()
    session.refresh(device)
    return AuthResponse(
        access_token=_sheng_cheng_ling_pai(elder),
        user=yong_hu_zhuan_du_qu(elder),
        device_id=device.device_id,
    )


@router.get("/devices", response_model=list[AuthDeviceRead])
def list_devices(user: CurrentUser, session: Session = Depends(get_session)) -> list[AuthDeviceRead]:
    devices = session.exec(
        select(AuthDevice).where(AuthDevice.user_id == user.id).order_by(AuthDevice.created_at.desc())
    ).all()
    return [
        AuthDeviceRead(
            id=device.id or 0,
            device_id=device.device_id,
            platform=device.platform,
            last_seen_at=device.last_seen_at,
            created_at=device.created_at,
            revoked_at=device.revoked_at,
        )
        for device in devices
    ]


@router.delete("/devices")
def revoke_all_devices(user: CurrentUser, session: Session = Depends(get_session)) -> dict[str, object]:
    devices = session.exec(
        select(AuthDevice).where(
            AuthDevice.user_id == user.id,
            AuthDevice.revoked_at.is_(None),
        )
    ).all()
    now = datetime.utcnow()
    for device in devices:
        device.revoked_at = now
        session.add(device)
    session.commit()
    return {"success": True, "revoked": len(devices)}


@router.delete("/devices/{device_id}")
def revoke_device(device_id: int, user: CurrentUser, session: Session = Depends(get_session)) -> dict[str, bool]:
    device = session.exec(
        select(AuthDevice).where(AuthDevice.id == device_id, AuthDevice.user_id == user.id)
    ).first()
    if not device:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="设备不存在")
    device.revoked_at = datetime.utcnow()
    session.add(device)
    session.commit()
    return {"success": True}


@router.delete("/account")
def delete_account(
    payload: AccountDeleteRequest,
    user: CurrentUser,
    session: Session = Depends(get_session),
) -> dict[str, object]:
    if not jiao_yan_mi_ma_zhai_yao(payload.password, user.password_hash):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="密码错误，无法删除账号")

    user_id = user.id or 0
    medicine_ids = [
        medicine.id
        for medicine in session.exec(select(Medicine).where(Medicine.owner_id == user_id)).all()
        if medicine.id is not None
    ]
    if medicine_ids:
        for reminder in session.exec(select(Reminder).where(Reminder.medicine_id.in_(medicine_ids))).all():
            session.delete(reminder)
        for log in session.exec(select(IntakeLog).where(IntakeLog.medicine_id.in_(medicine_ids))).all():
            session.delete(log)
    for reminder in session.exec(select(Reminder).where(Reminder.owner_id == user_id)).all():
        session.delete(reminder)
    for log in session.exec(select(IntakeLog).where(IntakeLog.owner_id == user_id)).all():
        session.delete(log)
    for medicine in session.exec(select(Medicine).where(Medicine.owner_id == user_id)).all():
        session.delete(medicine)
    for link in session.exec(
        select(FamilyLink).where((FamilyLink.elder_id == user_id) | (FamilyLink.child_id == user_id))
    ).all():
        session.delete(link)
    for device in session.exec(select(AuthDevice).where(AuthDevice.user_id == user_id)).all():
        session.delete(device)
    for token in session.exec(select(DeviceToken).where(DeviceToken.user_id == user_id)).all():
        session.delete(token)
    for binding in session.exec(select(SpeakerBinding).where(SpeakerBinding.user_id == user_id)).all():
        session.delete(binding)
    for activation in session.exec(select(ActivationRequest).where(ActivationRequest.elder_id == user_id)).all():
        activation.elder_id = None
        activation.claimed_at = None
        session.add(activation)


    from app.device_agent import DeviceCameraAsset, DeviceCommand, DeviceFaceProfile, MedicineBoxDevice, _camera_path
    from app.device_events import (
        DeviceAnnouncement,
        DevicePreviewFrame,
        DevicePreviewSession,
        DeviceRecognitionEvent,
        DeviceRuntimeState,
        DeviceTelemetryEvent,
        _preview_path,
    )

    owned_device_ids = [
        device.id
        for device in session.exec(select(MedicineBoxDevice).where(MedicineBoxDevice.owner_id == user_id)).all()
        if device.id is not None
    ]
    if owned_device_ids:
        for model in (
            DeviceAnnouncement,
            DeviceRecognitionEvent,
            DeviceTelemetryEvent,
            DeviceRuntimeState,
            DevicePreviewSession,
            DevicePreviewFrame,
        ):
            for row in session.exec(select(model).where(model.device_id.in_(owned_device_ids))).all():
                if isinstance(row, (DevicePreviewFrame,)):
                    try:
                        preview_path = _preview_path(row.storage_name)
                        preview_path.unlink(missing_ok=True)
                    except Exception:
                        pass
                session.delete(row)
        for asset in session.exec(select(DeviceCameraAsset).where(DeviceCameraAsset.device_id.in_(owned_device_ids))).all():
            for storage_name in (asset.storage_name, asset.thumbnail_name):
                if storage_name:
                    try:
                        target = _camera_path(storage_name)
                        if target is not None:
                            target.unlink(missing_ok=True)
                    except Exception:
                        pass
            session.delete(asset)
        for command in session.exec(select(DeviceCommand).where(DeviceCommand.device_id.in_(owned_device_ids))).all():
            session.delete(command)
        for face in session.exec(select(DeviceFaceProfile).where(DeviceFaceProfile.device_id.in_(owned_device_ids))).all():
            session.delete(face)
        for device in session.exec(select(MedicineBoxDevice).where(MedicineBoxDevice.id.in_(owned_device_ids))).all():
            session.delete(device)

    for face in session.exec(select(DeviceFaceProfile).where(DeviceFaceProfile.user_id == user_id)).all():
        session.delete(face)
    for event in session.exec(select(DeviceRecognitionEvent).where(DeviceRecognitionEvent.user_id == user_id)).all():
        session.delete(event)
    for announcement in session.exec(select(DeviceAnnouncement).where(DeviceAnnouncement.user_id == user_id)).all():
        session.delete(announcement)
    for asset in session.exec(select(DeviceCameraAsset).where(DeviceCameraAsset.user_id == user_id)).all():
        for storage_name in (asset.storage_name, asset.thumbnail_name):
            if storage_name:
                try:
                    target = _camera_path(storage_name)
                    if target is not None:
                        target.unlink(missing_ok=True)
                except Exception:
                    pass
        session.delete(asset)
    for runtime in session.exec(select(DeviceRuntimeState).where(DeviceRuntimeState.last_recognition_user_id == user_id)).all():
        runtime.last_recognition_user_id = None
        session.add(runtime)

    session.add(
        AuditLog(
            user_id=None,
            action="delete_account",
            resource_type="user",
            resource_id=user_id,
            detail=f"deleted_user_id={user_id};role={user.role.value}",
        )
    )
    session.delete(user)
    session.commit()
    return {"success": True, "deleted_user_id": user_id}


@router.post("/generate-bind-code", response_model=BindCodeResponse)
def generate_bind_code(user: CurrentUser, session: Session = Depends(get_session)) -> BindCodeResponse:
    if user.role != UserRole.elder:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="只有老人账号可以生成邀请码")
    code = f"{secrets.randbelow(1_000_000):06d}"
    expires_at = datetime.utcnow() + timedelta(hours=24)
    user.bind_code_hash = hashlib.sha256(code.encode("utf-8")).hexdigest()
    user.bind_code_expires_at = expires_at
    user.updated_at = datetime.utcnow()
    session.add(user)
    session.commit()
    return BindCodeResponse(bind_code=code, expires_at=expires_at)


@router.post("/bind-family", response_model=FamilyRead)
def bind_family(payload: BindFamilyRequest, user: CurrentUser, session: Session = Depends(get_session)) -> FamilyRead:
    if user.role != UserRole.child:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="只有家属账号可以绑定老人")
    digest = hashlib.sha256(payload.bind_code.strip().encode("utf-8")).hexdigest()
    now = datetime.utcnow()
    elder = session.exec(
        select(User).where(User.role == UserRole.elder, User.bind_code_hash == digest, User.bind_code_expires_at > now)
    ).first()
    if not elder:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="邀请码无效或已过期")
    existing = session.exec(
        select(FamilyLink).where(FamilyLink.elder_id == elder.id, FamilyLink.child_id == user.id)
    ).first()
    if not existing:
        session.add(FamilyLink(elder_id=elder.id or 0, child_id=user.id or 0))
    session.commit()
    return _family_for_user(user, session)


@router.get("/my-family", response_model=FamilyRead)
def my_family(user: CurrentUser, session: Session = Depends(get_session)) -> FamilyRead:
    return _family_for_user(user, session)


def _family_for_user(user: User, session: Session) -> FamilyRead:
    if user.role == UserRole.elder:
        links = session.exec(select(FamilyLink).where(FamilyLink.elder_id == user.id)).all()
        children = []
        for link in links:
            member = session.get(User, link.child_id)
            if member:
                children.append(FamilyMemberRead(**yong_hu_zhuan_du_qu(member).model_dump(), linked_at=link.created_at))
        return FamilyRead(children=children)
    links = session.exec(select(FamilyLink).where(FamilyLink.child_id == user.id)).all()
    elders = []
    for link in links:
        member = session.get(User, link.elder_id)
        if member:
            elders.append(FamilyMemberRead(**yong_hu_zhuan_du_qu(member).model_dump(), linked_at=link.created_at))
    return FamilyRead(elders=elders)
