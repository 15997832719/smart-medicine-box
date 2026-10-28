from pathlib import Path

for name in ("/opt/xiaozhi/config.yaml", "/opt/xiaozhi/data/.config.yaml"):
    p = Path(name)
    s = p.read_text(encoding="utf-8")
    if "confirm_medicine_taken" in s:
        print(name, "already")
        continue
    old = "      - get_medicine_plan"
    if old not in s:
        print(name, "anchor missing")
        continue
    s = s.replace(old, old + "\n      - confirm_medicine_taken", 1)
    p.write_text(s, encoding="utf-8")
    print(name, "patched")
