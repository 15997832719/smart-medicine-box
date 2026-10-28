from pathlib import Path

for name in ("/opt/xiaozhi/config.yaml", "/opt/xiaozhi/data/.config.yaml"):
    p = Path(name)
    s = p.read_text(encoding="utf-8")
    if "get_medicine_plan" in s:
        print(name, "already")
        continue
    idx = s.find("  function_call:")
    if idx < 0:
        print(name, "function_call not found")
        continue
    pos = s.find("    functions:", idx)
    if pos < 0:
        print(name, "functions not found")
        continue
    end = pos + len("    functions:")
    s = s[:end] + "\n      - get_medicine_plan" + s[end:]
    p.write_text(s, encoding="utf-8")
    print(name, "patched")
