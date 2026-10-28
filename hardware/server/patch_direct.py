from pathlib import Path

files = [
    "get_medicine_plan.py",
    "confirm_medicine_taken.py",
    "add_medicine_plan.py",
    "add_alarm.py",
    "bind_speaker_device.py",
    "bind_speaker.py",
]

base = Path(r"D:\smart-medicine-box\hardware\server")
for name in files:
    p = base / name
    if not p.exists():
        continue
    s = p.read_text(encoding="utf-8")
    before = s
    s = s.replace("ActionResponse(Action.REQLLM, speech, None)", "ActionResponse(Action.RESPONSE, None, speech)")
    s = s.replace("ActionResponse(Action.REQLLM, data.get(\"speech\", \"绑定失败。\"), None)", "ActionResponse(Action.RESPONSE, None, data.get(\"speech\", \"绑定失败。\"))")
    s = s.replace("ActionResponse(\n            Action.REQLLM,\n            \"暂时查不到用药计划，请打开智能药箱 App 查看。\",\n            None,\n        )", "ActionResponse(\n            Action.RESPONSE,\n            None,\n            \"暂时查不到用药计划，请打开智能药箱 App 查看。\",\n        )")
    s = s.replace("ActionResponse(Action.REQLLM, \"暂时无法记录，请打开智能药箱 App 手动确认。\", None)", "ActionResponse(Action.RESPONSE, None, \"暂时无法记录，请打开智能药箱 App 手动确认。\")")
    s = s.replace("ActionResponse(Action.REQLLM, \"暂时无法添加计划，请打开智能药箱 App 操作。\", None)", "ActionResponse(Action.RESPONSE, None, \"暂时无法添加计划，请打开智能药箱 App 操作。\")")
    s = s.replace("ActionResponse(Action.REQLLM, \"暂时无法设置闹钟，请稍后再试。\", None)", "ActionResponse(Action.RESPONSE, None, \"暂时无法设置闹钟，请稍后再试。\")")
    s = s.replace("ActionResponse(Action.REQLLM, \"绑定失败，请稍后再试。\", None)", "ActionResponse(Action.RESPONSE, None, \"绑定失败，请稍后再试。\")")
    if s != before:
        p.write_text(s, encoding="utf-8")
        print(name, "patched")
