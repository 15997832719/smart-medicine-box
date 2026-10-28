from __future__ import annotations

import base64
import hashlib
import hmac
import json
import logging
import secrets
import time
from dataclasses import dataclass
from datetime import datetime, timedelta
from typing import Any, Protocol

from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from fastapi import APIRouter, Depends, File, Form, HTTPException, Request, UploadFile, status
from sqlmodel import Session, select

from app.auth import _sheng_cheng_ling_pai, get_current_user, yong_hu_zhuan_du_qu
from app.config import get_settings
from app.database import get_session
from app.models import AuditLog, FaceConsent, FaceLoginAttempt, FaceLoginLock, FaceProfile, SmsLoginCode, User
from app.schemas import FaceConsentRequest, FaceStatusRead, SmsLoginRequest, SmsSendRequest

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/face", tags=["face"])
sms_router = APIRouter(prefix="/auth/sms", tags=["auth"])

FACE_CONSENT_VERSION = "v1"
FACE_PERSON_PREFIX = "smb-user-"


def _settings_ready() -> bool:
    return bool(get_settings().face_auth_enabled)


def _require_face_enabled() -> None:
    if not _settings_ready():
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="人脸登录模块尚未启用，请联系管理员完成人脸服务配置",
        )


def _encryption_key() -> bytes:
    raw = get_settings().face_encryption_key
    if not raw:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="人脸数据加密密钥未配置",
        )
    try:
        key = base64.urlsafe_b64decode(raw + "=" * (-len(raw) % 4))
    except Exception as exc:
        raise HTTPException(status_code=503, detail="人脸数据加密密钥格式错误") from exc
    if len(key) != 32:
        raise HTTPException(status_code=503, detail="人脸数据加密密钥必须为 32 字节")
    return key


def encrypt_text(value: str) -> str:
    nonce = secrets.token_bytes(12)
    encrypted = AESGCM(_encryption_key()).encrypt(nonce, value.encode("utf-8"), None)
    return base64.urlsafe_b64encode(nonce + encrypted).decode("ascii")


def decrypt_text(value: str) -> str:
    payload = base64.urlsafe_b64decode(value + "=" * (-len(value) % 4))
    plain = AESGCM(_encryption_key()).decrypt(payload[:12], payload[12:], None)
    return plain.decode("utf-8")


def normalize_face_image(content: bytes) -> bytes:
    import io

    from PIL import Image

    try:
        image = Image.open(io.BytesIO(content))
        image = image.convert("RGB")
        image.thumbnail((1000, 1000))
        output = io.BytesIO()
        image.save(output, format="JPEG", quality=88)
        normalized = output.getvalue()
    except Exception as exc:
        raise HTTPException(status_code=400, detail="图片格式无法识别，请重新拍摄") from exc
    if not normalized:
        raise HTTPException(status_code=400, detail="图片处理失败，请重新拍摄")
    logger.info("face_image_normalized original=%s normalized=%s", len(content), len(normalized))
    return normalized


class FaceProviderError(RuntimeError):
    pass


@dataclass(frozen=True)
class FaceMatch:
    person_id: str
    score: int


class FaceProvider(Protocol):
    name: str

    def enroll(self, user_id: int, image: bytes) -> tuple[str, str | None]: ...
    def search(self, image: bytes) -> FaceMatch | None: ...
    def delete(self, person_id: str) -> None: ...


class MockFaceProvider:
    name = "mock"

    def enroll(self, user_id: int, image: bytes) -> tuple[str, str | None]:
        return f"{FACE_PERSON_PREFIX}{user_id}", hashlib.sha256(image).hexdigest()

    def search(self, image: bytes) -> FaceMatch | None:
        return None

    def delete(self, person_id: str) -> None:
        return None


class TencentFaceProvider:
    name = "tencent"

    def __init__(self) -> None:
        settings = get_settings()
        if not settings.tencent_secret_id or not settings.tencent_secret_key:
            raise FaceProviderError("腾讯云 SecretId/SecretKey 未配置")
        self.secret_id = settings.tencent_secret_id
        self.secret_key = settings.tencent_secret_key
        self.region = settings.tencent_face_region
        self.group_id = settings.tencent_face_group_id

    def _request(self, action: str, payload: dict[str, Any]) -> dict[str, Any]:
        import urllib.error
        import urllib.request

        service = "iai"
        host = f"{service}.tencentcloudapi.com"
        version = "2020-03-03"
        timestamp = int(time.time())
        date = datetime.utcfromtimestamp(timestamp).strftime("%Y-%m-%d")
        body = json.dumps(payload, ensure_ascii=False, separators=(",", ":"))
        hashed_payload = hashlib.sha256(body.encode("utf-8")).hexdigest()
        canonical_headers = f"content-type:application/json; charset=utf-8\nhost:{host}\n"
        signed_headers = "content-type;host"
        canonical_request = (
            f"POST\n/\n\n{canonical_headers}\n{signed_headers}\n{hashed_payload}"
        )
        credential_scope = f"{date}/{service}/tc3_request"
        string_to_sign = (
            f"TC3-HMAC-SHA256\n{timestamp}\n{credential_scope}\n"
            f"{hashlib.sha256(canonical_request.encode('utf-8')).hexdigest()}"
        )
        secret_date = hmac.new(f"TC3{self.secret_key}".encode(), date.encode(), hashlib.sha256).digest()
        secret_service = hmac.new(secret_date, service.encode(), hashlib.sha256).digest()
        secret_signing = hmac.new(secret_service, b"tc3_request", hashlib.sha256).digest()
        signature = hmac.new(secret_signing, string_to_sign.encode(), hashlib.sha256).hexdigest()
        authorization = (
            f"TC3-HMAC-SHA256 Credential={self.secret_id}/{credential_scope}, "
            f"SignedHeaders={signed_headers}, Signature={signature}"
        )
        request = urllib.request.Request(
            f"https://{host}",
            data=body.encode("utf-8"),
            method="POST",
            headers={
                "Authorization": authorization,
                "Content-Type": "application/json; charset=utf-8",
                "Host": host,
                "X-TC-Action": action,
                "X-TC-Version": version,
                "X-TC-Timestamp": str(timestamp),
                "X-TC-Region": self.region,
            },
        )
        try:
            with urllib.request.urlopen(request, timeout=20) as response:
                payload_data = json.loads(response.read().decode("utf-8"))
        except urllib.error.HTTPError as exc:
            detail = exc.read().decode("utf-8", errors="replace")[:300]
            raise FaceProviderError(f"腾讯云人脸服务请求失败：HTTP {exc.code} {detail}") from exc
        except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as exc:
            raise FaceProviderError("腾讯云人脸服务暂时不可用") from exc
        result = payload_data.get("Response") or {}
        if result.get("Error"):
            error = result["Error"]
            raise FaceProviderError(str(error.get("Message") or "腾讯云人脸服务返回错误"))
        return result

    def _ensure_group(self) -> None:
        try:
            self._request("CreateGroup", {"GroupId": self.group_id, "GroupName": "智能药箱老人人脸库"})
        except FaceProviderError:
            # Group already exists or the account has no permission; CreatePerson will return a clear error.
            pass

    def enroll(self, user_id: int, image: bytes) -> tuple[str, str | None]:
        self._ensure_group()
        person_id = f"{FACE_PERSON_PREFIX}{user_id}"
        # 新版人脸库接口：PersonId 全局唯一，DeletePerson 不再需要 GroupId。
        try:
            self._request("DeletePerson", {"PersonId": person_id})
        except FaceProviderError:
            pass
        # 新版接口已移除 AddFace，创建人员时通过 Image 一并录入人脸。
        created = self._request(
            "CreatePerson",
            {
                "GroupId": self.group_id,
                "PersonId": person_id,
                "PersonName": f"user-{user_id}",
                "Image": base64.b64encode(image).decode("ascii"),
                "QualityControl": 1,
            },
        )
        face_id = str(created.get("FaceId") or "") or None
        return person_id, face_id

    def search(self, image: bytes) -> FaceMatch | None:
        result = self._request(
            "SearchFaces",
            {
                # 新版搜索接口使用 GroupIds 数组。
                "GroupIds": [self.group_id],
                "Image": base64.b64encode(image).decode("ascii"),
                "MaxPersonNum": 1,
            },
        )
        results = result.get("Results") or []
        candidates = results[0].get("Candidates") if results else None
        if not candidates:
            return None
        candidate = candidates[0]
        return FaceMatch(str(candidate.get("PersonId") or ""), int(candidate.get("Score") or 0))

    def delete(self, person_id: str) -> None:
        self._request("DeletePerson", {"PersonId": person_id})


def get_face_provider() -> FaceProvider:
    provider = get_settings().face_provider.strip().lower()
    if provider == "mock":
        return MockFaceProvider()
    if provider == "tencent":
        return TencentFaceProvider()
    raise FaceProviderError(f"不支持的人脸服务提供商：{provider}")


def _client_ip(request: Request | None) -> str | None:
    if request is None or request.client is None:
        return None
    return request.client.host


def _device_key(value: str) -> str:
    normalized = (value or "").strip()
    if len(normalized) < 8:
        raise HTTPException(status_code=400, detail="设备标识无效")
    return normalized[:120]


def _get_lock(session: Session, device_key: str) -> FaceLoginLock:
    lock = session.exec(select(FaceLoginLock).where(FaceLoginLock.device_key == device_key)).first()
    if lock is None:
        lock = FaceLoginLock(device_key=device_key)
        session.add(lock)
    return lock


def _lock_state(session: Session, device_key: str) -> FaceLoginLock:
    lock = _get_lock(session, device_key)
    if lock.blocked_until and lock.blocked_until > datetime.utcnow():
        return lock
    if lock.blocked_until and lock.blocked_until <= datetime.utcnow():
        lock.blocked_until = None
        lock.failures = 0
        session.add(lock)
    return lock


def _record_face_failure(session: Session, device_key: str, ip: str | None, reason: str) -> None:
    settings = get_settings()
    lock = _lock_state(session, device_key)
    lock.failures += 1
    lock.updated_at = datetime.utcnow()
    if lock.failures >= settings.face_max_failures:
        lock.blocked_until = datetime.utcnow() + timedelta(minutes=settings.face_lock_minutes)
    session.add(lock)
    session.add(
        FaceLoginAttempt(
            device_key=device_key,
            client_ip=ip,
            success=False,
            reason=reason[:120],
        )
    )
    session.commit()


def _record_face_success(session: Session, device_key: str, ip: str | None, user_id: int, score: int) -> None:
    lock = _lock_state(session, device_key)
    lock.failures = 0
    lock.blocked_until = None
    lock.updated_at = datetime.utcnow()
    session.add(lock)
    session.add(
        FaceLoginAttempt(
            device_key=device_key,
            client_ip=ip,
            success=True,
            score=score,
            matched_user_id=user_id,
        )
    )
    session.commit()


def _auth_response(user: User) -> dict[str, Any]:
    return {
        "access_token": _sheng_cheng_ling_pai(user),
        "token_type": "bearer",
        "user": yong_hu_zhuan_du_qu(user).model_dump(),
    }


@router.get("/status", response_model=FaceStatusRead)
def face_status(user: User = Depends(get_current_user), session: Session = Depends(get_session)) -> FaceStatusRead:
    profile = session.exec(select(FaceProfile).where(FaceProfile.user_id == user.id)).first()
    return FaceStatusRead(
        enabled=bool(get_settings().face_auth_enabled),
        enrolled=bool(profile and profile.status == "active"),
        provider=profile.provider if profile else get_settings().face_provider,
        status=profile.status if profile else None,
        last_verified_at=profile.last_verified_at if profile else None,
    )


@router.post("/consent", response_model=FaceStatusRead)
def record_face_consent(
    payload: FaceConsentRequest,
    request: Request,
    user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
) -> FaceStatusRead:
    consent = session.exec(select(FaceConsent).where(FaceConsent.user_id == user.id)).first()
    if consent is None:
        consent = FaceConsent(
            user_id=user.id or 0,
            version=payload.version,
            client_ip=_client_ip(request),
            user_agent=(request.headers.get("user-agent") or "")[:300] if request else None,
        )
        session.add(consent)
    else:
        consent.version = payload.version
        consent.agreed_at = datetime.utcnow()
        consent.client_ip = _client_ip(request)
        consent.user_agent = (request.headers.get("user-agent") or "")[:300] if request else None
        session.add(consent)
    session.add(
        AuditLog(
            user_id=user.id,
            action="face_consent",
            resource_type="face_consent",
            detail=f"version={payload.version}",
        )
    )
    session.commit()
    return face_status(user, session)


@router.post("/enroll")
async def enroll_face(
    image: UploadFile = File(...),
    device_key: str = Form(...),
    user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
) -> dict[str, Any]:
    _require_face_enabled()
    _device_key(device_key)
    consent = session.exec(select(FaceConsent).where(FaceConsent.user_id == user.id)).first()
    if consent is None:
        raise HTTPException(status_code=400, detail="请先阅读并同意人脸识别隐私协议")
    content = normalize_face_image(await await_image(image))
    try:
        provider = get_face_provider()
        person_id, face_id = provider.enroll(user.id or 0, content)
    except FaceProviderError as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc
    profile = session.exec(select(FaceProfile).where(FaceProfile.user_id == user.id)).first()
    if profile is None:
        profile = FaceProfile(user_id=user.id or 0)
    profile.provider = provider.name
    profile.person_id_encrypted = encrypt_text(person_id)
    profile.face_id_encrypted = encrypt_text(face_id) if face_id else None
    profile.status = "active"
    profile.updated_at = datetime.utcnow()
    session.add(profile)
    session.add(
        AuditLog(
            user_id=user.id,
            action="face_enroll",
            resource_type="face_profile",
            detail=f"provider={provider.name}",
        )
    )
    session.commit()
    return {"success": True, "enrolled": True, "provider": provider.name}


@router.delete("/enroll")
def delete_face(
    user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
) -> dict[str, Any]:
    profile = session.exec(select(FaceProfile).where(FaceProfile.user_id == user.id)).first()
    if profile is None:
        return {"success": True, "deleted": False}
    try:
        person_id = decrypt_text(profile.person_id_encrypted)
        get_face_provider().delete(person_id)
    except FaceProviderError as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc
    session.delete(profile)
    session.add(
        AuditLog(
            user_id=user.id,
            action="face_delete",
            resource_type="face_profile",
            detail=f"provider={profile.provider}",
        )
    )
    session.commit()
    return {"success": True, "deleted": True}


@router.post("/login")
async def face_login(
    request: Request,
    image: UploadFile = File(...),
    device_key: str = Form(...),
    session: Session = Depends(get_session),
) -> dict[str, Any]:
    _require_face_enabled()
    key = _device_key(device_key)
    lock = _lock_state(session, key)
    if lock.blocked_until and lock.blocked_until > datetime.utcnow():
        raise HTTPException(
            status_code=status.HTTP_423_LOCKED,
            detail={
                "code": "FACE_LOGIN_LOCKED",
                "message": "刷脸失败次数过多，请使用手机号验证码登录",
                "retry_after_seconds": int((lock.blocked_until - datetime.utcnow()).total_seconds()),
            },
        )
    content = normalize_face_image(await await_image(image))
    try:
        match = get_face_provider().search(content)
    except FaceProviderError as exc:
        _record_face_failure(session, key, _client_ip(request), "provider_error")
        raise HTTPException(status_code=503, detail=str(exc)) from exc
    threshold = get_settings().face_search_threshold
    if match is None or match.score < threshold or not match.person_id.startswith(FACE_PERSON_PREFIX):
        _record_face_failure(session, key, _client_ip(request), "no_match")
        raise HTTPException(status_code=401, detail={"code": "FACE_LOGIN_FAILED", "message": "人脸比对失败，请重试或使用手机号验证码登录"})
    try:
        user_id = int(match.person_id[len(FACE_PERSON_PREFIX):])
    except ValueError:
        _record_face_failure(session, key, _client_ip(request), "invalid_person")
        raise HTTPException(status_code=401, detail={"code": "FACE_LOGIN_FAILED", "message": "人脸比对失败"}) from None
    user = session.get(User, user_id)
    profile = session.exec(select(FaceProfile).where(FaceProfile.user_id == user_id)).first()
    if not user or not user.is_active or not profile or profile.status != "active":
        _record_face_failure(session, key, _client_ip(request), "account_unavailable")
        raise HTTPException(status_code=401, detail={"code": "FACE_LOGIN_FAILED", "message": "账号不可用，请使用手机号验证码登录"})
    profile.last_verified_at = datetime.utcnow()
    profile.updated_at = datetime.utcnow()
    session.add(profile)
    _record_face_success(session, key, _client_ip(request), user_id, match.score)
    session.add(
        AuditLog(
            user_id=user.id,
            action="login",
            resource_type="session",
            detail=f"method=face;score={match.score}",
        )
    )
    session.commit()
    response = _auth_response(user)
    response["score"] = match.score
    return response


async def await_image(image: UploadFile) -> bytes:
    content = await image.read()
    await image.close()
    if not content:
        raise HTTPException(status_code=400, detail="人脸图片为空")
    if len(content) > 8 * 1024 * 1024:
        raise HTTPException(status_code=413, detail="人脸图片不能超过 8 MB")
    return content


def _code_hash(phone: str, code: str) -> str:
    return hashlib.sha256(f"{phone}:{code}".encode("utf-8")).hexdigest()


@sms_router.post("/send")
def send_sms_code(payload: SmsSendRequest, session: Session = Depends(get_session)) -> dict[str, Any]:
    phone = payload.phone.strip()
    user = session.exec(select(User).where(User.phone == phone)).first()
    if not user or not user.is_active:
        return {"success": True}
    code = f"{secrets.randbelow(1_000_000):06d}"
    settings = get_settings()
    session.add(
        SmsLoginCode(
            phone=phone,
            code_hash=_code_hash(phone, code),
            expires_at=datetime.utcnow() + timedelta(minutes=settings.sms_code_ttl_minutes),
        )
    )
    session.commit()
    if settings.sms_provider == "debug":
        logger.warning("sms_debug_code phone=%s code=%s", phone, code)
        return {"success": True, "debug_code": code}
    return {"success": True}


@sms_router.post("/login")
def sms_login(payload: SmsLoginRequest, session: Session = Depends(get_session)) -> dict[str, Any]:
    phone = payload.phone.strip()
    user = session.exec(select(User).where(User.phone == phone)).first()
    if not user or not user.is_active:
        raise HTTPException(status_code=401, detail="手机号或验证码错误")
    record = session.exec(
        select(SmsLoginCode)
        .where(SmsLoginCode.phone == phone, SmsLoginCode.used_at.is_(None))
        .order_by(SmsLoginCode.created_at.desc())
    ).first()
    if not record or record.expires_at <= datetime.utcnow():
        raise HTTPException(status_code=401, detail="验证码已过期，请重新获取")
    record.attempts += 1
    if record.attempts > 5:
        session.add(record)
        session.commit()
        raise HTTPException(status_code=429, detail="验证码尝试次数过多，请重新获取")
    if not hmac.compare_digest(record.code_hash, _code_hash(phone, payload.code.strip())):
        session.add(record)
        session.commit()
        raise HTTPException(status_code=401, detail="手机号或验证码错误")
    record.used_at = datetime.utcnow()
    session.add(record)
    session.add(
        AuditLog(
            user_id=user.id,
            action="login",
            resource_type="session",
            detail="method=sms",
        )
    )
    session.commit()
    return _auth_response(user)
