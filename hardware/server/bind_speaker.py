from config.logger import setup_logging
from plugins_func.register import register_function, ToolType, ActionResponse, Action
import httpx
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from core.connection import ConnectionHandler

logger = setup_logging()
TAG = __name__

DESC = {
    "type": "function",
    "function": {
        "name": "bind_speaker_device",
        "description": (
            "把当前音箱绑定到智能药箱账号。用户说“绑定音箱”“绑定码123456”时调用，"
            "参数 code 是从 App 里看到的6位数字。"
        ),
        "parameters": {
            "type": "object",
            "properties": {"code": {"type": "string", "description": "6位绑定码"}},
            "required": ["code"],
        },
    },
}


@register_function("bind_speaker_device", DESC, ToolType.SYSTEM_CTL)
async def bind_speaker_device(conn: "ConnectionHandler", code: str):
    try:
        async with httpx.AsyncClient(timeout=8) as client:
            resp = await client.post(
                "http://127.0.0.1:8013/bind",
                params={"code": code.strip(), "device_id": conn.device_id or ""},
            )
            resp.raise_for_status()
            data = resp.json()
        return ActionResponse(Action.RESPONSE, None, data.get("speech", "绑定失败。"))
    except Exception as exc:
        logger.error(f"绑定失败: {exc}")
        return ActionResponse(Action.RESPONSE, None, "绑定失败，请稍后再试。")
