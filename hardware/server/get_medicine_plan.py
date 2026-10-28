import httpx
from config.logger import setup_logging
from plugins_func.register import register_function, ToolType, ActionResponse, Action
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from core.connection import ConnectionHandler

TAG = __name__
logger = setup_logging()

GET_MEDICINE_FUNCTION_DESC = {
    "type": "function",
    "function": {
        "name": "get_medicine_plan",
        "description": (
            "查询当前用户今天需要服用的药品、时间和剂量。"
            "当用户问“今天吃什么药”“我的用药计划”“几点吃药”“该吃药了吗”时必须调用此工具，"
            "默认只返回简洁摘要；用户明确说“全部计划”“详细说说”时才用 full。"
            "严禁自己编造药品名称或剂量。"
        ),
        "parameters": {
            "type": "object",
            "properties": {
                "detail": {
                    "type": "string",
                    "enum": ["summary", "full"],
                    "description": "默认 summary；用户要求听全部计划时用 full",
                }
            },
            "required": [],
        },
    },
}


@register_function("get_medicine_plan", GET_MEDICINE_FUNCTION_DESC, ToolType.SYSTEM_CTL)
async def get_medicine_plan(conn: "ConnectionHandler", detail: str = "summary"):
    try:
        detail = "full" if detail == "full" else "summary"
        async with httpx.AsyncClient(timeout=6) as client:
            resp = await client.get(
                "http://127.0.0.1:8013/today",
                params={"device_id": conn.device_id, "detail": detail},
            )
            resp.raise_for_status()
            data = resp.json()
        speech = data.get("speech") or "今天暂无用药计划。"
        logger.info("用药计划查询成功: %s", speech)
        return ActionResponse(Action.RESPONSE, None, speech)
    except Exception as exc:
        logger.error("查询用药计划失败: %s", exc)
        return ActionResponse(
            Action.RESPONSE,
            None,
            "暂时查不到用药计划，请打开智能药箱 App 查看。",
        )
