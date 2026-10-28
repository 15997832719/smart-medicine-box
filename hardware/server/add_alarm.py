import httpx
from config.logger import setup_logging
from plugins_func.register import register_function, ToolType, ActionResponse, Action
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from core.connection import ConnectionHandler

TAG = __name__
logger = setup_logging()

DESC = {
    "type": "function",
    "function": {
        "name": "add_alarm",
        "description": (
            "设置一个普通闹钟或提醒，例如“下午三点提醒我喝水”“每天七点提醒我散步”。"
            "用药提醒请改用 add_medicine_plan。时间用24小时制 HH:MM。"
        ),
        "parameters": {
            "type": "object",
            "properties": {
                "label": {"type": "string", "description": "提醒内容，例如喝水、散步"},
                "time": {"type": "string", "description": "24小时制时间，例如15:00"},
                "repeat": {"type": "string", "enum": ["once", "daily"], "description": "每天用 daily，只响一次用 once"},
            },
            "required": ["label", "time"],
        },
    },
}


@register_function("add_alarm", DESC, ToolType.SYSTEM_CTL)
async def add_alarm(
    conn: "ConnectionHandler",
    label: str,
    time: str,
    repeat: str = "once",
):
    try:
        async with httpx.AsyncClient(timeout=8) as client:
            resp = await client.post(
                "http://127.0.0.1:8013/alarm",
                params={"label": label, "time": time, "repeat": repeat, "device_id": conn.device_id},
            )
            resp.raise_for_status()
            data = resp.json()
        speech = data.get("speech") or "设置失败，请稍后再试。"
        logger.info(f"新增闹钟: {speech}")
        return ActionResponse(Action.RESPONSE, None, speech)
    except Exception as exc:
        logger.error(f"新增闹钟失败: {exc}")
        return ActionResponse(Action.RESPONSE, None, "暂时无法设置闹钟，请稍后再试。")
