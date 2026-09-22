from datetime import date, datetime, time, timedelta
from pathlib import Path
import secrets
import re
import tempfile

from starlette.concurrency import run_in_threadpool

from fastapi import APIRouter, Depends, File, HTTPException, Query, UploadFile, status
from sqlmodel import Session, select

from app.asr import ASRError, transcribe_audio_file
from app.auth import accessible_owner_ids, get_current_user, require_owner_access
from app.config import get_settings
from app.database import get_session
from app.models import AuditLog, DeviceToken, IntakeLog, Medicine, Reminder, User, SpeakerBinding
from app.schemas import (
    AlertRead,
    ConflictCheckRequest,
    ConflictRead,
    DeviceTokenRequest,
    InstructionParseRequest,
    InstructionParseResult,
    IntakeLogCreate,
    IntakeLogRead,
    LogConfirmRequest,
    MedicineCreate,
    MedicineRead,
    MedicineUpdate,
    RecognizeResult,
    ReminderCreate,
    ReminderRead,
    ReminderUpdate,
    ScheduleUpdate,
    VoiceIntentRequest,
)
from app.voice_intents import VoiceIntent, shi_bie_yu_yin_yi_tu, gui_fan_hua_yu_yin_wen_ben
from app.services import (
    MedicineRecognitionError,
    gou_jian_yao_pin,
    check_conflicts,
    lie_chu_jing_gao,
    parse_instruction_ai,
    recognize_medicine_image,
    biao_qian_zhuan_zi_fu_chuan,
    yao_pin_zhuan_du_qu,
    utcnow,
)


router = APIRouter()

@router.post("/speaker/pairing-code")
def create_speaker_pairing_code(user: User = Depends(get_current_user), session: Session = Depends(get_session)) -> dict:
    code = str(secrets.randbelow(900000) + 100000)
    pending_id = f"pending-{user.id}"
    binding = session.exec(select(SpeakerBinding).where(SpeakerBinding.user_id == user.id, SpeakerBinding.speaker_id == pending_id)).first()
    if not binding:
        binding = SpeakerBinding(speaker_id=pending_id, user_id=user.id or 0)
        session.add(binding)
    binding.pairing_code = code
    binding.code_expires_at = datetime.utcnow() + timedelta(minutes=10)
    session.commit()
    return {"code": code, "expires_in": 600}

@router.post("/speaker/bind")
def bind_speaker(payload: dict, user: User = Depends(get_current_user), session: Session = Depends(get_session)) -> dict:
    speaker_id = str(payload.get("speaker_id") or payload.get("device_id") or "").strip()
    code = str(payload.get("code") or payload.get("pairing_code") or "").strip()
    if not speaker_id or len(code) != 6:
        raise HTTPException(status_code=400, detail="speaker_id and six-digit code are required")
    binding = session.exec(select(SpeakerBinding).where(SpeakerBinding.pairing_code == code)).first()
    if not binding or binding.user_id != user.id or not binding.code_expires_at or binding.code_expires_at < datetime.utcnow():
        raise HTTPException(status_code=400, detail="pairing code is invalid or expired")
    binding.speaker_id = speaker_id
    binding.pairing_code = None
    binding.code_expires_at = None
    session.add(binding); session.commit()
    return {"success": True, "speaker_id": speaker_id, "user_id": user.id}

PENDING_SPEAKER_PREFIX = "pending-"


@router.get("/speaker/bindings")
def list_speaker_bindings(user: User = Depends(get_current_user), session: Session = Depends(get_session)) -> list[dict]:

    bindings = session.exec(
        select(SpeakerBinding).where(SpeakerBinding.user_id == user.id).order_by(SpeakerBinding.created_at)
    ).all()
    return [
        {
            "id": binding.id,
            "speaker_id": binding.speaker_id,
            "platform": binding.platform,
            "created_at": binding.created_at.isoformat() if binding.created_at else None,
        }
        for binding in bindings
        if binding.speaker_id and not binding.speaker_id.startswith(PENDING_SPEAKER_PREFIX)
    ]


@router.delete("/speaker/bindings/{binding_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_speaker_binding(binding_id: int, user: User = Depends(get_current_user), session: Session = Depends(get_session)) -> None:

    binding = session.exec(
        select(SpeakerBinding).where(SpeakerBinding.id == binding_id, SpeakerBinding.user_id == user.id)
    ).first()
    if not binding:
        raise HTTPException(status_code=404, detail="Speaker binding not found")
    session.delete(binding)
    session.commit()


@router.post("/devices/push-token", status_code=status.HTTP_204_NO_CONTENT)
def register_push_token(payload: DeviceTokenRequest, user: User = Depends(get_current_user), session: Session = Depends(get_session)) -> None:
    token = session.exec(select(DeviceToken).where(DeviceToken.registration_id == payload.registration_id)).first()
    if token:
        token.user_id = user.id or 0
        token.platform = payload.platform
        token.updated_at = datetime.utcnow()
    else:
        session.add(DeviceToken(user_id=user.id or 0, registration_id=payload.registration_id, platform=payload.platform))
    session.commit()


@router.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok", "time": utcnow().isoformat()}


def _medicine_query(session: Session, owner_id: int, medicine_id: int) -> Medicine:
    medicine = session.exec(select(Medicine).where(Medicine.id == medicine_id, Medicine.owner_id == owner_id)).first()
    if not medicine:
        raise HTTPException(status_code=404, detail="Medicine not found")
    return medicine


def _owner_for_request(session: Session, user: User, elder_id: int | None) -> int:
    return require_owner_access(session, user, elder_id)


def _reminder_read(reminder: Reminder) -> ReminderRead:
    data = reminder.model_dump()
    data["user_id"] = reminder.owner_id
    return ReminderRead(**data)


def _schedule_matches_day(reminder: Reminder, day: date) -> bool:
    return reminder.schedule_date is None or reminder.schedule_date == day


def _intake_read(log: IntakeLog) -> IntakeLogRead:
    data = log.model_dump()
    data["user_id"] = log.owner_id
    return IntakeLogRead(**data)


@router.get("/medicines", response_model=list[MedicineRead])
def list_medicines(
    elder_id: int | None = Query(default=None),
    user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
) -> list[MedicineRead]:
    owner_id = _owner_for_request(session, user, elder_id)
    medicines = session.exec(select(Medicine).where(Medicine.owner_id == owner_id).order_by(Medicine.created_at.desc())).all()
    return [yao_pin_zhuan_du_qu(medicine) for medicine in medicines]


@router.post("/medicines", response_model=MedicineRead, status_code=status.HTTP_201_CREATED)
def create_medicine(
    payload: MedicineCreate,
    elder_id: int | None = Query(default=None),
    user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
) -> MedicineRead:
    owner_id = _owner_for_request(session, user, elder_id)
    medicine = gou_jian_yao_pin(payload)
    medicine.owner_id = owner_id
    session.add(medicine)
    session.commit()
    session.refresh(medicine)
    session.add(AuditLog(user_id=user.id, action="create", resource_type="medicine", resource_id=medicine.id, detail="medicine created"))
    session.commit()
    return yao_pin_zhuan_du_qu(medicine)


@router.get("/medicines/{medicine_id}", response_model=MedicineRead)
def get_medicine(medicine_id: int, user: User = Depends(get_current_user), session: Session = Depends(get_session)) -> MedicineRead:
    allowed = accessible_owner_ids(session, user)
    medicine = session.exec(select(Medicine).where(Medicine.id == medicine_id, Medicine.owner_id.in_(allowed))).first()
    if not medicine:
        raise HTTPException(status_code=404, detail="Medicine not found")
    return yao_pin_zhuan_du_qu(medicine)


@router.patch("/medicines/{medicine_id}", response_model=MedicineRead)
def update_medicine(medicine_id: int, payload: MedicineUpdate, user: User = Depends(get_current_user), session: Session = Depends(get_session)) -> MedicineRead:
    allowed = accessible_owner_ids(session, user)
    medicine = session.exec(select(Medicine).where(Medicine.id == medicine_id, Medicine.owner_id.in_(allowed))).first()
    if not medicine:
        raise HTTPException(status_code=404, detail="Medicine not found")
    data = payload.model_dump(exclude_unset=True)
    if "conflict_tags" in data:
        medicine.conflict_tags = biao_qian_zhuan_zi_fu_chuan(data.pop("conflict_tags"))
    for key, value in data.items():
        setattr(medicine, key, value)
    medicine.updated_at = datetime.utcnow()
    session.add(medicine)
    session.commit()
    session.refresh(medicine)
    return yao_pin_zhuan_du_qu(medicine)


@router.delete("/medicines/{medicine_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_medicine(medicine_id: int, user: User = Depends(get_current_user), session: Session = Depends(get_session)) -> None:
    allowed = accessible_owner_ids(session, user)
    medicine = session.exec(select(Medicine).where(Medicine.id == medicine_id, Medicine.owner_id.in_(allowed))).first()
    if not medicine:
        raise HTTPException(status_code=404, detail="Medicine not found")
    for reminder in session.exec(select(Reminder).where(Reminder.medicine_id == medicine_id)).all():
        session.delete(reminder)
    for log in session.exec(select(IntakeLog).where(IntakeLog.medicine_id == medicine_id)).all():
        session.delete(log)
    session.delete(medicine)
    session.commit()


@router.get("/medicines/expiring/list", response_model=list[MedicineRead])
def list_expiring_medicines(
    days: int = Query(default=30, ge=0, le=3650),
    elder_id: int | None = Query(default=None),
    user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
) -> list[MedicineRead]:
    owner_id = _owner_for_request(session, user, elder_id)
    cutoff = date.today() + timedelta(days=days)
    medicines = session.exec(
        select(Medicine).where(Medicine.owner_id == owner_id, Medicine.expire_date.is_not(None), Medicine.expire_date <= cutoff)
    ).all()
    return [yao_pin_zhuan_du_qu(medicine) for medicine in medicines]


@router.get("/reminders", response_model=list[ReminderRead])
def list_reminders(
    elder_id: int | None = Query(default=None),
    user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
) -> list[ReminderRead]:
    owner_id = _owner_for_request(session, user, elder_id)
    reminders = session.exec(select(Reminder).where(Reminder.owner_id == owner_id).order_by(Reminder.remind_time)).all()
    return [_reminder_read(reminder) for reminder in reminders]


@router.post("/reminders", response_model=ReminderRead, status_code=status.HTTP_201_CREATED)
def create_reminder(
    payload: ReminderCreate,
    elder_id: int | None = Query(default=None),
    user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
) -> ReminderRead:
    owner_id = _owner_for_request(session, user, elder_id)
    _medicine_query(session, owner_id, payload.medicine_id)
    reminder = Reminder(**payload.model_dump(), owner_id=owner_id)
    session.add(reminder)
    session.commit()
    session.refresh(reminder)
    return _reminder_read(reminder)


@router.patch("/reminders/{reminder_id}", response_model=ReminderRead)
def update_reminder(reminder_id: int, payload: ReminderUpdate, user: User = Depends(get_current_user), session: Session = Depends(get_session)) -> ReminderRead:
    allowed = accessible_owner_ids(session, user)
    reminder = session.exec(select(Reminder).where(Reminder.id == reminder_id, Reminder.owner_id.in_(allowed))).first()
    if not reminder:
        raise HTTPException(status_code=404, detail="Reminder not found")
    for key, value in payload.model_dump(exclude_unset=True).items():
        setattr(reminder, key, value)
    session.add(reminder)
    session.commit()
    session.refresh(reminder)
    return _reminder_read(reminder)


@router.delete("/reminders/{reminder_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_reminder(reminder_id: int, user: User = Depends(get_current_user), session: Session = Depends(get_session)) -> None:
    allowed = accessible_owner_ids(session, user)
    reminder = session.exec(select(Reminder).where(Reminder.id == reminder_id, Reminder.owner_id.in_(allowed))).first()
    if not reminder:
        raise HTTPException(status_code=404, detail="Reminder not found")
    session.delete(reminder)
    session.commit()


@router.get("/schedules", response_model=list[ReminderRead])
def list_schedules(elder_id: int | None = Query(default=None), user: User = Depends(get_current_user), session: Session = Depends(get_session)):
    return list_reminders(elder_id=elder_id, user=user, session=session)


@router.post("/schedules", response_model=ReminderRead, status_code=status.HTTP_201_CREATED)
def create_schedule(payload: ReminderCreate, elder_id: int | None = Query(default=None), user: User = Depends(get_current_user), session: Session = Depends(get_session)):
    return create_reminder(payload=payload, elder_id=elder_id, user=user, session=session)


@router.patch("/schedules/{schedule_id}", response_model=ReminderRead)
def update_schedule(schedule_id: int, payload: ScheduleUpdate, user: User = Depends(get_current_user), session: Session = Depends(get_session)):
    allowed = accessible_owner_ids(session, user)
    reminder = session.exec(select(Reminder).where(Reminder.id == schedule_id, Reminder.owner_id.in_(allowed))).first()
    if not reminder:
        raise HTTPException(status_code=404, detail="Schedule not found")
    data = payload.model_dump(exclude_unset=True)
    if data.get("medicine_id") is not None:
        _medicine_query(session, reminder.owner_id or 0, data["medicine_id"])
    if "is_active" in data and "enabled" not in data:
        data["enabled"] = data.pop("is_active")
    else:
        data.pop("is_active", None)
    for key, value in data.items():
        setattr(reminder, key, value)
    session.add(reminder)
    session.commit()
    session.refresh(reminder)
    return _reminder_read(reminder)


@router.delete("/schedules/{schedule_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_schedule(schedule_id: int, user: User = Depends(get_current_user), session: Session = Depends(get_session)) -> None:
    delete_reminder(schedule_id, user, session)


def _confirm_schedule(schedule_id: int, method: str, user: User, session: Session) -> tuple[IntakeLog, str]:
    allowed = accessible_owner_ids(session, user)
    reminder = session.exec(select(Reminder).where(Reminder.id == schedule_id, Reminder.owner_id.in_(allowed))).first()
    if not reminder:
        raise HTTPException(status_code=404, detail="Schedule not found")
    if reminder.schedule_date is not None and reminder.schedule_date > date.today():
        raise HTTPException(status_code=400, detail="Schedule date is in the future")
    medicine = _medicine_query(session, reminder.owner_id or 0, reminder.medicine_id)
    now = datetime.utcnow()
    day_start = datetime.combine(now.date(), time.min)
    existing = session.exec(
        select(IntakeLog).where(
            IntakeLog.owner_id == reminder.owner_id,
            IntakeLog.medicine_id == medicine.id,
            IntakeLog.taken_at >= day_start,
            IntakeLog.note.contains(f"schedule:{schedule_id}"),
        )
    ).first()
    if existing:
        return existing, f"今天已经记录过{medicine.name}。"
    log = IntakeLog(
        owner_id=reminder.owner_id,
        medicine_id=medicine.id or 0,
        dose=reminder.dose,
        note=f"schedule:{schedule_id};confirm:{method}",
        taken_at=now,
    )
    if medicine.stock_count > 0:
        medicine.stock_count -= 1
        medicine.updated_at = now
        session.add(medicine)
    session.add(log)
    session.commit()
    session.refresh(log)
    return log, f"已记录你服用了{medicine.name}。"


@router.post("/intake-logs", response_model=IntakeLogRead, status_code=status.HTTP_201_CREATED)
def create_intake_log(payload: IntakeLogCreate, elder_id: int | None = Query(default=None), user: User = Depends(get_current_user), session: Session = Depends(get_session)) -> IntakeLogRead:
    owner_id = _owner_for_request(session, user, elder_id)
    medicine = _medicine_query(session, owner_id, payload.medicine_id)
    log = IntakeLog(owner_id=owner_id, medicine_id=payload.medicine_id, dose=payload.dose, note=payload.note, taken_at=payload.taken_at or datetime.utcnow())
    if medicine.stock_count > 0:
        medicine.stock_count -= 1
        medicine.updated_at = datetime.utcnow()
        session.add(medicine)
    session.add(log)
    session.commit()
    session.refresh(log)
    return _intake_read(log)


@router.get("/intake-logs", response_model=list[IntakeLogRead])
def list_intake_logs(elder_id: int | None = Query(default=None), user: User = Depends(get_current_user), session: Session = Depends(get_session)) -> list[IntakeLogRead]:
    owner_id = _owner_for_request(session, user, elder_id)
    logs = session.exec(select(IntakeLog).where(IntakeLog.owner_id == owner_id).order_by(IntakeLog.taken_at.desc()).limit(100)).all()
    return [_intake_read(log) for log in logs]


@router.get("/alerts", response_model=list[AlertRead])
def get_alerts(elder_id: int | None = Query(default=None), user: User = Depends(get_current_user), session: Session = Depends(get_session)) -> list[AlertRead]:
    owner_id = _owner_for_request(session, user, elder_id)
    alerts = lie_chu_jing_gao(session, [owner_id])
    now = datetime.utcnow()
    start = datetime.combine(now.date(), time.min)
    logs = session.exec(
        select(IntakeLog).where(
            IntakeLog.owner_id == owner_id,
            IntakeLog.taken_at >= start,
            IntakeLog.taken_at < start + timedelta(days=1),
        )
    ).all()
    confirmed_schedule_ids = {
        int(match.group(1))
        for log in logs
        for match in [re.search(r"schedule:(\d+)", log.note or "")]
        if match
    }
    reminders = [
        reminder
        for reminder in session.exec(
            select(Reminder).where(Reminder.owner_id == owner_id, Reminder.enabled.is_(True))
        ).all()
        if _schedule_matches_day(reminder, now.date())
    ]
    for reminder in reminders:
        due_at = datetime.combine(now.date(), reminder.remind_time)
        if due_at + timedelta(minutes=90) > now or reminder.id in confirmed_schedule_ids:
            continue
        medicine = session.get(Medicine, reminder.medicine_id)
        if medicine:
            alerts.append(
                AlertRead(
                    type="missed_medication",
                    severity="high",
                    medicine_id=medicine.id or 0,
                    medicine_name=medicine.name,
                    message=f"{medicine.name} 计划时间后仍未确认服用，请尽快核实。",
                )
            )
    return alerts


@router.post("/conflicts/check", response_model=list[ConflictRead])
def check_medicine_conflicts(payload: ConflictCheckRequest, user: User = Depends(get_current_user), session: Session = Depends(get_session)) -> list[ConflictRead]:
    allowed = accessible_owner_ids(session, user)
    medicines = session.exec(select(Medicine).where(Medicine.id.in_(payload.medicine_ids), Medicine.owner_id.in_(allowed))).all()
    return check_conflicts(medicines, payload.names)


@router.post("/ai/recognize-medicine", response_model=RecognizeResult)
async def recognize_medicine(image: UploadFile = File(...), user: User = Depends(get_current_user)) -> RecognizeResult:
    try:
        return await recognize_medicine_image(await image.read(), image.content_type)
    except MedicineRecognitionError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc


@router.post("/ai/parse-instruction", response_model=InstructionParseResult)
async def parse_instruction(payload: InstructionParseRequest, user: User = Depends(get_current_user)) -> InstructionParseResult:
    try:
        return await parse_instruction_ai(payload.text)
    except MedicineRecognitionError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc


@router.get("/ai/status")
def ai_status(user: User = Depends(get_current_user)) -> dict[str, object]:
    settings = get_settings()
    return {
        "configured": bool(settings.zhipu_api_key),
        "vision_model": settings.zhipu_vision_model,
        "text_model": settings.zhipu_text_model,
    }


def _today_summary(owner_id: int, session: Session) -> dict:
    today = date.today()
    start = datetime.combine(today, time.min)
    end = start + timedelta(days=1)
    reminders = [
        reminder
        for reminder in session.exec(
            select(Reminder).where(Reminder.owner_id == owner_id, Reminder.enabled.is_(True))
        ).all()
        if _schedule_matches_day(reminder, today)
    ]
    logs = session.exec(select(IntakeLog).where(IntakeLog.owner_id == owner_id, IntakeLog.taken_at >= start, IntakeLog.taken_at < end)).all()
    now = datetime.utcnow()
    confirmed_schedule_ids = {
        int(match.group(1))
        for log in logs
        for match in [re.search(r"schedule:(\d+)", log.note or "")]
        if match
    }
    items = []
    for log in logs:
        medicine = session.get(Medicine, log.medicine_id)
        items.append({"id": log.id, "user_id": owner_id, "medicine_id": log.medicine_id, "medicine_name": medicine.name if medicine else None, "actual_time": log.taken_at, "planned_time": log.taken_at, "status": "taken", "confirm_method": log.note})
    taken = min(len(confirmed_schedule_ids), len(reminders)) if reminders else len(logs)
    missed = sum(
        1
        for reminder in reminders
        if reminder.id not in confirmed_schedule_ids
        and datetime.combine(today, reminder.remind_time) + timedelta(minutes=90) <= now
    )
    return {
        "date": today.isoformat(),
        "total": len(reminders),
        "taken": taken,
        "missed": missed,
        "pending": max(0, len(reminders) - taken - missed),
        "logs": items,
    }


@router.get("/logs/today")
def logs_today(elder_id: int | None = Query(default=None), user: User = Depends(get_current_user), session: Session = Depends(get_session)):
    return _today_summary(_owner_for_request(session, user, elder_id), session)


@router.get("/logs/week")
def logs_week(elder_id: int | None = Query(default=None), user: User = Depends(get_current_user), session: Session = Depends(get_session)):
    owner_id = _owner_for_request(session, user, elder_id)
    start = datetime.combine(date.today() - timedelta(days=6), time.min)
    logs = session.exec(select(IntakeLog).where(IntakeLog.owner_id == owner_id, IntakeLog.taken_at >= start).order_by(IntakeLog.taken_at.desc())).all()
    return [_intake_read(log).model_dump(mode="json") for log in logs]


@router.get("/logs/history/{elder_id}")
def logs_history(elder_id: int, days: int = Query(default=7, ge=1, le=365), user: User = Depends(get_current_user), session: Session = Depends(get_session)):
    owner_id = _owner_for_request(session, user, elder_id)
    start = datetime.combine(date.today() - timedelta(days=days - 1), time.min)
    logs = session.exec(select(IntakeLog).where(IntakeLog.owner_id == owner_id, IntakeLog.taken_at >= start).order_by(IntakeLog.taken_at.desc())).all()
    return [_intake_read(log).model_dump(mode="json") for log in logs]


@router.post("/logs/confirm")
def logs_confirm(payload: LogConfirmRequest, user: User = Depends(get_current_user), session: Session = Depends(get_session)):
    log, message = _confirm_schedule(payload.schedule_id, payload.confirm_method, user, session)
    return {"success": True, "message": message, "log": _intake_read(log).model_dump(mode="json")}


@router.post("/voice/transcribe")
async def transcribe_voice(
    audio: UploadFile = File(...),
    user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
):

    owner_id = _owner_for_request(session, user, None)
    medicines = session.exec(select(Medicine).where(Medicine.owner_id == owner_id).order_by(Medicine.name)).all()
    medicine_names = [medicine.name for medicine in medicines if medicine.name][:30]
    initial_prompt = (
        "家庭用药咨询。常见药品名称：" + "、".join(medicine_names)
        if medicine_names
        else "家庭用药咨询"
    )
    settings = get_settings()
    max_bytes = settings.asr_max_upload_mb * 1024 * 1024
    suffix = Path(audio.filename or "").suffix.lower()
    if suffix not in {".m4a", ".mp4", ".aac", ".wav", ".mp3", ".ogg", ".webm"}:
        suffix = ".m4a"

    temp_path: Path | None = None
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as temp_file:
            temp_path = Path(temp_file.name)
            total = 0
            while chunk := await audio.read(1024 * 1024):
                total += len(chunk)
                if total > max_bytes:
                    raise HTTPException(
                        status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
                        detail=f"录音文件不能超过 {settings.asr_max_upload_mb} MB",
                    )
                temp_file.write(chunk)

        text = await run_in_threadpool(transcribe_audio_file, temp_path, initial_prompt)
        return {"success": True, "text": text, "model": settings.asr_model}
    except ASRError as exc:
        raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail=str(exc)) from exc
    finally:
        await audio.close()
        if temp_path is not None:
            temp_path.unlink(missing_ok=True)

def _voice_today_reply(owner_id: int, session: Session) -> str:
    reminders = [
        reminder
        for reminder in session.exec(
            select(Reminder)
            .where(Reminder.owner_id == owner_id, Reminder.enabled.is_(True))
            .order_by(Reminder.remind_time)
        ).all()
        if _schedule_matches_day(reminder, date.today())
    ]
    items: list[str] = []
    for reminder in reminders:
        medicine = session.get(Medicine, reminder.medicine_id)
        if not medicine:
            continue
        dose = f"（{reminder.dose}）" if reminder.dose else ""
        items.append(f"{reminder.remind_time.strftime('%H:%M')} {medicine.name}{dose}")
    if not items:
        return "今天没有需要服用的药。"
    return "今天需要服用的药是：" + "；".join(items) + "。请按计划服用。"


def _voice_stock_reply(owner_id: int, session: Session) -> str:
    medicines = session.exec(
        select(Medicine).where(Medicine.owner_id == owner_id).order_by(Medicine.stock_count, Medicine.name)
    ).all()
    if not medicines:
        return "药箱里还没有药品。"
    stock = "；".join(f"{medicine.name}剩余{medicine.stock_count}" for medicine in medicines)
    low = [medicine.name for medicine in medicines if medicine.stock_count <= medicine.low_stock_threshold]
    reply = f"当前库存：{stock}。"
    if low:
        reply += "库存偏少的有：" + "、".join(low) + "，请及时补充。"
    else:
        reply += "目前库存都还充足。"
    return reply


def _voice_expiry_reply(owner_id: int, session: Session) -> str:
    medicines = session.exec(select(Medicine).where(Medicine.owner_id == owner_id)).all()
    today = date.today()
    soon = today + timedelta(days=30)
    expired = [medicine.name for medicine in medicines if medicine.expire_date and medicine.expire_date < today]
    expiring = [
        medicine.name
        for medicine in medicines
        if medicine.expire_date and today <= medicine.expire_date <= soon
    ]
    parts: list[str] = []
    if expired:
        parts.append("已经过期的药有：" + "、".join(expired))
    if expiring:
        parts.append("30天内将要过期的药有：" + "、".join(expiring))
    if not parts:
        return "没有已经过期或30天内将要过期的药。"
    return "；".join(parts) + "。请及时处理。"


def _voice_medicine_names(medicine: Medicine) -> list[str]:
    names = [medicine.name]
    if medicine.alias:
        names.extend(part.strip() for part in re.split(r"[,，、/]+", medicine.alias) if part.strip())
    return names


def _voice_match_reminders(text: str, reminders: list[Reminder], session: Session) -> list[Reminder]:
    gui_fan_hua_wen_ben = gui_fan_hua_yu_yin_wen_ben(text)
    matches: list[Reminder] = []
    for reminder in reminders:
        medicine = session.get(Medicine, reminder.medicine_id)
        if not medicine:
            continue
        for name in _voice_medicine_names(medicine):
            normalized_name = gui_fan_hua_yu_yin_wen_ben(name)
            if len(normalized_name) >= 2 and normalized_name in gui_fan_hua_wen_ben:
                matches.append(reminder)
                break
    return matches


def _voice_confirm_taken(
    payload: VoiceIntentRequest,
    owner_id: int,
    user: User,
    session: Session,
) -> dict:
    reminders = [
        reminder
        for reminder in session.exec(
            select(Reminder)
            .where(Reminder.owner_id == owner_id, Reminder.enabled.is_(True))
            .order_by(Reminder.remind_time)
        ).all()
        if _schedule_matches_day(reminder, date.today())
    ]
    if not reminders:
        reply = "现在没有需要确认的服药计划。"
        return {"success": False, "intent": VoiceIntent.confirm_taken.value, "message": reply, "reply": reply}

    selected: Reminder | None = None
    if payload.schedule_id is not None:
        selected = next((item for item in reminders if item.id == payload.schedule_id), None)
        if selected is None:
            reply = "没有找到这条用药计划，请重新打开提醒后再确认。"
            return {"success": False, "intent": VoiceIntent.confirm_taken.value, "message": reply, "reply": reply}
    else:
        matches = _voice_match_reminders(payload.text, reminders, session)
        if len(matches) == 1:
            selected = matches[0]
        elif len(matches) > 1:
            names = []
            for reminder in matches:
                medicine = session.get(Medicine, reminder.medicine_id)
                if medicine:
                    names.append(medicine.name)
            reply = "匹配到多种药：" + "、".join(dict.fromkeys(names)) + "。请说清药品名称后再确认。"
            return {"success": False, "intent": VoiceIntent.confirm_taken.value, "message": reply, "reply": reply}
        elif len(reminders) == 1:
            selected = reminders[0]
        else:
            reply = "你今天有多个用药计划，请说清药品名称后再确认，避免记错。"
            return {"success": False, "intent": VoiceIntent.confirm_taken.value, "message": reply, "reply": reply}

    log, message = _confirm_schedule(selected.id or 0, "voice", user, session)
    return {
        "success": True,
        "intent": VoiceIntent.confirm_taken.value,
        "message": message,
        "reply": message,
        "schedule_id": selected.id,
        "log": _intake_read(log).model_dump(mode="json"),
    }


def _voice_intent(payload: VoiceIntentRequest, user: User, session: Session) -> dict:
    owner_id = _owner_for_request(session, user, None)
    intent = shi_bie_yu_yin_yi_tu(payload.text, payload.schedule_id)
    if intent == VoiceIntent.today_medicine:
        reply = _voice_today_reply(owner_id, session)
        return {"success": True, "intent": intent.value, "message": reply, "reply": reply}
    if intent == VoiceIntent.stock_check:
        reply = _voice_stock_reply(owner_id, session)
        return {"success": True, "intent": intent.value, "message": reply, "reply": reply}
    if intent == VoiceIntent.expiry_check:
        reply = _voice_expiry_reply(owner_id, session)
        return {"success": True, "intent": intent.value, "message": reply, "reply": reply}
    if intent == VoiceIntent.confirm_taken:
        return _voice_confirm_taken(payload, owner_id, user, session)

    reply = "我可以查询今天吃什么药、药品库存和有效期，也可以在你说清药品后确认服药。"
    return {"success": False, "intent": VoiceIntent.unknown.value, "message": reply, "reply": reply}

@router.post("/logs/voice-intent")
def logs_voice_intent(payload: VoiceIntentRequest, user: User = Depends(get_current_user), session: Session = Depends(get_session)):
    return _voice_intent(payload, user, session)


@router.post("/speaker/intent")
def speaker_intent(payload: VoiceIntentRequest, user: User = Depends(get_current_user), session: Session = Depends(get_session)):
    return _voice_intent(payload, user, session)
