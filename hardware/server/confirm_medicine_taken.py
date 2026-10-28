import httpx
from config.logger import setup_logging
from plugins_func.register import register_function, ToolType, ActionResponse, Action
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from core.connection import ConnectionHandler

TAG = __name__
logger = setup_logging()

CONFIRM_FUNCTION_DESC = {
    "type": "function",
    "function": {
        "name": "confirm_medicine_taken",
        "description": (
            "记录用户已经服用的具体药品。只有用户明确说出药名后才能调用。"
            "用户只说“我吃过了”“刚吃完药”而没有说药名时，禁止调用本工具，"
            "必须先问“您刚才吃的是哪种药”，等用户回答药名后再调用。"
            "绝不能用用药计划里的药名替用户猜测。"
        ),
        "parameters": {
            "type": "object",
            "properties": {
                "medicine": {
                    "type": "string",
                    "description": "用户亲口说出的药品名称；没有药名时不要调用",
                }
            },
            "required": ["medicine"],
        },
    },
}


@register_function("confirm_medicine_taken", CONFIRM_FUNCTION_DESC, ToolType.SYSTEM_CTL)
async def confirm_medicine_taken(conn: "ConnectionHandler", medicine: str):
    medicine = (medicine or "").strip()
    if not medicine:
        return ActionResponse(Action.RESPONSE, None, "请问您刚才吃的是哪种药？请说药名。")
    try:
        params = {"device_id": conn.device_id, "medicine": medicine}
        async with httpx.AsyncClient(timeout=8) as client:
            resp = await client.post("http://127.0.0.1:8013/confirm", params=params)
            resp.raise_for_status()
            data = resp.json()
        speech = data.get("speech") or "记录失败，请稍后再试。"
        logger.info(f"服药确认: {speech}")
        return ActionResponse(Action.RESPONSE, None, speech)
    except Exception as exc:
        logger.error(f"服药确认失败: {exc}")
        return ActionResponse(Action.RESPONSE, None, "暂时无法记录，请打开智能药箱 App 手动确认。")
