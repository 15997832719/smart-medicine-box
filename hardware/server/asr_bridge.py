# -*- coding: utf-8 -*-
"""OpenAI 兼容的语音识别桥接：把 faster-whisper 包装成 /v1/audio/transcriptions。

小智服务端的 OpenaiASR 会把音频 POST 到这里，返回 {"text": "..."}。

启动：
    /opt/xiaozhi/.venv/bin/uvicorn asr_bridge:app --host 127.0.0.1 --port 8012
"""
import os
import tempfile

from fastapi import FastAPI, File, Form, UploadFile
from faster_whisper import WhisperModel

try:
    from opencc import OpenCC
    _cc = OpenCC("t2s")
except Exception:
    _cc = None

MODEL_NAME = os.getenv("ASR_MODEL", "base")
MODEL_ROOT = os.getenv("ASR_MODEL_ROOT", "/opt/xiaozhi/models/whisper")

app = FastAPI(title="Local Whisper ASR Bridge")
_whisper = None


def get_model() -> WhisperModel:
    global _whisper
    if _whisper is None:
        _whisper = WhisperModel(
            MODEL_NAME,
            device="cpu",
            compute_type="int8",
            cpu_threads=2,
            num_workers=1,
            download_root=MODEL_ROOT,
        )
    return _whisper


@app.get("/health")
def health() -> dict:
    return {"status": "ok", "model": MODEL_NAME}


@app.post("/v1/audio/transcriptions")
async def transcribe(
    file: UploadFile = File(...),
    model: str = Form("whisper-1"),
    language: str = Form("zh"),
) -> dict:
    suffix = os.path.splitext(file.filename or "audio.wav")[1] or ".wav"
    with tempfile.NamedTemporaryFile(suffix=suffix, delete=False) as tmp:
        tmp.write(await file.read())
        path = tmp.name
    try:
        segments, _info = get_model().transcribe(
            path,
            language=language or "zh",
            beam_size=2,
            vad_filter=False,
            condition_on_previous_text=False,
            initial_prompt="以下是普通话的简体中文句子。",
        )
        text = "".join(seg.text for seg in segments).strip()
        if _cc is not None:
            text = _cc.convert(text)
    finally:
        try:
            os.unlink(path)
        except OSError:
            pass
    return {"text": text}



