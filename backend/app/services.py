import base64
import json
import re
from datetime import date, datetime, timedelta
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

from sqlmodel import Session, select

from app.models import Medicine
from app.config import get_settings
from app.schemas import (
    AlertRead,
    ConflictRead,
    InstructionParseResult,
    MedicineCreate,
    MedicineRead,
    RecognizeResult,
)


KNOWN_CONFLICTS = {
    frozenset({"布洛芬", "阿司匹林"}): "同属非甾体抗炎药，合用可能增加胃肠道出血风险。",
    frozenset({"华法林", "阿司匹林"}): "抗凝/抗血小板作用叠加，可能增加出血风险。",
    frozenset({"硝酸甘油", "西地那非"}): "可能导致严重低血压。",
}


def biao_qian_zhuan_zi_fu_chuan(tags: list[str] | None) -> str | None:
    if not tags:
        return None
    return ",".join(sorted({tag.strip() for tag in tags if tag.strip()}))


def zi_fu_chuan_zhuan_biao_qian(tags: str | None) -> list[str]:
    if not tags:
        return []
    return [tag.strip() for tag in tags.split(",") if tag.strip()]


def yao_pin_zhuan_du_qu(medicine: Medicine) -> MedicineRead:
    data = medicine.model_dump()
    data["conflict_tags"] = zi_fu_chuan_zhuan_biao_qian(medicine.conflict_tags)
    data["user_id"] = medicine.owner_id
    return MedicineRead(**data)


def gou_jian_yao_pin(payload: MedicineCreate) -> Medicine:
    data = payload.model_dump(exclude={"conflict_tags"})
    return Medicine(**data, conflict_tags=biao_qian_zhuan_zi_fu_chuan(payload.conflict_tags))


def lie_chu_jing_gao(session: Session, owner_ids: list[int] | None = None) -> list[AlertRead]:
    today = date.today()
    soon = today + timedelta(days=30)
    alerts: list[AlertRead] = []

    query = select(Medicine).order_by(Medicine.expire_date)
    if owner_ids is not None:
        query = query.where(Medicine.owner_id.in_(owner_ids))
    medicines = session.exec(query).all()
    for medicine in medicines:
        if medicine.stock_count <= medicine.low_stock_threshold:
            alerts.append(
                AlertRead(
                    type="low_stock",
                    severity="medium",
                    medicine_id=medicine.id or 0,
                    medicine_name=medicine.name,
                    message=f"{medicine.name} 库存剩余 {medicine.stock_count}，低于阈值 {medicine.low_stock_threshold}。",
                )
            )

        if medicine.expire_date and medicine.expire_date < today:
            alerts.append(
                AlertRead(
                    type="expired",
                    severity="high",
                    medicine_id=medicine.id or 0,
                    medicine_name=medicine.name,
                    message=f"{medicine.name} 已于 {medicine.expire_date.isoformat()} 过期。",
                )
            )
        elif medicine.expire_date and medicine.expire_date <= soon:
            alerts.append(
                AlertRead(
                    type="expiring",
                    severity="medium",
                    medicine_id=medicine.id or 0,
                    medicine_name=medicine.name,
                    message=f"{medicine.name} 将于 {medicine.expire_date.isoformat()} 过期。",
                )
            )

    return alerts


def check_conflicts(medicines: list[Medicine], extra_names: list[str] | None = None) -> list[ConflictRead]:
    names = [medicine.name for medicine in medicines] + (extra_names or [])
    gui_fan_hua_wen_ben = {name.strip() for name in names if name.strip()}
    conflicts: list[ConflictRead] = []

    for pair, reason in KNOWN_CONFLICTS.items():
        if pair.issubset(gui_fan_hua_wen_ben):
            medicine_a, medicine_b = sorted(pair)
            conflicts.append(ConflictRead(medicine_a=medicine_a, medicine_b=medicine_b, reason=reason, severity="high"))

    tag_map = {medicine.name: set(zi_fu_chuan_zhuan_biao_qian(medicine.conflict_tags)) for medicine in medicines}
    medicine_names = list(tag_map)
    for index, name_a in enumerate(medicine_names):
        for name_b in medicine_names[index + 1 :]:
            shared_tags = tag_map[name_a] & tag_map[name_b]
            if shared_tags:
                conflicts.append(
                    ConflictRead(
                        medicine_a=name_a,
                        medicine_b=name_b,
                        reason=f"两种药品存在相同风险标签：{', '.join(sorted(shared_tags))}。",
                        severity="medium",
                    )
                )

    return conflicts


class MedicineRecognitionError(RuntimeError):
    pass



def _jie_xi_mo_xing_ri_qi(value: Any) -> date | None:
    if value is None:
        return None
    try:
        return date.fromisoformat(str(value).strip()[:10])
    except ValueError:
        return None


def _json_from_model_text(text: str) -> dict[str, Any]:
    cleaned = text.strip()
    fenced = re.search(r"```(?:json)?\s*(.*?)```", cleaned, flags=re.IGNORECASE | re.DOTALL)
    if fenced:
        cleaned = fenced.group(1).strip()
    try:
        value = json.loads(cleaned)
    except json.JSONDecodeError as exc:
        raise MedicineRecognitionError("视觉模型返回的不是有效 JSON。") from exc
    if not isinstance(value, dict):
        raise MedicineRecognitionError("视觉模型返回的数据格式不正确。")
    return value


def _model_content(payload: dict[str, Any]) -> str:
    choices = payload.get("choices")
    if not isinstance(choices, list) or not choices:
        raise MedicineRecognitionError("视觉模型没有返回识别结果。")
    message = choices[0].get("message") if isinstance(choices[0], dict) else None
    content = message.get("content") if isinstance(message, dict) else None
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return "".join(str(part.get("text", "")) for part in content if isinstance(part, dict))
    raise MedicineRecognitionError("视觉模型返回内容为空。")


def _medicine_from_model(value: dict[str, Any]) -> RecognizeResult:
    name = str(value.get("name") or "").strip()
    if not name:
        raise MedicineRecognitionError("无法从图片确认药品名称，请拍摄清晰的药盒正面。")

    def text(key: str) -> str | None:
        item = value.get(key)
        return str(item).strip() if item is not None and str(item).strip() else None

    raw_confidence = value.get("confidence", 0.0)
    try:
        confidence = max(0.0, min(1.0, float(raw_confidence)))
    except (TypeError, ValueError):
        confidence = 0.0

    tags = value.get("conflict_tags") or []
    if isinstance(tags, str):
        tags = [item.strip() for item in re.split(r"[,，、]", tags) if item.strip()]
    if not isinstance(tags, list):
        tags = []

    return RecognizeResult(
        medicine=MedicineCreate(
            name=name,
            alias=text("alias"),
            category=text("category"),
            manufacturer=text("manufacturer"),
            description=text("description"),
            dosage=text("dosage"),
            precautions=text("precautions"),
            conflict_tags=[str(item).strip() for item in tags if str(item).strip()],
            stock_count=0,
            expire_date=_jie_xi_mo_xing_ri_qi(value.get("expire_date") or value.get("valid_date")),
        ),
        confidence=confidence,
        source="zhipu_glm_vision",
    )


async def recognize_medicine_image(image: bytes, content_type: str | None) -> RecognizeResult:
    if not image:
        raise MedicineRecognitionError("上传的图片为空。")
    if len(image) > 8 * 1024 * 1024:
        raise MedicineRecognitionError("图片不能超过 8 MB。")

    settings = get_settings()
    api_key = settings.zhipu_api_key
    if not api_key:
        raise MedicineRecognitionError("尚未配置 ZHIPU_API_KEY，暂时无法进行真实图片识别。")

    mime = content_type if content_type in {"image/jpeg", "image/png", "image/webp"} else "image/jpeg"
    encoded = base64.b64encode(image).decode("ascii")
    prompt = (
        "请识别图片中的药品包装，只返回 JSON，不要 Markdown。字段必须为："
        "name, alias, category, manufacturer, description, dosage, precautions, conflict_tags, expire_date, confidence。"
        "必须读取包装上的有效期或失效日期并以 YYYY-MM-DD 返回 expire_date；看不清时返回空值。"
        "看不清或无法确认时 name 返回空字符串，confidence 返回 0。不要猜测药名、剂量或有效期。"
    )
    body = json.dumps(
        {
            "model": settings.zhipu_vision_model,
            "temperature": 0.1,
            "messages": [
                {
                    "role": "user",
                    "content": [
                        {"type": "text", "text": prompt},
                        {"type": "image_url", "image_url": {"url": f"data:{mime};base64,{encoded}"}},
                    ],
                }
            ],
        },
        ensure_ascii=False,
    ).encode("utf-8")
    request = Request(
        "https://open.bigmodel.cn/api/paas/v4/chat/completions",
        data=body,
        headers={"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urlopen(request, timeout=45) as response:
            result = json.loads(response.read().decode("utf-8"))
    except HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")[:300]
        raise MedicineRecognitionError(f"视觉识别服务请求失败（HTTP {exc.code}）：{detail}") from exc
    except (URLError, TimeoutError, json.JSONDecodeError) as exc:
        raise MedicineRecognitionError("视觉识别服务暂时不可用，请稍后重试。") from exc

    recognized = _medicine_from_model(_json_from_model_text(_model_content(result)))
    return _enrich_from_local_leaflet(recognized)




_LOCAL_LEAFLETS = {
    "九九九感冒灵": {"dosage": "成人一次1袋，一日3次，开水冲服。", "precautions": ["孕妇、哺乳期及儿童请先咨询医生。", "服药期间避免饮酒。", "对本品成分过敏者禁用。"]},
    "布洛芬": {"dosage": "成人一次1片（200mg），每4至6小时一次，24小时不超过4片。", "precautions": ["胃溃疡、肾功能不全患者慎用。", "不得与其他解热镇痛药同服。"]},
}

def _enrich_from_local_leaflet(result: RecognizeResult) -> RecognizeResult:
    if not result.medicine.name:
        return result
    entry = next((v for k, v in _LOCAL_LEAFLETS.items() if k in result.medicine.name or result.medicine.name in k), None)
    if not entry:
        return result
    return result.model_copy(update={
        "medicine": result.medicine.model_copy(update={"dosage": result.medicine.dosage or entry["dosage"], "precautions": result.medicine.precautions or "；".join(entry["precautions"])}),
        "source": "local_leaflet",
    })


async def parse_instruction_ai(text: str) -> InstructionParseResult:
    gui_fan_hua_wen_ben = text.strip()
    if not gui_fan_hua_wen_ben:
        raise MedicineRecognitionError("说明书内容不能为空。")
    settings = get_settings()
    if not settings.zhipu_api_key:
        raise MedicineRecognitionError("尚未配置 ZHIPU_API_KEY，暂时无法解析说明书。")

    prompt = (
        "请从下面的药品说明书文字中提取结构化信息，只返回 JSON，不要 Markdown。"
        "字段必须为 name, dosage, precautions, conflict_tags, summary。"
        "不要补写原文没有的信息；不确定的字段使用空字符串或空数组。\n\n"
        f"说明书文字：\n{gui_fan_hua_wen_ben[:12000]}"
    )
    body = json.dumps(
        {
            "model": settings.zhipu_text_model,
            "temperature": 0.1,
            "messages": [{"role": "user", "content": prompt}],
        },
        ensure_ascii=False,
    ).encode("utf-8")
    request = Request(
        "https://open.bigmodel.cn/api/paas/v4/chat/completions",
        data=body,
        headers={"Authorization": f"Bearer {settings.zhipu_api_key}", "Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urlopen(request, timeout=45) as response:
            result = json.loads(response.read().decode("utf-8"))
    except HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")[:300]
        raise MedicineRecognitionError(f"说明书解析服务请求失败（HTTP {exc.code}）：{detail}") from exc
    except (URLError, TimeoutError, json.JSONDecodeError) as exc:
        raise MedicineRecognitionError("说明书解析服务暂时不可用，请稍后重试。") from exc

    value = _json_from_model_text(_model_content(result))
    precautions = value.get("precautions") or []
    conflicts = value.get("conflict_tags") or []
    if isinstance(precautions, str):
        precautions = [precautions]
    if isinstance(conflicts, str):
        conflicts = [item.strip() for item in re.split(r"[,，、]", conflicts) if item.strip()]
    return InstructionParseResult(
        name=str(value.get("name") or "").strip() or None,
        dosage=str(value.get("dosage") or "").strip() or None,
        precautions=[str(item).strip() for item in precautions if str(item).strip()],
        conflict_tags=[str(item).strip() for item in conflicts if str(item).strip()],
        summary=str(value.get("summary") or gui_fan_hua_wen_ben[:160]).strip(),
    )


def parse_instruction_stub(text: str) -> InstructionParseResult:
    gui_fan_hua_wen_ben = text.strip()
    conflict_tags: list[str] = []
    precautions: list[str] = []

    if "孕妇" in gui_fan_hua_wen_ben:
        precautions.append("孕妇用药需咨询医生。")
        conflict_tags.append("孕妇慎用")
    if "过敏" in gui_fan_hua_wen_ben:
        precautions.append("对本品过敏者禁用。")
        conflict_tags.append("过敏风险")
    if "酒" in gui_fan_hua_wen_ben:
        precautions.append("服药期间避免饮酒。")
        conflict_tags.append("饮酒风险")

    dosage = None
    for keyword in ["一次", "每日", "每天"]:
        start = gui_fan_hua_wen_ben.find(keyword)
        if start >= 0:
            dosage = gui_fan_hua_wen_ben[start : start + 40]
            break

    return InstructionParseResult(
        name=None,
        dosage=dosage,
        precautions=precautions,
        conflict_tags=conflict_tags,
        summary=gui_fan_hua_wen_ben[:160] + ("..." if len(gui_fan_hua_wen_ben) > 160 else ""),
    )


def utcnow() -> datetime:
    return datetime.utcnow()
