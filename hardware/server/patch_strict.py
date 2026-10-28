from pathlib import Path

p = Path(r"D:\smart-medicine-box\hardware\server\medicine_api.py")
s = p.read_text(encoding="utf-8")

s = s.replace(
    "def _resolve_owner(device_id: str | None, owner_id: int | None) -> int:",
    "def _resolve_owner(device_id: str | None, owner_id: int | None) -> int | None:",
)
s = s.replace(
    "        if row:\n            return int(row[0])\n    return DEFAULT_OWNER",
    "        if row:\n            return int(row[0])\n    return None",
)

WARN = "这台音箱还没有绑定账号。请打开智能药箱 App，点“我的 → 音箱接入”生成绑定码，然后对我说：绑定码 加六位数字。"

pairs = [
    (
        "    owner_id = _resolve_owner(device_id, owner_id)\n    items = _today_plans(owner_id)",
        "    owner_id = _resolve_owner(device_id, owner_id)\n    if owner_id is None:\n        return {\"owner_id\": None, \"items\": [], \"speech\": \"" + WARN + "\"}\n    items = _today_plans(owner_id)",
    ),
    (
        "    owner_id = _resolve_owner(device_id, owner_id)\n    now = dt.datetime.now()\n    plans = _today_plans(owner_id)",
        "    owner_id = _resolve_owner(device_id, owner_id)\n    if owner_id is None:\n        return {\"success\": False, \"speech\": \"" + WARN + "\"}\n    now = dt.datetime.now()\n    plans = _today_plans(owner_id)",
    ),
    (
        "    owner_id = _resolve_owner(device_id, owner_id)\n    name = medicine.strip()",
        "    owner_id = _resolve_owner(device_id, owner_id)\n    if owner_id is None:\n        return {\"success\": False, \"speech\": \"" + WARN + "\"}\n    name = medicine.strip()",
    ),
    (
        "    owner_id = _resolve_owner(device_id, owner_id)\n    try:\n        hhmm = _norm_time(time)",
        "    owner_id = _resolve_owner(device_id, owner_id)\n    if owner_id is None:\n        return {\"success\": False, \"speech\": \"" + WARN + "\"}\n    try:\n        hhmm = _norm_time(time)",
    ),
    (
        "    owner_id = _resolve_owner(device_id, owner_id)\n    now = dt.datetime.now()\n    con = _connect(readonly=False)",
        "    owner_id = _resolve_owner(device_id, owner_id)\n    if owner_id is None:\n        return {\"items\": []}\n    now = dt.datetime.now()\n    con = _connect(readonly=False)",
    ),
]

for old, new in pairs:
    if old not in s:
        print("MISS:", old.splitlines()[0])
    s = s.replace(old, new, 1)

p.write_text(s, encoding="utf-8")
print("done")
