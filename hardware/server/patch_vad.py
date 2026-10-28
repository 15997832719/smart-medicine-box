from pathlib import Path

for name in ("/opt/xiaozhi/config.yaml", "/opt/xiaozhi/data/.config.yaml"):
    p = Path(name)
    s = p.read_text(encoding="utf-8")
    s = s.replace("min_silence_duration_ms: 200", "min_silence_duration_ms: 900")
    s = s.replace("tts_audio_send_delay: 0", "tts_audio_send_delay: 65")
    p.write_text(s, encoding="utf-8")
    print(name, "patched")
