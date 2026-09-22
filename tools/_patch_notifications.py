from pathlib import Path
p = Path(r'D:\smart-medicine-box\frontend\lib\services\notification_service.dart')
s = p.read_text(encoding='utf-8')

def replace_all(old, new, expected):
    global s
    count = s.count(old)
    if count != expected:
        raise SystemExit(f'count={count}, expected={expected}: {old[:90]}')
    s = s.replace(old, new)

replace_all("medicineName: '??',\n        dose: '?????',", "medicineName: '药品',\n        dose: '',", 1)
replace_all("medicineName: (data['medicine_name'] ?? '??').toString(),\n        dose: (data['dose'] ?? '?????').toString(),", "medicineName: (data['medicine_name'] ?? '药品').toString(),\n        dose: (data['dose'] ?? '').toString(),", 1)
replace_all("            '????',\n            '${schedule.medicineName ?? '??'}${_doseText(schedule.dose)}??????????',", "            '用药提醒',\n            '${schedule.medicineName ?? '药品'}${_doseText(schedule.dose)}，服药时间到了，请及时确认。',", 1)
replace_all("            '????',\n            '${schedule.medicineName ?? '??'}?????????????????',", "            '漏服提醒',\n            '${schedule.medicineName ?? '药品'}${_doseText(schedule.dose)}，已超过计划时间，请尽快核实是否服药。',", 1)
replace_all("              medicineName: schedule.medicineName ?? '??',\n              dose: schedule.dose ?? '?????',", "              medicineName: schedule.medicineName ?? '药品',\n              dose: schedule.dose ?? '',", 2)
replace_all("      '??????',\n      '$medicineName${_doseText(dose)}???????????',", "      '稍后提醒',\n      '$medicineName${_doseText(dose)}，将在30分钟后再次提醒。',", 1)
replace_all("        ? alerts.first.message\n        : '??? $missed ????????????????';", "        ? alerts.first.message\n        : '今日有 $missed 项未确认用药，请及时查看。';", 1)
replace_all("      '??????',", "      '用药风险提醒',", 1)
replace_all("      dose == null || dose.trim().isEmpty ? '' : '??? $dose';", "      dose == null || dose.trim().isEmpty ? '' : '，剂量 $dose';", 1)
p.write_text(s, encoding='utf-8')

h = Path(r'D:\smart-medicine-box\frontend\lib\services\harmony_reminder_service.dart')
t = h.read_text(encoding='utf-8')
old = "              'medicine_name': schedule.medicineName ?? '??',\n              'dose': schedule.dose ?? '?????',"
new = "              'medicine_name': schedule.medicineName ?? '药品',\n              'dose': schedule.dose ?? '',\n              'schedule_date': schedule.scheduleDate?.toIso8601String().split('T').first,"
if t.count(old) != 1:
    raise SystemExit('harmony payload pattern not found')
h.write_text(t.replace(old, new, 1), encoding='utf-8')
print('notification text patch applied')
