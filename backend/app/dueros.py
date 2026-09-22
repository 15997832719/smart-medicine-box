from datetime import date, datetime, timedelta
import re
from typing import Any, Callable

from fastapi import APIRouter, Depends
from sqlmodel import Session, select

from app.config import get_settings
from app.database import get_session
from app.models import IntakeLog, Medicine, Reminder, User, UserRole, SpeakerBinding
from app.voice_intents import VoiceIntent, shi_bie_yu_yin_yi_tu

router = APIRouter()


def skill_response(text: str, end_session: bool = False) -> dict[str, Any]:
    return {
        "version": "2.0",
        "sessionAttributes": {},
        "response": {
            "outputSpeech": {"type": "PlainText", "text": text},
            "card": {"type": "txt", "content": text},
            "shouldEndSession": end_session,
        },
    }


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
    items: list[str] = []
    for reminder in reminders:
        medicine = session.get(Medicine, reminder.medicine_id)
        if medicine:
            dose = f" {reminder.dose}" if reminder.dose else ""
            items.append(f"{reminder.remind_time.strftime('%H:%M')} {medicine.name}{dose}")
    if not items:
        return "今天没有需要吃的药。"
    return "今天要吃的是：" + "，".join(items) + "。"


def confirm_taken(session: Session, owner_id: int | None = None) -> str:
    query = select(Reminder).where(Reminder.enabled.is_(True)).order_by(Reminder.remind_time)
    if owner_id is not None:
        query = query.where(Reminder.owner_id == owner_id)
    reminders = [reminder for reminder in session.exec(query).all() if reminder.schedule_date is None or reminder.schedule_date == date.today()]
    if not reminders:
        return "现在没有需要确认的服药计划。"
    now = datetime.now()
    reminder = min(reminders, key=lambda item: abs(datetime.combine(now.date(), item.remind_time).timestamp() - now.timestamp()))
    medicine = session.get(Medicine, reminder.medicine_id)
    if not medicine:
        return "这条用药计划对应的药品找不到了。"
    start = datetime.combine(date.today(), datetime.min.time())
    existing_query = select(IntakeLog).where(IntakeLog.medicine_id == medicine.id).where(IntakeLog.taken_at >= start)
    if owner_id is not None:
        existing_query = existing_query.where(IntakeLog.owner_id == owner_id)
    existing = session.exec(existing_query).first()
    if existing:
        return f"今天 {medicine.name} 已经记过了。"
    session.add(IntakeLog(owner_id=owner_id or reminder.owner_id, medicine_id=medicine.id or 0, dose=reminder.dose, note="通过 DuerOS 确认服药", taken_at=now))
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
    request = payload.get("request") or {}
    text = request_text(payload).strip()
    request_type = request.get("type")


    if request_type == "LaunchRequest" and not text:
        return skill_response("欢迎使用智能药箱。你可以问我今天吃什么药。")
    if request_type == "SessionEndedRequest":
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
            return skill_response("绑定成功，以后你可以直接问我今天吃什么药。")
        return skill_response("这个配对码不对或者已经过期了，请在手机 App 的我的-音箱接入里重新生成一个。")
    if owner_id is None:
        return skill_response("这台音箱还没有绑定账号。请打开智能药箱 App，点我的，再点音箱接入，生成配对码后对我说：配对码 加上那 6 个数字。")
    intent_name = resolve_intent_name((request.get("intent") or {}).get("name"))
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
    if intent_name == "TodayMedicineIntent":
        return skill_response(today_medicine(session, owner_id))
    if intent_name == "ConfirmTakenIntent":
        return skill_response(confirm_taken(session, owner_id))
    if intent_name == "MedicineInfoIntent":
        return skill_response(medicine_info(payload, session, owner_id))
    if intent_name == "StockCheckIntent":
        return skill_response(stock_check(session, owner_id))
    if intent_name == "ExpiryCheckIntent":
        return skill_response(expiry_check(session, owner_id))
    return skill_response("我可以查询今天吃什么药、药品用法和库存。")
