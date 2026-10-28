from __future__ import annotations

import re
import threading
import time
from dataclasses import dataclass
from difflib import SequenceMatcher
from typing import Any

from app.models import Medicine, Reminder
from app.voice_intents import gui_fan_hua_yu_yin_wen_ben

VOICE_CONTEXT_TTL_SECONDS = 300
_VOICE_CONTEXT: dict[tuple[int, str], dict[str, Any]] = {}
_VOICE_CONTEXT_LOCK = threading.Lock()

_HIGH_RISK_PATTERNS = (
    r"诊断",
    r"确诊",
    r"换药",
    r"停药",
    r"加量",
    r"减量",
    r"剂量调整",
    r"能不能一起吃",
    r"能否一起吃",
    r"孕妇",
    r"哺乳",
    r"儿童",
    r"过量",
    r"中毒",
    r"胸痛",
    r"呼吸困难",
    r"昏迷",
    r"急救",
    r"急诊",
)
_CONFIRM_WORDS = {"确认", "确定", "是的", "对", "没错", "可以", "执行"}
_CANCEL_WORDS = {"取消", "不用", "不要", "否", "算了"}


@dataclass(frozen=True)
class MedicineMatch:
    medicine_id: int | None
    name: str | None
    confidence: float
    corrected_text: str


def _normalize(value: str) -> str:
    return re.sub(r"[\s,，。；;：:、/]+", "", gui_fan_hua_yu_yin_wen_ben(value))


def _aliases(medicine: Medicine) -> list[str]:
    result = [medicine.name]
    if medicine.alias:
        result.extend(item.strip() for item in re.split(r"[,，、/]+", medicine.alias) if item.strip())
    return [item for item in result if item]


def match_medicine(text: str, medicines: list[Medicine]) -> MedicineMatch:
    normalized_text = _normalize(text)
    best: tuple[float, Medicine, str] | None = None
    for medicine in medicines:
        for alias in _aliases(medicine):
            normalized_alias = _normalize(alias)
            if len(normalized_alias) < 2:
                continue
            if normalized_alias in normalized_text:
                return MedicineMatch(medicine.id, medicine.name, 0.98, text.replace(alias, medicine.name))
            max_ratio = 0.0
            min_size = max(2, len(normalized_alias) - 1)
            max_size = min(len(normalized_text), len(normalized_alias) + 1)
            for size in range(min_size, max_size + 1):
                for start in range(0, len(normalized_text) - size + 1):
                    ratio = SequenceMatcher(None, normalized_alias, normalized_text[start:start + size]).ratio()
                    if ratio > max_ratio:
                        max_ratio = ratio
            if best is None or max_ratio > best[0]:
                best = (max_ratio, medicine, alias)
    if best is not None and best[0] >= 0.72:
        return MedicineMatch(best[1].id, best[1].name, round(best[0], 2), text)
    return MedicineMatch(None, None, 0.0, text)


def high_risk_reply(text: str) -> str | None:
    normalized = _normalize(text)
    if any(re.search(pattern, normalized) for pattern in _HIGH_RISK_PATTERNS):
        return "这个问题涉及诊断、换药、剂量调整或特殊人群用药，我不能直接判断。请咨询医生或药师；如有胸痛、呼吸困难等急症，请立即就医。"
    return None


def is_confirmation(text: str) -> bool:
    normalized = _normalize(text)
    return normalized in _CONFIRM_WORDS or any(normalized == word for word in _CONFIRM_WORDS)


def is_cancellation(text: str) -> bool:
    normalized = _normalize(text)
    return normalized in _CANCEL_WORDS or any(normalized == word for word in _CANCEL_WORDS)


def get_context(user_id: int, session_id: str | None) -> dict[str, Any]:
    key = (user_id, session_id or "default")
    now = time.monotonic()
    with _VOICE_CONTEXT_LOCK:
        expired = [item for item, value in _VOICE_CONTEXT.items() if value.get("expires_at", 0) <= now]
        for item in expired:
            _VOICE_CONTEXT.pop(item, None)
        value = dict(_VOICE_CONTEXT.get(key, {}))
    value["expires_at"] = value.get("expires_at", now + VOICE_CONTEXT_TTL_SECONDS)
    return value


def save_context(user_id: int, session_id: str | None, **updates: Any) -> dict[str, Any]:
    key = (user_id, session_id or "default")
    value = get_context(user_id, session_id)
    value.update(updates)
    value["expires_at"] = time.monotonic() + VOICE_CONTEXT_TTL_SECONDS
    with _VOICE_CONTEXT_LOCK:
        _VOICE_CONTEXT[key] = dict(value)
    return value


def clear_context(user_id: int, session_id: str | None) -> None:
    key = (user_id, session_id or "default")
    with _VOICE_CONTEXT_LOCK:
        _VOICE_CONTEXT.pop(key, None)


def sanitize_speak_text(text: str) -> str:
    value = text or ""
    value = re.sub(r"```.*?```|~~~.*?~~~", " ", value, flags=re.DOTALL)
    value = re.sub(r"!\[[^\]]*\]\([^)]+\)", " ", value)
    value = re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", value)
    value = re.sub(r"https?://\S+|www\.\S+", " ", value, flags=re.IGNORECASE)
    value = re.sub(r"<[^>]+>", " ", value)
    value = re.sub(r"(?m)^\s{0,3}#{1,6}\s*", "", value)
    value = re.sub(r"(?m)^\s*(?:[-*+]|\d+[.?])\s+", "", value)
    value = re.sub(r"(?m)^\s*>\s?", "", value)
    value = value.replace("|", "，")
    value = re.sub(r"(?m)^\s*:?-{3,}:?\s*$", " ", value)
    value = re.sub(r"[`*_~]", "", value)
    value = re.sub(
        r"[🇠-🇿🌀-🫿☀-➿]+",
        " ",
        value,
    )
    value = value.replace("\r\n", "\n").replace("\r", "\n")
    value = re.sub(r"\n+", "。", value)
    value = (
        value.replace(",", "，")
        .replace(";", "；")
        .replace(":", "：")
        .replace("!", "！")
        .replace("?", "？")
    )
    value = re.sub(r"(?<=[一-鿿])\.", "。", value)
    value = re.sub(r"\.(?=\s|$)", "。", value)
    value = re.sub(r"\s+", "", value)
    value = re.sub(r"[。！？；：，]{2,}", lambda match: match.group(0)[0], value)
    value = value.strip("。！？；：， ")
    if not value:
        return "暂时没有可播报的内容。"
    if value[-1] not in "。！？":
        value += "。"
    return value


def medicine_facts(medicine: Medicine) -> str:
    parts = [f"药品名称：{medicine.name}"]
    if medicine.alias:
        parts.append(f"别名：{medicine.alias}")
    if medicine.dosage:
        parts.append(f"用法用量：{medicine.dosage}")
    if medicine.precautions:
        parts.append(f"注意事项：{medicine.precautions}")
    if medicine.description:
        parts.append(f"说明：{medicine.description}")
    parts.append(f"库存：{medicine.stock_count}")
    if medicine.expire_date:
        parts.append(f"有效期：{medicine.expire_date.isoformat()}")
    return "；".join(parts)


def schedule_facts(reminder: Reminder, medicine: Medicine | None) -> str:
    name = medicine.name if medicine else reminder.title
    date_text = reminder.schedule_date.isoformat() if reminder.schedule_date else "每天"
    dose = reminder.dose or "未填写剂量"
    return f"计划：{name}；日期：{date_text}；时间：{reminder.remind_time.strftime('%H:%M')}；剂量：{dose}"


def reply_payload(
    intent: str,
    reply: str,
    *,
    source: str = "rule",
    confidence: float = 1.0,
    needs_confirmation: bool = False,
    needs_medicine: bool = False,
    medicine_id: int | None = None,
    schedule_id: int | None = None,
    session_id: str | None = None,
    corrected_text: str | None = None,
    success: bool = True,
) -> dict[str, Any]:
    display_text = reply
    return {
        "success": success,
        "intent": intent,
        "message": display_text,
        "reply": display_text,
        "display_text": display_text,
        "speak_text": sanitize_speak_text(display_text),
        "source": source,
        "confidence": confidence,
        "needs_confirmation": needs_confirmation,
        "needs_medicine": needs_medicine,
        "medicine_id": medicine_id,
        "schedule_id": schedule_id,
        "session_id": session_id,
        "corrected_text": corrected_text,
    }
