

from __future__ import annotations

import base64
import hashlib
import hmac
import json
import os
import secrets
from datetime import datetime, timedelta, timezone
from typing import Annotated

from fastapi import APIRouter, Depends, Header, HTTPException, status
from sqlmodel import Session, select

from app.config import get_settings
from app.database import get_session
from app.models import FamilyLink, IntakeLog, Medicine, Reminder, User, UserRole
from app.schemas import (
    AuthResponse,
    BindCodeResponse,
    BindFamilyRequest,
    FamilyMemberRead,
    FamilyRead,
    LoginRequest,
    RegisterRequest,
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
    return UserRead(id=user.id or 0, phone=user.phone, nickname=user.nickname, role=user.role.value)


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


def accessible_owner_ids(session: Session, user: User) -> list[int]:

    if user.role == UserRole.elder:
        return [user.id or 0]
    return list(session.exec(select(FamilyLink.elder_id).where(FamilyLink.child_id == user.id)).all())


def require_owner_access(session: Session, user: User, requested_owner_id: int | None = None) -> int:
    allowed = accessible_owner_ids(session, user)
    if requested_owner_id is not None:
        if requested_owner_id not in allowed:
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="无权访问该老人数据")
        return requested_owner_id
    if user.role == UserRole.elder:
        return user.id or 0
    if len(allowed) == 1:
        return allowed[0]
    if not allowed:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="请先绑定老人账号")
    raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="请通过 elder_id 指定要查看的老人")


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
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="手机号或密码错误")
    return AuthResponse(access_token=_sheng_cheng_ling_pai(user), user=yong_hu_zhuan_du_qu(user))


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
