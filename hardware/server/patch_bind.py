from pathlib import Path

for name in ("/opt/xiaozhi/config.yaml", "/opt/xiaozhi/data/.config.yaml"):
    p = Path(name)
    s = p.read_text(encoding="utf-8")
    if "bind_speaker_device" in s:
        continue
    anchor = "      - add_alarm"
    if anchor in s:
        s = s.replace(anchor, anchor + "\n      - bind_speaker_device", 1)
        p.write_text(s, encoding="utf-8")
        print(name, "patched")
