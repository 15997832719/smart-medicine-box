

from __future__ import annotations

import re
from enum import Enum


class VoiceIntent(str, Enum):
    today_medicine = "today_medicine"
    stock_check = "stock_check"
    confirm_taken = "confirm_taken"
    expiry_check = "expiry_check"
    unknown = "unknown"


def gui_fan_hua_yu_yin_wen_ben(text: str) -> str:

    return re.sub(r"[\s,，。.!！?？;；:：]+", "", (text or "").strip().lower())


def _matches(text: str, patterns: tuple[str, ...]) -> bool:
    return any(re.search(pattern, text) for pattern in patterns)


TODAY_MEDICINE_PATTERNS = (
    r"(今天|今日).*(吃什么|吃哪些|该吃|要吃什么|吃啥).*药",
    r"(今天|今日).*(用药|服药|吃药).*(计划|安排|吗|么|情况)",
    r"(用药|服药|吃药)计划",
    r"(该|要|需要)(吃|服|用)什么药",
)

CONFIRM_TAKEN_PATTERNS = (
    r"(确认|记录|登记|帮我记).*(服药|服用|吃药|用药)",
    r"(我|药).*(已经|已|刚|刚刚).*(吃|服).*药",
    r"(吃|服).*(药|了).*(了|过)(?![吗呢么])",
)

STOCK_CHECK_PATTERNS = (
    r"(库存|存货|余量|存量)",
    r"(还剩|剩下|剩多少|剩几|快吃完|够不够).*(药|片|盒|瓶)",
)

EXPIRY_CHECK_PATTERNS = (
    r"(过期|有效期|保质期|到期)",
)


def shi_bie_yu_yin_yi_tu(text: str, schedule_id: int | None = None) -> VoiceIntent:

    gui_fan_hua_wen_ben = gui_fan_hua_yu_yin_wen_ben(text)
    if not gui_fan_hua_wen_ben:
        return VoiceIntent.unknown


    if _matches(gui_fan_hua_wen_ben, CONFIRM_TAKEN_PATTERNS):
        return VoiceIntent.confirm_taken
    if schedule_id is not None and _matches(gui_fan_hua_wen_ben, (r"(吃|服).*药", r"(确认|记录|登记)")):
        return VoiceIntent.confirm_taken
    if _matches(gui_fan_hua_wen_ben, STOCK_CHECK_PATTERNS):
        return VoiceIntent.stock_check
    if _matches(gui_fan_hua_wen_ben, EXPIRY_CHECK_PATTERNS):
        return VoiceIntent.expiry_check
    if _matches(gui_fan_hua_wen_ben, TODAY_MEDICINE_PATTERNS):
        return VoiceIntent.today_medicine
    return VoiceIntent.unknown
