from datetime import datetime
from zoneinfo import ZoneInfo

from plugins_func.register import (
    Action,
    ActionResponse,
    ToolType,
    register_function,
)

CHINA_TZ = ZoneInfo("Asia/Shanghai")

GET_CURRENT_TIME_DESC = {
    "type": "function",
    "function": {
        "name": "get_current_time",
        "description": (
            "查询中国标准时间（北京时间）的当前时间。"
            "用户问“现在几点”“当前时间”“现在是什么时候”时必须调用此工具，"
            "严禁根据对话上下文、模型知识或设备时间自行推算。"
        ),
        "parameters": {"type": "object", "properties": {}, "required": []},
    },
}


def _spoken_clock(now: datetime) -> str:
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


@register_function("get_current_time", GET_CURRENT_TIME_DESC, ToolType.WAIT)
def get_current_time():
    now = datetime.now(ZoneInfo("Asia/Shanghai"))
    speech = f"现在是{_spoken_clock(now)}。"
    return ActionResponse(
        action=Action.RESPONSE,
        result=speech,
        response=speech,
    )

