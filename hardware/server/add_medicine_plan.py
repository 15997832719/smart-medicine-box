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
        "name": "add_medicine_plan",
        "description": (
            "新增一条用药提醒计划。当用户说“每天几点提醒我吃什么药”“帮我加一个吃药提醒”时调用。"
            "必须从用户话里提取药品名和时间；没有明确药名时不要调用，先询问药名；时间用24小时制 HH:MM；剂量没提到就不传。"
        ),
        "parameters": {
            "type": "object",
            "properties": {
                "medicine": {"type": "string", "description": "用户说出的完整药品名称"},
                "time": {"type": "string", "description": "24小时制时间，例如08:00"},
                "dose": {"type": "string", "description": "剂量，例如一次一袋；没提到就不传"},
                "frequency": {"type": "string", "enum": ["daily", "once"], "description": "每天用 daily，只说一次用 once"},
            },
            "required": ["medicine", "time"],
        },
    },
}


@register_function("add_medicine_plan", DESC, ToolType.SYSTEM_CTL)
async def add_medicine_plan(
    conn: "ConnectionHandler",
    medicine: str,
    time: str,
    dose: str | None = None,
    frequency: str = "daily",
):
    params = {"medicine": medicine, "time": time, "frequency": frequency, "device_id": conn.device_id}
    if dose:
        params["dose"] = dose
    try:
        async with httpx.AsyncClient(timeout=8) as client:
            resp = await client.post("http://127.0.0.1:8013/plan", params=params)
            resp.raise_for_status()
            data = resp.json()
        speech = data.get("speech") or "添加失败，请稍后再试。"
        logger.info(f"新增用药计划: {speech}")
        return ActionResponse(Action.RESPONSE, None, speech)
    except Exception as exc:
        logger.error(f"新增用药计划失败: {exc}")
        return ActionResponse(Action.RESPONSE, None, "暂时无法添加计划，请打开智能药箱 App 操作。")

