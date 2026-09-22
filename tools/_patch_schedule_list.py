from pathlib import Path
p = Path(r'D:\smart-medicine-box\frontend/lib/screens/elder/schedule_list_screen.dart')
s = p.read_text(encoding='utf-8')

def replace(old, new, expected=1):
    global s
    count = s.count(old)
    if count != expected:
        raise SystemExit(f'count={count}, expected={expected}: {old[:90]}')
    s = s.replace(old, new)

replace("import '../../services/api_service.dart';\n", "import '../../services/api_service.dart';\nimport '../../services/notification_service.dart';\n")
replace("  void _edit(Schedule schedule) {\n", "  String _dateText(Schedule schedule) {\n    final date = schedule.scheduleDate;\n    if (date == null) return '每天';\n    return '${date.year}年${date.month}月${date.day}日';\n  }\n\n  Future<void> _delete(Schedule schedule) async {\n    final confirmed = await showDialog<bool>(\n      context: context,\n      builder: (context) => AlertDialog(\n        title: const Text('删除用药计划'),\n        content: Text('确定删除“${schedule.medicineName ?? '药品'}”这条计划吗？'),\n        actions: [\n          TextButton(\n            onPressed: () => Navigator.pop(context, false),\n            child: const Text('取消'),\n          ),\n          FilledButton(\n            onPressed: () => Navigator.pop(context, true),\n            child: const Text('删除'),\n          ),\n        ],\n      ),\n    );\n    if (confirmed != true) return;\n    try {\n      await ApiService.deleteSchedule(schedule.id, elderId: widget.elderId);\n      if (widget.elderId == null) {\n        final schedules = await ApiService.getSchedules();\n        await NotificationService.instance.syncMedicationSchedules(schedules);\n      }\n      if (!mounted) return;\n      _reload();\n      ScaffoldMessenger.of(context).showSnackBar(\n        const SnackBar(content: Text('用药计划已删除')),\n      );\n    } catch (e) {\n      if (!mounted) return;\n      ScaffoldMessenger.of(context).showSnackBar(\n        SnackBar(content: Text('删除失败：$e')),\n      );\n    }\n  }\n\n  void _edit(Schedule schedule) {\n")
replace("                      '${schedule.remindTime}  ${schedule.dose ?? ''}',", "                      '${_dateText(schedule)}  ${schedule.remindTime}  ${schedule.dose ?? ''}',")
replace("                  trailing: IconButton(\n                    tooltip: '编辑计划',\n                    onPressed: () => _edit(schedule),\n                    icon: const Icon(Icons.edit_rounded),\n                  ),", "                  trailing: Row(\n                    mainAxisSize: MainAxisSize.min,\n                    children: [\n                      IconButton(\n                        tooltip: '编辑计划',\n                        onPressed: () => _edit(schedule),\n                        icon: const Icon(Icons.edit_rounded),\n                      ),\n                      IconButton(\n                        tooltip: '删除计划',\n                        onPressed: () => _delete(schedule),\n                        icon: const Icon(Icons.delete_outline_rounded),\n                        color: ElderTheme.errorColor,\n                      ),\n                    ],\n                  ),")
p.write_text(s, encoding='utf-8')
print('schedule list patch applied')
