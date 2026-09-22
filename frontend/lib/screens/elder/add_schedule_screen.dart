import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../models/medicine.dart';
import '../../services/api_service.dart';
import '../../services/notification_service.dart';
import 'ai_recognize_screen.dart';

class AddScheduleScreen extends StatefulWidget {
  const AddScheduleScreen({super.key, this.elderId, this.schedule});

  
  final int? elderId;
  final Schedule? schedule;

  @override
  State<AddScheduleScreen> createState() => _AddScheduleScreenState();
}

class _AddScheduleScreenState extends State<AddScheduleScreen> {
  final _ji_liang_kong_zhi_qi = TextEditingController(text: '1片');
  bool _jia_zai_zhong = true;
  bool _bao_cun_zhong = false;
  String? _cuo_wu;
  List<Medicine> _yao_pin_lie_biao = [];
  Medicine? _xuan_zhong_yao_pin;
  TimeOfDay _time = const TimeOfDay(hour: 8, minute: 0);
  bool _isDaily = true;
  DateTime _specificDate = DateTime.now().add(const Duration(days: 1));

  final _kuai_su_ji_liang = const ['半片', '1片', '2片', '1袋', '2袋', '5ml', '10ml'];

  bool get _isEditing => widget.schedule != null;

  @override
  void initState() {
    super.initState();
    final schedule = widget.schedule;
    if (schedule != null) {
      _ji_liang_kong_zhi_qi.text = schedule.dose ?? '1片';
      _time = TimeOfDay(hour: schedule.hour, minute: schedule.minute);
      if (schedule.ji_hua_ri_qi != null) {
        _isDaily = false;
        _specificDate = schedule.ji_hua_ri_qi!;
      }
    }
    _loadMedicines();
  }

  @override
  void dispose() {
    _ji_liang_kong_zhi_qi.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ElderTheme.bgColor,
      appBar: AppBar(
        title: Text(_isEditing ? '编辑用药计划' : '添加服药计划'),
      ),
      body: SafeArea(
        child: _jia_zai_zhong
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _loadMedicines,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (_cuo_wu != null) _buildError(),
                    _buildMedicineSection(),
                    const SizedBox(height: 14),
                    _buildTimeSection(),
                    const SizedBox(height: 14),
                    _buildDoseSection(),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: _canSubmit ? _submit : null,
                      icon: _bao_cun_zhong
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.check_rounded),
                      label: Text(_bao_cun_zhong
                          ? '正在保存...'
                          : (_isEditing ? '保存修改' : '保存计划')),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '提示：本系统只记录你已设置的服药计划，不提供诊断或开药建议。具体用药请遵医嘱。',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 13,
                          color: ElderTheme.textSecondary,
                          height: 1.35),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  bool get _canSubmit =>
      !_bao_cun_zhong &&
      _xuan_zhong_yao_pin != null &&
      _ji_liang_kong_zhi_qi.text.trim().isNotEmpty;

  Widget _buildError() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ElderTheme.errorColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: ElderTheme.errorColor),
          const SizedBox(width: 8),
          Expanded(
              child: Text(_cuo_wu!,
                  style: const TextStyle(color: ElderTheme.errorColor))),
        ],
      ),
    );
  }

  Widget _buildMedicineSection() {
    return _section(
      title: '1. 选择药品',
      icon: Icons.medication_rounded,
      child: _yao_pin_lie_biao.isEmpty
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('还没有药品，请先拍照识别或手动录入药品。',
                    style: TextStyle(
                        fontSize: 16, color: ElderTheme.textSecondary)),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context)
                      .push(ElderPageRoute(page: const AIRecognizeScreen()))
                      .then((_) => _loadMedicines()),
                  icon: const Icon(Icons.camera_alt_rounded),
                  label: const Text('去拍照识药'),
                ),
              ],
            )
          : Column(
              children: _yao_pin_lie_biao.map((medicine) {
                final selected = _xuan_zhong_yao_pin?.id == medicine.id;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => setState(() => _xuan_zhong_yao_pin = medicine),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: selected
                            ? ElderTheme.primaryColor.withOpacity(0.12)
                            : ElderTheme.bgColor,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                            color: selected
                                ? ElderTheme.primaryColor
                                : ElderTheme.dividerColor,
                            width: selected ? 2 : 1),
                      ),
                      child: Row(
                        children: [
                          Icon(
                              selected
                                  ? Icons.radio_button_checked_rounded
                                  : Icons.radio_button_off_rounded,
                              color: selected
                                  ? ElderTheme.primaryColor
                                  : ElderTheme.textSecondary),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(medicine.name,
                                    style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold)),
                                if ((medicine.dosage ?? medicine.category) !=
                                    null)
                                  Text(
                                    medicine.dosage ?? medicine.category!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        color: ElderTheme.textSecondary),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
    );
  }

  Widget _buildTimeSection() {
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

  Widget _buildDoseSection() {
    return _section(
      title: '3. 设置剂量',
      icon: Icons.straighten_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _ji_liang_kong_zhi_qi,
            decoration: const InputDecoration(
                labelText: '每次剂量', hintText: '例如：1片 / 1袋 / 10ml'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _kuai_su_ji_liang.map((dose) {
              final selected = _ji_liang_kong_zhi_qi.text == dose;
              return ChoiceChip(
                label: Text(dose),
                selected: selected,
                onSelected: (_) => setState(() => _ji_liang_kong_zhi_qi.text = dose),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _section(
      {required String title, required IconData icon, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ElderTheme.cardColor,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 12,
              offset: const Offset(0, 5))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: ElderTheme.primaryColor, size: 26),
              const SizedBox(width: 8),
              Text(title,
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  String get _timeText =>
      '${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}';

  String get _dateText =>
      '${_specificDate.year}年${_specificDate.month}月${_specificDate.day}日';

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _specificDate,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 5, 12, 31),
    );
    if (picked != null) setState(() => _specificDate = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (picked != null) setState(() => _time = picked);
  }

  Future<void> _loadMedicines() async {
    setState(() {
      _jia_zai_zhong = true;
      _cuo_wu = null;
    });
    try {
      final medicines = await ApiService.getMedicines(elderId: widget.elderId);
      if (!mounted) return;
      if (_xuan_zhong_yao_pin == null && widget.schedule != null) {
        for (final medicine in medicines) {
          if (medicine.id == widget.schedule!.yao_pin_bian_hao) {
            _xuan_zhong_yao_pin = medicine;
            break;
          }
        }
      }
      setState(() {
        _yao_pin_lie_biao = medicines;
        _xuan_zhong_yao_pin ??= medicines.isNotEmpty ? medicines.first : null;
        _jia_zai_zhong = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cuo_wu = '药品加载失败，请确认后端已启动。';
        _jia_zai_zhong = false;
      });
    }
  }

  Future<void> _submit() async {
    final medicine = _xuan_zhong_yao_pin;
    if (medicine == null) return;
    setState(() => _bao_cun_zhong = true);
    try {
      if (_isEditing) {
        await ApiService.updateSchedule(
          ji_hua_bian_hao: widget.schedule!.id,
          yao_pin_bian_hao: medicine.id,
          ti_xing_shi_jian: _timeText,
          dose: _ji_liang_kong_zhi_qi.text.trim(),
          ji_hua_ri_qi: _isDaily ? null : _specificDate,
          clearScheduleDate: _isDaily,
          elderId: widget.elderId,
        );
      } else {
        await ApiService.createSchedule(
          yao_pin_bian_hao: medicine.id,
          ti_xing_shi_jian: _timeText,
          dose: _ji_liang_kong_zhi_qi.text.trim(),
          ji_hua_ri_qi: _isDaily ? null : _specificDate,
          elderId: widget.elderId,
        );
      }

      var reminderReady = true;
      Object? notificationError;
      if (widget.elderId == null) {
        try {
          reminderReady =
              await NotificationService.instance.requestPermissions();
          final schedules = await ApiService.getSchedules();
          await NotificationService.instance.syncMedicationSchedules(schedules);
        } catch (error) {
          notificationError = error;
          debugPrint('Notification scheduling failed: $error');
        }
      }

      if (!mounted) return;
      final message = notificationError != null
          ? '服药计划已保存，但系统闹钟设置失败，请检查通知和“闹钟与提醒”权限后重试。'
          : !reminderReady
              ? '计划已保存，但系统未允许精确闹钟，已启用兼容提醒；鸿蒙下可能延迟，请在应用启动管理和电池设置中允许后台运行。'
              : (_isEditing ? '服药计划已修改' : '服药计划已保存');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: reminderReady
              ? ElderTheme.successColor
              : ElderTheme.warningColor,
        ),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('保存失败：$e'),
          backgroundColor: ElderTheme.errorColor));
    } finally {
      if (mounted) setState(() => _bao_cun_zhong = false);
    }
  }
}
