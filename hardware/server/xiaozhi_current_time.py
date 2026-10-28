from datetime import datetime
from zoneinfo import ZoneInfo

CHINA_TZ = ZoneInfo("Asia/Shanghai")


def spoken_clock(now: datetime) -> str:
    hour = now.hour
    if hour < 6:
        period = "凌晨"
    elif hour < 12:
        period = "早上"
    elif hour < 14:
        period = "中午"
    elif hour < 18:
        period = "下午"
    else:
        period = "晚上"
    hour_text = str(hour if hour <= 12 else hour - 12)
    minute_text = "" if now.minute == 0 else f"{now.minute}分"
    return f"{period}{hour_text}点{minute_text}"


def current_time_reply() -> str:
    now = datetime.now(ZoneInfo("Asia/Shanghai"))
    return f"现在是{spoken_clock(now)}。"

def is_identity_question(text: str) -> bool:
    normalized = (text or "").strip()
    for char in "，,。.!！？?；;：:、 ":
        normalized = normalized.replace(char, "")
    for prefix in ("我说", "我问", "问一下", "请问"):
        if normalized.startswith(prefix):
            normalized = normalized[len(prefix):]
    return normalized in {
        "你是谁",
        "你是谁呀",
        "你是谁啊",
        "你是什么",
        "你是什么东西",
        "你是干什么的",
    }

def identity_reply() -> str:
    return "我是智能药箱的语音助手，可以帮您查用药计划。"

def is_current_time_question(text: str) -> bool:
    normalized = (text or "").strip()
    for char in "，,。.!！？?；;：:、 ":
        normalized = normalized.replace(char, "")
    if normalized.endswith("吗") or normalized.endswith("呢"):
        normalized = normalized[:-1]
    return normalized in {
        "现在几点",
        "当前时间",
        "现在时间",
        "现在几点了",
        "现在是什么时候",
        "现在什么时候",
        "北京时间现在几点",
        "现在北京时间几点",
    }
