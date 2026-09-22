

from __future__ import annotations

from functools import lru_cache
from pathlib import Path

from app.config import get_settings


class ASRError(RuntimeError):
    pass



@lru_cache(maxsize=1)
def _load_model():
    settings = get_settings()
    try:
        from faster_whisper import WhisperModel
    except ImportError as exc:
        raise ASRError(
            "服务器尚未安装 faster-whisper，请在后端虚拟环境执行：pip install -r requirements.txt"
        ) from exc

    model_path = Path(settings.asr_model_dir).expanduser()
    model_path.mkdir(parents=True, exist_ok=True)
    try:
        return WhisperModel(
            settings.asr_model,
            device=settings.asr_device,
            compute_type=settings.asr_compute_type,
            cpu_threads=settings.asr_cpu_threads,
            num_workers=1,
            download_root=str(model_path),
        )
    except Exception as exc:
        raise ASRError(f"本地语音模型加载失败：{exc}") from exc


def transcribe_audio_file(path: Path, initial_prompt: str | None = None) -> str:

    settings = get_settings()
    model = _load_model()
    try:
        segments, _ = model.transcribe(
            str(path),
            language=settings.asr_language,
            beam_size=settings.asr_beam_size,
            vad_filter=True,
            initial_prompt=initial_prompt,
            condition_on_previous_text=False,
        )
        text = "".join(segment.text for segment in segments).strip()
    except Exception as exc:
        raise ASRError(f"本地语音识别失败：{exc}") from exc

    if not text:
        raise ASRError("没有识别到有效语音，请靠近麦克风后重试。")
    return text