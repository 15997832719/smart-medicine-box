# -*- coding: utf-8 -*-
"""用药计划查询、语音确认、语音新增计划与闹钟服务。"""
import datetime as dt
from difflib import SequenceMatcher
import os
import re
import sqlite3

from fastapi import FastAPI, Query

DB_PATH = os.getenv("MEDICINE_DB", "/root/smart-medicine-box-backend/smart_medicine_box.db")
DEFAULT_OWNER = int(os.getenv("MEDICINE_OWNER_ID", "1"))

app = FastAPI(title="Medicine Plan API")


def _connect(readonly: bool = True) -> sqlite3.Connection:
    if readonly:
        return sqlite3.connect(f"file:{DB_PATH}?mode=ro", uri=True, timeout=5)
    return sqlite3.connect(DB_PATH, timeout=5)


def _resolve_owner(device_id: str | None, owner_id: int | None) -> int | None:
    """设备号优先：speaker_bindings 里查到就用绑定的账号，否则用默认账号。"""
    if owner_id is not None:
        return owner_id
    if device_id:
        con = _connect()
        try:
            row = con.execute(
                "SELECT user_id FROM speaker_bindings WHERE speaker_id = ? LIMIT 1",
                (device_id,),
            ).fetchone()
        finally:
            con.close()
        if row:
            return int(row[0])
    return None


@app.on_event("startup")
def _init_tables() -> None:
    con = _connect(readonly=False)
    try:
        con.execute(
            """
            CREATE TABLE IF NOT EXISTS voice_alarms (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                owner_id INTEGER NOT NULL,
                label TEXT NOT NULL,
                fire_at DATETIME NOT NULL,
                repeat TEXT NOT NULL DEFAULT 'once',
                enabled INTEGER NOT NULL DEFAULT 1,
                created_at DATETIME NOT NULL
            )
            """
        )
        con.commit()
    finally:
        con.close()


GENERIC_MEDICINE_PHRASES = {
    "药",
    "吃药",
    "服药",
    "用药",
    "吃过了",
    "我吃过了",
    "吃药了",
    "我吃药了",
    "我吃了药",
    "吃了药",
    "刚吃药",
    "我刚吃药",
    "已经吃药",
    "吃过药了",
    "我吃过药了",
    "已经吃了",
    "我刚吃了",
    "刚吃完药",
    "服药了",
    "吃过药",
    "吃了点药",
}


def _normalize_medicine(value: str | None) -> str:
    return re.sub(r"[\s,，。.!！?？;；:：、/]+", "", value or "").lower()


def _plan_medicine_names(plan: dict) -> list[str]:
    names = [plan.get("medicine") or ""]
    aliases = plan.get("alias") or ""
    names.extend(part.strip() for part in re.split(r"[,，、/]+", aliases) if part.strip())
    return [name for name in dict.fromkeys(names) if name]


def _match_today_plans(plans: list[dict], medicine: str | None) -> list[dict]:
    key = _normalize_medicine(medicine)
    if not key or key in GENERIC_MEDICINE_PHRASES or len(key) < 2:
        return []

    exact: list[dict] = []
    partial: list[dict] = []
    for plan in plans:
        for name in _plan_medicine_names(plan):
            candidate = _normalize_medicine(name)
            if not candidate:
                continue
            if key == candidate:
                exact.append(plan)
                break
            common = SequenceMatcher(None, key, candidate).find_longest_match().size
            if min(len(key), len(candidate)) >= 3 and common >= 3:
                partial.append(plan)
                break
    matched = exact or partial
    return list({id(plan): plan for plan in matched}.values())


def _today_plans(owner_id: int) -> list[dict]:
    con = _connect()
    try:
        rows = con.execute(
            """
            SELECT r.id, r.medicine_id, m.name, m.alias, r.remind_time, r.dose
              FROM reminder r
              LEFT JOIN medicine m ON m.id = r.medicine_id
             WHERE r.owner_id = ? AND r.enabled = 1
             ORDER BY r.remind_time
            """,
            (owner_id,),
        ).fetchall()
    finally:
        con.close()
    return [
        {
            "reminder_id": rid,
            "medicine_id": mid,
            "medicine": name or "药品",
            "alias": alias or "",
            "time": str(remind)[:5] if remind else "",
            "dose": dose or "",
        }
        for rid, mid, name, alias, remind, dose in rows
    ]


def _spoken_time(hhmm: str) -> str:
    try:
        hour, minute = (int(part) for part in hhmm.split(":")[:2])
    except (TypeError, ValueError):
        return hhmm
    if hour < 6:
        period = "凌晨"
    elif hour < 12:
        period = "早上"
    elif hour < 14:
        period = "中午"
    elif hour < 18:
        period = "下午"
    else:
        period = "晚上"
    hour_text = str(hour if hour <= 12 else hour - 12)
    minute_text = "" if minute == 0 else f"{minute}分"
    return f"{period}{hour_text}点{minute_text}"


def _speech(items: list[dict], detail: str = "summary", now: dt.datetime | None = None) -> str:
    if not items:
        return "今天暂无用药计划。"
    now = now or dt.datetime.now()
    if detail == "full":
        parts: list[str] = []
        for item in items[:5]:
            dose_text = f"，{item['dose']}" if item["dose"] else ""
            parts.append(f"{_spoken_time(item['time'])}服用{item['medicine']}{dose_text}")
        speech = f"今天有{len(items)}项用药：" + "；".join(parts)
        if len(items) > 5:
            speech += f"；另外还有{len(items) - 5}项，请在智能药箱 App 查看"
        return speech + "。"

    if len(items) == 1:
        item = items[0]
        dose_text = f"，{item['dose']}" if item["dose"] else ""
        return f"今天只有一项用药：{_spoken_time(item['time'])}服用{item['medicine']}{dose_text}。"

    now_text = now.strftime("%H:%M")
    upcoming = [item for item in items if item["time"] >= now_text]
    target = upcoming[0] if upcoming else None
    if target:
        dose_text = f"，{target['dose']}" if target["dose"] else ""
        return (
            f"今天有{len(items)}项用药。下一项是{_spoken_time(target['time'])}服用"
            f"{target['medicine']}{dose_text}。想听全部，请说“全部用药计划”。"
        )
    target = items[-1]
    dose_text = f"，{target['dose']}" if target["dose"] else ""
    return (
        f"今天有{len(items)}项用药，计划时间都已经过了。最后一项是"
        f"{_spoken_time(target['time'])}服用{target['medicine']}{dose_text}。"
        f"想听全部，请说“全部用药计划”。"
    )


def _minutes(hhmm: str, now: dt.datetime) -> int:
    try:
        h, m = hhmm.split(":")[:2]
        t = now.replace(hour=int(h), minute=int(m), second=0, microsecond=0)
        return abs(int((t - now).total_seconds() // 60))
    except Exception:
        return 24 * 60


def _norm_time(value: str) -> str:
    m = re.search(r"(\d{1,2})[:：点时](\d{1,2})?", value or "")
    if not m:
        raise ValueError("时间格式应为 HH:MM")
    h = int(m.group(1))
    minute = int(m.group(2) or 0)
    if not (0 <= h <= 23 and 0 <= minute <= 59):
        raise ValueError("时间超出范围")
    return f"{h:02d}:{minute:02d}"


@app.get("/today")
def today(
    owner_id: int | None = Query(default=None),
    device_id: str | None = Query(default=None),
    detail: str = Query(default="summary"),
) -> dict:
    owner_id = _resolve_owner(device_id, owner_id)
    if owner_id is None:
        return {"owner_id": None, "items": [], "speech": "这台音箱还没有绑定账号。请打开智能药箱 App，点“我的 → 音箱接入”生成绑定码，然后对我说：绑定码 加六位数字。"}
    items = _today_plans(owner_id)
    detail = "full" if detail == "full" else "summary"
    return {
        "owner_id": owner_id,
        "items": items,
        "detail": detail,
        "speech": _speech(items, detail),
    }


@app.post("/confirm")
def confirm(
    owner_id: int | None = Query(default=None),
    device_id: str | None = Query(default=None),
    medicine: str | None = Query(default=None),
) -> dict:
    owner_id = _resolve_owner(device_id, owner_id)
    if owner_id is None:
        return {"success": False, "speech": "这台音箱还没有绑定账号。请打开智能药箱 App，点“我的 → 音箱接入”生成绑定码，然后对我说：绑定码 加六位数字。"}
    now = dt.datetime.now()
    plans = _today_plans(owner_id)
    if not plans:
        return {"success": False, "speech": "今天没有找到用药计划，请先在智能药箱 App 里添加。"}

    key = _normalize_medicine(medicine)
    if not key or key in GENERIC_MEDICINE_PHRASES:
        return {
            "success": False,
            "needs_medicine": True,
            "speech": "请问您刚才吃的是哪种药？请说药名。",
        }

    matched = _match_today_plans(plans, medicine)
    if not matched:
        return {
            "success": False,
            "needs_medicine": True,
            "speech": "我没听清药名，请再说一遍。直接说您吃过的药品名称就可以。",
        }
    if len(matched) > 1:
        names = "、".join(dict.fromkeys(plan["medicine"] for plan in matched[:5]))
        return {
            "success": False,
            "needs_medicine": True,
            "speech": f"今天有多个计划都包含这个药名：{names}。请说完整药名。",
        }

    target = matched[0]
    con = _connect(readonly=False)
    try:
        logged = con.execute(
            "SELECT id FROM intakelog WHERE owner_id=? AND medicine_id=? AND date(taken_at)=date('now','localtime')",
            (owner_id, target["medicine_id"]),
        ).fetchone()
        if logged:
            return {"success": True, "already": True, "speech": f"今天已经记录过{target['medicine']}了，不需要重复记录。"}
        con.execute(
            "INSERT INTO intakelog (medicine_id, taken_at, dose, note, owner_id) VALUES (?,?,?,?,?)",
            (target["medicine_id"], now.strftime("%Y-%m-%d %H:%M:%S.%f"), target["dose"] or None, "通过语音确认", owner_id),
        )
        con.execute("UPDATE medicine SET stock_count = stock_count - 1 WHERE id=? AND stock_count > 0", (target["medicine_id"],))
        con.commit()
    finally:
        con.close()
    dose = f"，{target['dose']}" if target["dose"] else ""
    return {"success": True, "already": False, "speech": f"好的，已经记录您服用{target['medicine']}{dose}。"}

@app.post("/plan")
def add_plan(
    medicine: str = Query(...),
    time: str = Query(...),
    dose: str | None = Query(default=None),
    frequency: str = Query(default="daily"),
    owner_id: int | None = Query(default=None),
    device_id: str | None = Query(default=None),
) -> dict:
    owner_id = _resolve_owner(device_id, owner_id)
    if owner_id is None:
        return {"success": False, "speech": "这台音箱还没有绑定账号。请打开智能药箱 App，点“我的 → 音箱接入”生成绑定码，然后对我说：绑定码 加六位数字。"}
    name = medicine.strip()
    if not name:
        return {"success": False, "speech": "请告诉我药品名称。"}
    try:
        hhmm = _norm_time(time)
    except ValueError:
        return {"success": False, "speech": "请告诉我具体时间，比如早上八点。"}
    freq = frequency if frequency in ("daily", "once", "weekly") else "daily"

    now = dt.datetime.now()
    con = _connect(readonly=False)
    try:
        row = con.execute("SELECT id FROM medicine WHERE owner_id=? AND name LIKE ? LIMIT 1", (owner_id, f"%{name}%")).fetchone()
        if row:
            medicine_id = row[0]
        else:
            cur = con.execute(
                "INSERT INTO medicine (name, stock_count, low_stock_threshold, created_at, updated_at, owner_id) VALUES (?,?,?,?,?,?)",
                (name, 0, 3, now.strftime("%Y-%m-%d %H:%M:%S.%f"), now.strftime("%Y-%m-%d %H:%M:%S.%f"), owner_id),
            )
            medicine_id = cur.lastrowid
        con.execute(
            "INSERT INTO reminder (medicine_id, title, dose, remind_time, frequency, enabled, created_at, owner_id) VALUES (?,?,?,?,?,?,?,?)",
            (medicine_id, "用药提醒", dose, hhmm + ":00", freq, 1, now.strftime("%Y-%m-%d %H:%M:%S.%f"), owner_id),
        )
        con.commit()
    finally:
        con.close()

    when = "每天" if freq == "daily" else ""
    dose_text = f"，{dose}" if dose else ""
    return {"success": True, "speech": f"好的，已经添加{when}{hhmm}服用{name}{dose_text}的提醒。"}


@app.post("/alarm")
def add_alarm(
    label: str = Query(...),
    time: str = Query(...),
    repeat: str = Query(default="once"),
    owner_id: int | None = Query(default=None),
    device_id: str | None = Query(default=None),
) -> dict:
    owner_id = _resolve_owner(device_id, owner_id)
    if owner_id is None:
        return {"success": False, "speech": "这台音箱还没有绑定账号。请打开智能药箱 App，点“我的 → 音箱接入”生成绑定码，然后对我说：绑定码 加六位数字。"}
    try:
        hhmm = _norm_time(time)
    except ValueError:
        return {"success": False, "speech": "请告诉我具体时间，比如下午三点。"}
    now = dt.datetime.now()
    h, m = map(int, hhmm.split(":"))
    fire = now.replace(hour=h, minute=m, second=0, microsecond=0)
    if fire <= now:
        fire += dt.timedelta(days=1)
    rep = "daily" if repeat == "daily" else "once"
    con = _connect(readonly=False)
    try:
        con.execute(
            "INSERT INTO voice_alarms (owner_id, label, fire_at, repeat, enabled, created_at) VALUES (?,?,?,?,?,?)",
            (owner_id, label, fire.strftime("%Y-%m-%d %H:%M:%S"), rep, 1, now.strftime("%Y-%m-%d %H:%M:%S")),
        )
        con.commit()
    finally:
        con.close()
    when = "每天" if rep == "daily" else ""
    return {"success": True, "speech": f"好的，已经设置{when}{hhmm}提醒您{label}。"}


@app.get("/alarms/due")
def due_alarms(owner_id: int | None = Query(default=None), device_id: str | None = Query(default=None)) -> dict:
    owner_id = _resolve_owner(device_id, owner_id)
    if owner_id is None:
        return {"items": []}
    now = dt.datetime.now()
    con = _connect(readonly=False)
    try:
        rows = con.execute(
            "SELECT id, label, fire_at, repeat FROM voice_alarms WHERE owner_id=? AND enabled=1 AND fire_at <= ? ORDER BY fire_at",
            (owner_id, now.strftime("%Y-%m-%d %H:%M:%S")),
        ).fetchall()
        fired = []
        for aid, label, fire_at, rep in rows:
            fired.append({"id": aid, "label": label, "time": str(fire_at)[11:16]})
            if rep == "daily":
                nxt = dt.datetime.strptime(str(fire_at), "%Y-%m-%d %H:%M:%S") + dt.timedelta(days=1)
                con.execute("UPDATE voice_alarms SET fire_at=? WHERE id=?", (nxt.strftime("%Y-%m-%d %H:%M:%S"), aid))
            else:
                con.execute("UPDATE voice_alarms SET enabled=0 WHERE id=?", (aid,))
        con.commit()
    finally:
        con.close()
    return {"items": fired}


@app.post("/bind")
def bind_device(code: str = Query(...), device_id: str = Query(...)) -> dict:
    code = code.strip()
    device_id = device_id.strip()
    if not code or not device_id:
        return {"success": False, "speech": "绑定码或设备号为空。"}
    now = dt.datetime.now()
    con = _connect(readonly=False)
    try:
        row = con.execute(
            "SELECT id, user_id, code_expires_at FROM speaker_bindings WHERE pairing_code = ? LIMIT 1",
            (code,),
        ).fetchone()
        if not row:
            return {"success": False, "speech": "绑定码不正确，请在 App 里重新生成。"}
        binding_id, user_id, expires = row
        if expires and str(expires)[:19] < now.strftime("%Y-%m-%d %H:%M:%S"):
            return {"success": False, "speech": "绑定码已经过期，请在 App 里重新生成。"}
        con.execute(
            "DELETE FROM speaker_bindings WHERE speaker_id=? AND id<>?",
            (device_id, binding_id),
        )
        con.execute(
            "UPDATE speaker_bindings SET speaker_id=?, platform='xiaozhi', pairing_code=NULL, code_expires_at=NULL WHERE id=?",
            (device_id, binding_id),
        )
        con.commit()
    finally:
        con.close()
    return {"success": True, "speech": "绑定成功，以后这台音箱会使用您的用药计划。"}


@app.get("/health")
def health() -> dict:
    return {"status": "ok"}





