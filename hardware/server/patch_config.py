# -*- coding: utf-8 -*-
"""把 xiaozhi-server 配成：本地 Whisper ASR + 智谱 LLM + EdgeTTS。"""
import re
from pathlib import Path

p = Path("/opt/xiaozhi/config.yaml")
s = p.read_text(encoding="utf-8")
orig = s

env = Path("/root/smart-medicine-box-backend/.env").read_text(encoding="utf-8")
m = re.search(r"^ZHIPU_API_KEY=(.+)$", env, re.M)
if not m:
    raise SystemExit("ZHIPU_API_KEY not found")
zhipu_key = m.group(1).strip().strip('"').strip("'")

repl = [
    ("  ip: 0.0.0.0\n  port: 8000", "  ip: 0.0.0.0\n  port: 8010"),
    ("  http_port: 8003", "  http_port: 8011"),
    ("  websocket: ws://你的ip或者域名:端口号/xiaozhi/v1/",
     "  websocket: wss://smart-medicine-box.124.156.137.131.nip.io/xiaozhi/v1/"),
    ("  ASR: FunASR", "  ASR: OpenaiASR"),
    ("    api_key: 你的OpenAI API密钥", "    api_key: local-whisper"),
    ("    base_url: https://api.openai.com/v1/audio/transcriptions",
     "    base_url: http://127.0.0.1:8012/v1/audio/transcriptions"),
    ("    model_name: gpt-4o-mini-transcribe", "    model_name: whisper-1"),
    ("    api_key: 你的chat-glm web key", "    api_key: " + zhipu_key),
]
for old, new in repl:
    if old not in s:
        print("MISS:", old[:40])
    s = s.replace(old, new, 1)

p.write_text(s, encoding="utf-8")
print("changed" if s != orig else "no change")
