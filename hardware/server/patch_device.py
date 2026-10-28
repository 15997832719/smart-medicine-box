from pathlib import Path
base = Path(r"D:\smart-medicine-box\hardware\server")

p = base / "get_medicine_plan.py"
s = p.read_text(encoding="utf-8")
s = s.replace(
    'await client.get("http://127.0.0.1:8013/today")',
    'await client.get("http://127.0.0.1:8013/today", params={"device_id": conn.device_id})',
)
p.write_text(s, encoding="utf-8")

p = base / "confirm_medicine_taken.py"
s = p.read_text(encoding="utf-8")
s = s.replace(
    'params = {"medicine": medicine} if medicine else {}',
    'params = {"device_id": conn.device_id}\n        if medicine:\n            params["medicine"] = medicine',
)
p.write_text(s, encoding="utf-8")

p = base / "add_medicine_plan.py"
s = p.read_text(encoding="utf-8")
s = s.replace(
    'params = {"medicine": medicine, "time": time, "frequency": frequency}',
    'params = {"medicine": medicine, "time": time, "frequency": frequency, "device_id": conn.device_id}',
)
p.write_text(s, encoding="utf-8")

p = base / "add_alarm.py"
s = p.read_text(encoding="utf-8")
s = s.replace(
    'params={"label": label, "time": time, "repeat": repeat}',
    'params={"label": label, "time": time, "repeat": repeat, "device_id": conn.device_id}',
)
p.write_text(s, encoding="utf-8")

p = base / "agent-base-prompt.txt"
s = p.read_text(encoding="utf-8")
if "bind_speaker_device" not in s:
    s = s.replace(
        "</重要规则>",
        "10. 用户说“绑定音箱”或“绑定码123456”时，调用 bind_speaker_device，把6位数字作为 code 传入。\n</重要规则>",
    )
    p.write_text(s, encoding="utf-8")

print("device patch done")
