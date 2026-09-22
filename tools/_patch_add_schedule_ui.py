from pathlib import Path
p = Path(r'D:\smart-medicine-box\frontend/lib/screens/elder/add_schedule_screen.dart')
s = p.read_text(encoding='utf-8')

def replace(old, new, expected=1):
    global s
    count = s.count(old)
    if count != expected:
        raise SystemExit(f'count={count}, expected={expected}: {old[:100]}')
    s = s.replace(old, new)

replace("  Medicine? _selectedMedicine;\n  TimeOfDay _time = const TimeOfDay(hour: 8, minute: 0);", "  Medicine? _selectedMedicine;\n  TimeOfDay _time = const TimeOfDay(hour: 8, minute: 0);\n  bool _isDaily = true;\n  DateTime _specificDate = DateTime.now().add(const Duration(days: 1));")
replace("      _doseController.text = schedule.dose ?? '1片';\n      _time = TimeOfDay(hour: schedule.hour, minute: schedule.minute);", "      _doseController.text = schedule.dose ?? '1片';\n      _time = TimeOfDay(hour: schedule.hour, minute: schedule.minute);\n      if (schedule.scheduleDate != null) {\n        _isDaily = false;\n        _specificDate = schedule.scheduleDate!;\n      }")

old_time = """  Widget _buildTimeSection() {
    return _section(
      title: '2. 设置提醒时间',
      icon: Icons.access_time_rounded,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: _pickTime,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
          decoration: BoxDecoration(
            color: ElderTheme.primaryColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              const Icon(Icons.schedule_rounded,
                  color: ElderTheme.primaryColor, size: 30),
              const SizedBox(width: 12),
              Expanded(
                child: Text(_timeText,
                    style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: ElderTheme.primaryColor)),
              ),
              const Icon(Icons.edit_rounded, color: ElderTheme.primaryColor),
            ],
          ),
        ),
      ),
    );
  }
"""
new_time = """  Widget _buildTimeSection() {
    return _section(
      title: '2. 设置提醒时间',
      icon: Icons.access_time_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: true, label: Text('每天')),
              ButtonSegment(value: false, label: Text('指定日期')),
            ],
            selected: <bool>{_isDaily},
            onSelectionChanged: (selection) {
              setState(() => _isDaily = selection.first);
            },
          ),
          if (!_isDaily) ...[
            const SizedBox(height: 12),
            InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: _pickDate,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                decoration: BoxDecoration(
                  color: ElderTheme.primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_month_rounded,
                        color: ElderTheme.primaryColor, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(_dateText,
                          style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: ElderTheme.primaryColor)),
                    ),
                    const Icon(Icons.edit_rounded,
                        color: ElderTheme.primaryColor),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: _pickTime,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
              decoration: BoxDecoration(
                color: ElderTheme.primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  const Icon(Icons.schedule_rounded,
                      color: ElderTheme.primaryColor, size: 30),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(_timeText,
                        style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: ElderTheme.primaryColor)),
                  ),
                  const Icon(Icons.edit_rounded,
                      color: ElderTheme.primaryColor),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
"""
replace(old_time, new_time)
replace("  String get _timeText =>\n      '${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}';\n", "  String get _timeText =>\n      '${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}';\n\n  String get _dateText =>\n      '${_specificDate.year}年${_specificDate.month}月${_specificDate.day}日';\n\n  Future<void> _pickDate() async {\n    final now = DateTime.now();\n    final picked = await showDatePicker(\n      context: context,\n      initialDate: _specificDate,\n      firstDate: DateTime(now.year, now.month, now.day),\n      lastDate: DateTime(now.year + 5, 12, 31),\n    );\n    if (picked != null) setState(() => _specificDate = picked);\n  }\n")
replace("          remindTime: _timeText,\n          dose: _doseController.text.trim(),\n          elderId: widget.elderId,\n        );\n      } else {\n        await ApiService.createSchedule(\n          medicineId: medicine.id,\n          remindTime: _timeText,\n          dose: _doseController.text.trim(),\n          elderId: widget.elderId,\n        );", "          remindTime: _timeText,\n          dose: _doseController.text.trim(),\n          scheduleDate: _isDaily ? null : _specificDate,\n          clearScheduleDate: _isDaily,\n          elderId: widget.elderId,\n        );\n      } else {\n        await ApiService.createSchedule(\n          medicineId: medicine.id,\n          remindTime: _timeText,\n          dose: _doseController.text.trim(),\n          scheduleDate: _isDaily ? null : _specificDate,\n          elderId: widget.elderId,\n        );")
p.write_text(s, encoding='utf-8')
print('add schedule date UI patch applied')
