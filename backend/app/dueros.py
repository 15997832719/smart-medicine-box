from datetime import date, datetime, timedelta
import logging
import re
import time
from typing import Any, Callable

from fastapi import APIRouter, Depends
from sqlmodel import Session, select

from app.config import get_settings
from app.database import get_session
from app.models import AuditLog, IntakeLog, Medicine, Reminder, User, UserRole, SpeakerBinding
from app.voice_intents import VoiceIntent, shi_bie_yu_yin_yi_tu

router = APIRouter()
logger = logging.getLogger(__name__)

FALLBACK_REPROMPT = "你还可以问我今天吃什么药，或者药品库存。"
FALLBACK_TEXT = "我只能处理家庭用药问题。你可以问今天吃什么药、药品库存、有效期，或者确认服药。"


def skill_response(
    text: str,
    end_session: bool = False,
    *,
    reprompt: str | None = None,
    session_attributes: dict[str, Any] | None = None,
) -> dict[str, Any]:
    response: dict[str, Any] = {
        "outputSpeech": {"type": "PlainText", "text": text},
        "card": {"type": "txt", "content": text},
        "shouldEndSession": end_session,
    }
    if not end_session:
        response["reprompt"] = {
            "outputSpeech": {
                "type": "PlainText",
                "text": reprompt or FALLBACK_REPROMPT,
            }
        }
    return {
        "version": "2.0",
        "sessionAttributes": session_attributes or {},
        "response": response,
    }


def request_identifier(payload: dict[str, Any]) -> str:
    request = payload.get("request") or {}
    for source in (request, payload):
        if isinstance(source, dict):
            for key in ("requestId", "request_id"):
                value = source.get(key)
                if value is not None and str(value).strip():
                    return str(value).strip()
    return "unknown"


def session_identifier(payload: dict[str, Any]) -> str:
    session = payload.get("session") or {}
    if isinstance(session, dict):
        for key in ("sessionId", "session_id"):
            value = session.get(key)
            if value is not None and str(value).strip():
                return str(value).strip()
    return "unknown"


def platform_intent_name(payload: dict[str, Any]) -> str | None:
    request = payload.get("request") or {}
    intent = request.get("intent") if isinstance(request, dict) else None
    if isinstance(intent, dict):
        value = intent.get("name")
        if value is not None and str(value).strip():
            return str(value).strip()
    return None


def request_text(payload: dict[str, Any]) -> str:
    request = payload.get("request") or {}
    intent = request.get("intent") or {}
    values: list[str] = []
    for source in (payload, request, payload.get("query") or {}):
        if isinstance(source, dict):
            for key in ("query", "text", "utterance", "original", "originalText", "originalQuery"):
                if isinstance(source.get(key), str):
                    values.append(source[key])
    slots = intent.get("slots") or {}
    if isinstance(slots, dict):
        for slot in slots.values():
            if isinstance(slot, str):
                values.append(slot)
            elif isinstance(slot, dict):
                for key in ("value", "originalValue", "rawValue"):
                    if isinstance(slot.get(key), str):
                        values.append(slot[key])
    return " ".join(values)


def find_medicine(payload: dict[str, Any], medicines: list[Medicine]) -> Medicine | None:
    text = request_text(payload).lower()
    for medicine in medicines:
        names = [medicine.name]
        if medicine.alias:
            names.extend(part.strip() for part in medicine.alias.split(","))
        if any(name and name.lower() in text for name in names):
            return medicine
    return None


def dueros_owner_id(payload: dict[str, Any], session: Session) -> int | None:

    candidates: list[Any] = []
    session_data = payload.get("session") or {}
    attributes = payload.get("sessionAttributes") or {}
    request = payload.get("request") or {}
    context = payload.get("context") or {}
    sources = (payload, session_data, attributes, request, context, session_data.get("user") if isinstance(session_data, dict) else {}, context.get("user") if isinstance(context, dict) else {}, context.get("device") if isinstance(context, dict) else {})
    for source in sources:
        if isinstance(source, dict):
            candidates.extend([source.get("user_id"), source.get("userId"), source.get("elder_id"), source.get("elderId")])
    for candidate in candidates:
        try:
            user_id = int(candidate)
        except (TypeError, ValueError):
            continue
        user = session.get(User, user_id)
        if user and user.role == UserRole.elder:
            return user.id
    configured = get_settings().dueros_user_id
    if configured:
        user = session.get(User, configured)
        if user and user.role == UserRole.elder:
            return user.id


    return None

def pairing_code_in_text(text: str) -> str | None:

    digits = re.findall(r"\d{6}", re.sub(r"[\s\-]", "", text or ""))
    return digits[0] if digits else None


def bind_speaker_by_code(session: Session, speaker_id: str | None, code: str) -> int | None:

    if not speaker_id:
        return None
    binding = session.exec(select(SpeakerBinding).where(SpeakerBinding.pairing_code == code)).first()
    if not binding or not binding.code_expires_at or binding.code_expires_at < datetime.utcnow():
        return None
    existing = session.exec(select(SpeakerBinding).where(SpeakerBinding.speaker_id == speaker_id)).first()
    if existing and existing.id != binding.id:
        session.delete(existing)
        session.flush()
    binding.speaker_id = speaker_id
    binding.pairing_code = None
    binding.code_expires_at = None
    session.add(binding)
    session.commit()
    return binding.user_id



INTENT_ALIASES: dict[str, str] = {
    "todaymedicine": "TodayMedicineIntent",
    "todaymedicines": "TodayMedicineIntent",
    "todaydrugs": "TodayMedicineIntent",
    "whatmedicine": "TodayMedicineIntent",
    "askmedicine": "TodayMedicineIntent",
    "查询用药": "TodayMedicineIntent",
    "今天吃什么药": "TodayMedicineIntent",
    "今日用药": "TodayMedicineIntent",
    "查药": "TodayMedicineIntent",
    "用药提醒": "TodayMedicineIntent",
    "confirmtaken": "ConfirmTakenIntent",
    "confirmmedicine": "ConfirmTakenIntent",
    "takemedicine": "ConfirmTakenIntent",
    "确认服药": "ConfirmTakenIntent",
    "吃过药了": "ConfirmTakenIntent",
    "medicineinfo": "MedicineInfoIntent",
    "druginfo": "MedicineInfoIntent",
    "medicineinformation": "MedicineInfoIntent",
    "怎么吃": "MedicineInfoIntent",
    "说明书": "MedicineInfoIntent",
    "stockcheck": "StockCheckIntent",
    "stock": "StockCheckIntent",
    "inventory": "StockCheckIntent",
    "库存": "StockCheckIntent",
    "expirycheck": "ExpiryCheckIntent",
    "expiry": "ExpiryCheckIntent",
    "过期": "ExpiryCheckIntent",
    "dueros.unknown": "FallbackIntent",
    "system.unknown": "FallbackIntent",
    "dueros.fallback": "FallbackIntent",
    "system.fallback": "FallbackIntent",
    "dueroschitchat": "FallbackIntent",
    "systemchitchat": "FallbackIntent",
    "fallback": "FallbackIntent",
    "medicinefallback": "FallbackIntent",
    "medicineunknown": "FallbackIntent",
    "unknown": "FallbackIntent",
    "chitchat": "FallbackIntent",
    "兜底": "FallbackIntent",
    "未知": "FallbackIntent",
}

def resolve_intent_name(name: str | None) -> str | None:

    if not name:
        return None
    gui_fan_hua_wen_ben = re.sub(r"[\s_\-]", "", name.strip().lower())
    if gui_fan_hua_wen_ben.endswith("intent"):
        gui_fan_hua_wen_ben = gui_fan_hua_wen_ben[: -len("intent")]
    return INTENT_ALIASES.get(gui_fan_hua_wen_ben)


def speaker_identity(payload: dict[str, Any]) -> str | None:
    session = payload.get("session") or {}; context = payload.get("context") or {}
    for source in (payload, session, payload.get("request") or {}, context, session.get("user") if isinstance(session, dict) else {}, context.get("user") if isinstance(context, dict) else {}, context.get("device") if isinstance(context, dict) else {}):
        if isinstance(source, dict):
            for key in ("deviceId", "device_id", "userId", "user_id"):
                value = source.get(key)
                if value is not None and str(value).strip(): return str(value).strip()
    return None


def today_medicine(session: Session, owner_id: int | None = None) -> str:
    query = select(Reminder).where(Reminder.enabled.is_(True)).order_by(Reminder.remind_time)
    if owner_id is not None:
        query = query.where(Reminder.owner_id == owner_id)
    reminders = [reminder for reminder in session.exec(query).all() if reminder.schedule_date is None or reminder.schedule_date == date.today()]
    items: list[tuple[Reminder, Medicine]] = []
    for reminder in reminders:
        medicine = session.get(Medicine, reminder.medicine_id)
        if medicine:
            items.append((reminder, medicine))
    if not items:
        return "今天没有需要吃的药。"
    if len(items) == 1:
        reminder, medicine = items[0]
        dose = f"，{reminder.dose}" if reminder.dose else ""
        return f"今天只有一项用药：{reminder.remind_time.strftime('%H:%M')}服用{medicine.name}{dose}。"
    now = datetime.now().time()
    upcoming = [(reminder, medicine) for reminder, medicine in items if reminder.remind_time >= now]
    if not upcoming:
        reminder, medicine = items[-1]
        dose = f"，{reminder.dose}" if reminder.dose else ""
        return (
            f"今天有{len(items)}项用药，计划时间都已经过了。最后一项是"
            f"{reminder.remind_time.strftime('%H:%M')}服用{medicine.name}{dose}。"
            f"详情请在智能药箱 App 查看。"
        )
    reminder, medicine = upcoming[0]
    dose = f"，{reminder.dose}" if reminder.dose else ""
    return f"今天有{len(items)}项用药。下一项是{reminder.remind_time.strftime('%H:%M')}服用{medicine.name}{dose}。详情请在 App 查看。"


def confirm_taken(payload: dict[str, Any], session: Session, owner_id: int | None = None) -> str:
    query = select(Reminder).where(Reminder.enabled.is_(True)).order_by(Reminder.remind_time)
    if owner_id is not None:
        query = query.where(Reminder.owner_id == owner_id)
    reminders = [
        reminder
        for reminder in session.exec(query).all()
        if reminder.schedule_date is None or reminder.schedule_date == date.today()
    ]
    if not reminders:
        return "现在没有需要确认的服药计划。"

    medicines = [session.get(Medicine, reminder.medicine_id) for reminder in reminders]
    medicines = [medicine for medicine in medicines if medicine is not None]
    mentioned = find_medicine(payload, medicines)
    if mentioned is None:
        return "请问您刚才吃的是哪种药？请说药名。"
    reminder = next((item for item in reminders if item.medicine_id == mentioned.id), None)

    if reminder is None:
        return "没有找到这个药品对应的今日用药计划。"
    medicine = session.get(Medicine, reminder.medicine_id)
    if not medicine:
        return "这条用药计划对应的药品找不到了。"
    now = datetime.now()
    start = datetime.combine(date.today(), datetime.min.time())
    existing_query = select(IntakeLog).where(
        IntakeLog.medicine_id == medicine.id,
        IntakeLog.taken_at >= start,
    )
    if owner_id is not None:
        existing_query = existing_query.where(IntakeLog.owner_id == owner_id)
    existing = session.exec(existing_query).first()
    if existing:
        return f"今天 {medicine.name} 已经记过了。"

    log = IntakeLog(
        owner_id=owner_id or reminder.owner_id,
        medicine_id=medicine.id or 0,
        dose=reminder.dose,
        note="通过 DuerOS 确认服药",
        taken_at=now,
    )
    session.add(log)
    session.flush()
    session.add(
        AuditLog(
            user_id=owner_id or reminder.owner_id,
            action="confirm",
            resource_type="intake_log",
            resource_id=log.id,
            detail=f"owner_id={owner_id or reminder.owner_id};actor_user_id={owner_id or reminder.owner_id};method=dueros",
        )
    )
    if medicine.stock_count > 0:
        medicine.stock_count -= 1
        medicine.updated_at = now
        session.add(medicine)
    session.commit()
    dose = f" {reminder.dose}" if reminder.dose else ""
    return f"好的，已经记下你吃过 {medicine.name}{dose}。"


def medicine_info(payload: dict[str, Any], session: Session, owner_id: int | None = None) -> str:
    query = select(Medicine).order_by(Medicine.name)
    if owner_id is not None:
        query = query.where(Medicine.owner_id == owner_id)
    medicines = session.exec(query).all()
    medicine = find_medicine(payload, medicines)
    if not medicine:
        names = "、".join(item.name for item in medicines[:5])
        return "请说一下药品名字。" + (f"现在有：{names}。" if names else "")
    parts = [medicine.name]
    if medicine.description:
        parts.append(medicine.description.rstrip("。"))
    if medicine.dosage:
        parts.append(f"用法：{medicine.dosage.rstrip('。')}")
    if medicine.precautions:
        parts.append(f"注意：{medicine.precautions.rstrip('。')}")
    parts.append("具体请以药品说明书和医生指导为准")
    return "。".join(parts) + "。"


def expiry_check(session: Session, owner_id: int | None = None) -> str:
    today = date.today()
    soon = today + timedelta(days=30)
    query = select(Medicine).order_by(Medicine.expire_date)
    if owner_id is not None:
        query = query.where(Medicine.owner_id == owner_id)
    medicines = session.exec(query).all()
    expired = [item for item in medicines if item.expire_date and item.expire_date < today]
    expiring = [item for item in medicines if item.expire_date and today <= item.expire_date <= soon]
    parts: list[str] = []
    if expired:
        parts.append("已经过期的药：" + "、".join(f"{item.name}（{item.expire_date.isoformat()}）" for item in expired))
    if expiring:
        parts.append("30 天内要过期的药：" + "、".join(f"{item.name}（{item.expire_date.isoformat()}）" for item in expiring))
    if not parts:
        return "没有过期或者快过期的药。"
    return "。".join(parts) + "。"


def stock_check(session: Session, owner_id: int | None = None) -> str:
    query = select(Medicine).order_by(Medicine.stock_count, Medicine.name)
    if owner_id is not None:
        query = query.where(Medicine.owner_id == owner_id)
    medicines = session.exec(query).all()
    if not medicines:
        return "药箱里还没有药品。"
    stock = "，".join(f"{item.name}剩 {item.stock_count} 片" for item in medicines)
    low = [item.name for item in medicines if item.stock_count <= item.low_stock_threshold]
    if low:
        return f"现在的库存是：{stock}。快吃完的是：{'、'.join(low)}。"
    return f"现在的库存是：{stock}。其他药品的库存都还够。"

@router.post("/dueros/skill")
def dueros_skill(payload: dict[str, Any], session: Session = Depends(get_session)) -> dict[str, Any]:
    started_at = time.perf_counter()
    request = payload.get("request") or {}
    text = request_text(payload).strip()
    request_type = request.get("type") if isinstance(request, dict) else None
    request_id = request_identifier(payload)
    session_id = session_identifier(payload)
    platform_intent = platform_intent_name(payload)
    final_intent = "UnknownIntent"
    reply_source = "rule"
    owner_id: int | None = None
    speaker_id: str | None = None

    try:
        if request_type == "LaunchRequest" and not text:
            final_intent = "LaunchRequest"
            reply_source = "system"
            return skill_response(
                "欢迎使用智能药箱。你可以问我今天吃什么药。",
                reprompt="你可以问我今天吃什么药，或者药品库存。",
                session_attributes={"request_id": request_id},
            )
        if request_type == "SessionEndedRequest":
            final_intent = "SessionEndedRequest"
            reply_source = "system"
            return skill_response("再见。", end_session=True)

        speaker_id = speaker_identity(payload)
        owner_id = dueros_owner_id(payload, session)
        if speaker_id:
            binding = session.exec(select(SpeakerBinding).where(SpeakerBinding.speaker_id == speaker_id)).first()
            if binding:
                owner_id = binding.user_id

        code = pairing_code_in_text(text)
        if code:
            if bind_speaker_by_code(session, speaker_id, code) is not None:
                final_intent = "PairingIntent"
                reply_source = "binding"
                return skill_response("绑定成功，以后你可以直接问我今天吃什么药。")
            return skill_response("这个配对码不对或者已经过期了，请在手机 App 的我的-音箱接入里重新生成一个。")

        if owner_id is None:
            final_intent = "BindingRequiredIntent"
            reply_source = "rule"
            return skill_response("这台音箱还没有绑定账号。请打开智能药箱 App，点我的，再点音箱接入，生成配对码后对我说：配对码 加上那 6 个数字。")

        intent_name = resolve_intent_name(platform_intent)
        if not intent_name:
            inferred = shi_bie_yu_yin_yi_tu(text)
            if inferred == VoiceIntent.today_medicine:
                intent_name = "TodayMedicineIntent"
            elif inferred == VoiceIntent.confirm_taken:
                intent_name = "ConfirmTakenIntent"
            elif inferred == VoiceIntent.stock_check:
                intent_name = "StockCheckIntent"
            elif inferred == VoiceIntent.expiry_check:
                intent_name = "ExpiryCheckIntent"
            elif any(word in text for word in ("怎么吃", "说明书", "注意事项")):
                intent_name = "MedicineInfoIntent"

        final_intent = intent_name or "FallbackIntent"
        if intent_name == "TodayMedicineIntent":
            reply_source = "database"
            return skill_response(today_medicine(session, owner_id))
        if intent_name == "ConfirmTakenIntent":
            reply_source = "database"
            return skill_response(
                confirm_taken(payload, session, owner_id),
                reprompt="如果音箱听错药名，请说取消。",
            )
        if intent_name == "MedicineInfoIntent":
            reply_source = "database"
            return skill_response(medicine_info(payload, session, owner_id))
        if intent_name == "StockCheckIntent":
            reply_source = "database"
            return skill_response(stock_check(session, owner_id))
        if intent_name == "ExpiryCheckIntent":
            reply_source = "database"
            return skill_response(expiry_check(session, owner_id))
        return skill_response(FALLBACK_TEXT)
    finally:
        logger.info(
            "dueros_skill_request",
            extra={
                "request_id": request_id,
                "session_id": session_id,
                "request_type": request_type,
                "raw_text": text,
                "platform_intent": platform_intent,
                "final_intent": final_intent,
                "reply_source": reply_source,
                "speaker_id": speaker_id,
                "owner_id": owner_id,
                "elapsed_ms": round((time.perf_counter() - started_at) * 1000, 2),
            },
        )
