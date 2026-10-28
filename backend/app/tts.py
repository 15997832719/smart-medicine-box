from __future__ import annotations

import tempfile
from pathlib import Path

from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.responses import FileResponse
from starlette.background import BackgroundTask

from app.auth import get_current_user
from app.config import get_settings
from app.models import User
from app.schemas import TtsRequest

router = APIRouter(prefix="/voice", tags=["voice"])


def _delete_file(path: str) -> None:
    Path(path).unlink(missing_ok=True)


@router.post("/synthesize")
async def synthesize_voice(
    payload: TtsRequest,
    user: User = Depends(get_current_user),
) -> FileResponse:
    del user
    text = payload.text.strip()
    if not text:
        raise HTTPException(status_code=400, detail="播报文本不能为空")

    temp = tempfile.NamedTemporaryFile(prefix="smb-tts-", suffix=".mp3", delete=False)
    temp.close()
    path = temp.name
    try:
        import edge_tts

        communicator = edge_tts.Communicate(text, get_settings().tts_voice)
        await communicator.save(path)
    except Exception as exc:
        _delete_file(path)
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=f"语音合成服务暂不可用：{exc}",
        ) from exc
    return FileResponse(
        path,
        media_type="audio/mpeg",
        filename="speech.mp3",
        background=BackgroundTask(_delete_file, path),
    )
