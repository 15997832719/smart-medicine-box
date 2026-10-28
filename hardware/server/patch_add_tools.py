from pathlib import Path

for name in ("/opt/xiaozhi/config.yaml", "/opt/xiaozhi/data/.config.yaml"):
    p = Path(name)
    s = p.read_text(encoding="utf-8")
    changed = False
    for fn in ("add_medicine_plan", "add_alarm"):
        if fn in s:
            continue
        anchor = "      - confirm_medicine_taken"
        if anchor not in s:
            print(name, "anchor missing")
            break
        s = s.replace(anchor, anchor + f"\n      - {fn}", 1)
        changed = True
    if changed:
        p.write_text(s, encoding="utf-8")
        print(name, "patched")
