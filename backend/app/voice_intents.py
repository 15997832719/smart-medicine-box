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
    """去掉语音文本里的空白和标点，便于做意图匹配。"""
    return re.sub(r"[\s,，。.!！?？;；:：、/]+", "", (text or "").strip().lower())


def _matches(text: str, patterns: tuple[str, ...]) -> bool:
    return any(re.search(pattern, text) for pattern in patterns)


TODAY_MEDICINE_PATTERNS = (
    r"(今天|今日).*(吃什么|吃啥|吃哪些|该吃|要吃|需要吃|服用什么|服什么).*药",
    r"(今天|今日).*(用药|服药|吃药).*(计划|安排|情况)",
    r"(用药|服药|吃药)(计划|安排)",
    r"(我)?(该|要|需要)(吃|服|用)(什么|哪些|啥)药",
)

CONFIRM_TAKEN_PATTERNS = (
    r"(确认|记录|登记|帮我记).*(吃药|服药|服用|用药)",
    r"(我|药).*(已经|已|刚|刚刚|刚才).*(吃|服|用).*药",
    r"(我)?(吃|服|用)药(了|过)(?!吗|么|没)",
    r"(我)?(吃|服|用)(了|过)药(?!吗|么|没)",
)

STOCK_CHECK_PATTERNS = (
    r"(库存|存货|余量|存量)",
    r"(药|药品|存货|库存).*(还剩|剩下|还有多少|余多少|剩多少|剩几|够不够|够吗|够用吗)",
    r"(药|药品).*(快吃完|快没了|用完了)",
    r"(还有多少|还剩|剩下|剩多少|剩几|快吃完|够不够).*(药|片|颗|粒|盒)",
)

EXPIRY_CHECK_PATTERNS = (r"(过期|有效期|保质期|到期)",)


def shi_bie_yu_yin_yi_tu(text: str, schedule_id: int | None = None) -> VoiceIntent:
    """识别家庭用药语音意图；无法确定时返回 unknown。"""
    normalized = gui_fan_hua_yu_yin_wen_ben(text)
    if not normalized:
        return VoiceIntent.unknown

    if _matches(normalized, CONFIRM_TAKEN_PATTERNS):
        return VoiceIntent.confirm_taken
    if schedule_id is not None and _matches(normalized, (r"(吃|服).*药", r"(确认|记录|登记)")):
        return VoiceIntent.confirm_taken
    if _matches(normalized, STOCK_CHECK_PATTERNS):
        return VoiceIntent.stock_check
    if _matches(normalized, EXPIRY_CHECK_PATTERNS):
        return VoiceIntent.expiry_check
    if _matches(normalized, TODAY_MEDICINE_PATTERNS):
        return VoiceIntent.today_medicine
    return VoiceIntent.unknown
