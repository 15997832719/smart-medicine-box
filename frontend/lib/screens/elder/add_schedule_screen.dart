import 'package:flutter/material.dart';

import '../../core/design_system.dart';
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
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: Text(_isEditing ? '编辑用药计划' : '添加服药计划')),
      body: SafeArea(
        child: _jia_zai_zhong
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _loadMedicines,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(18, 4, 18, 104),
                  children: [
                    if (_cuo_wu != null) _buildError(),
                    _buildMedicineSection(),
                    const SizedBox(height: 11),
                    _buildTimeSection(),
                    const SizedBox(height: 11),
                    _buildDoseSection(),
                    const SizedBox(height: 14),
                    const AppNotice(
                      text: '本系统只记录你设置的服药计划，不提供诊断或开药建议。具体用药请遵医嘱。',
                      icon: Icons.warning_amber_rounded,
                      background: Color(0xCCFFF8ED),
                      foreground: Color(0xFF8A6843),
                      iconColor: Color(0xFFE39A3B),
                    ),
                  ],
                ),
              ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(20, 0, 20, 14),
        child: AppGradientButton(
          label: _bao_cun_zhong ? '正在保存…' : (_isEditing ? '保存修改' : '保存计划'),
          icon: Icons.check_rounded,
          loading: _bao_cun_zhong,
          height: 60,
          onPressed: _canSubmit ? _submit : null,
        ),
      ),
    );
  }

  bool get _canSubmit =>
      !_bao_cun_zhong &&
      _xuan_zhong_yao_pin != null &&
      _ji_liang_kong_zhi_qi.text.trim().isNotEmpty;

  Widget _buildError() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 11),
      child: AppNotice(
        text: _cuo_wu!,
        icon: Icons.error_outline_rounded,
        background: AppColors.redTint,
        foreground: const Color(0xFF95606A),
        iconColor: AppColors.red,
      ),
    );
  }

  Widget _buildMedicineSection() {
    return _section(
      title: '选择药品',
      step: '1',
      child: _yao_pin_lie_biao.isEmpty
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '还没有药品，请先拍照识别或手动录入药品。',
                  style: TextStyle(fontSize: 16, color: AppColors.muted, height: 1.5),
                ),
                const SizedBox(height: 12),
                AppSecondaryButton(
                  label: '去拍照识药',
                  icon: Icons.camera_alt_rounded,
                  height: 52,
                  onPressed: () => Navigator.of(context)
                      .push(ElderPageRoute(page: AIRecognizeScreen(elderId: widget.elderId)))
                      .then((_) => _loadMedicines()),
                ),
              ],
            )
          : Column(
              children: _yao_pin_lie_biao.map((medicine) {
                final selected = _xuan_zhong_yao_pin?.id == medicine.id;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 9),
                  child: AppGlassCard(
                    radius: 18,
                    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
                    color: selected
                        ? const Color(0xFFF1FBFF)
                        : Colors.white.withValues(alpha: 0.66),
                    border: Border.all(
                      color: selected
                          ? const Color(0xFF7FC4F2)
                          : Colors.white.withValues(alpha: 0.9),
                      width: selected ? 1.5 : 1,
                    ),
                    onTap: () => setState(() => _xuan_zhong_yao_pin = medicine),
                    child: Row(
                      children: [
                        AppIconTile(
                          icon: Icons.medication_rounded,
                          size: 46,
                          iconSize: 24,
                          gradient: selected ? AppGradients.primaryButton : null,
                          background: selected ? null : AppColors.blueTint,
                          color: selected ? Colors.white : AppColors.blue,
                        ),
                        const SizedBox(width: 11),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                medicine.name,
                                style: const TextStyle(
                                  fontSize: 19,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.ink,
                                ),
                              ),
                              if ((medicine.dosage ?? medicine.category) != null)
                                Text(
                                  medicine.dosage ?? medicine.category!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 14, color: AppColors.muted),
                                ),
                            ],
                          ),
                        ),
                        Icon(
                          selected
                              ? Icons.check_circle_rounded
                              : Icons.radio_button_unchecked_rounded,
                          color: selected ? AppColors.blue : const Color(0xFFA7B8C7),
                          size: 24,
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
    );
  }

  Widget _buildTimeSection() {
    return _section(
      title: '设置提醒时间',
      step: '2',
      trailing: Text(
        _isDaily ? '每天' : '指定日期',
        style: const TextStyle(fontSize: 13, color: AppColors.muted2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: true, label: Text('每天')),
              ButtonSegment(value: false, label: Text('指定日期')),
            ],
            selected: <bool>{_isDaily},
            onSelectionChanged: (selection) => setState(() => _isDaily = selection.first),
            style: ButtonStyle(
              textStyle: WidgetStateProperty.all(
                const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              shape: WidgetStateProperty.all(
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
          if (!_isDaily) ...[
            const SizedBox(height: 10),
            InkWell(
              borderRadius: BorderRadius.circular(17),
              onTap: _pickDate,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
                decoration: BoxDecoration(
                  color: AppColors.blueTint,
                  borderRadius: BorderRadius.circular(17),
                  border: Border.all(color: Colors.white),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_month_rounded, color: AppColors.blue, size: 26),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _dateText,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: AppColors.ink2,
                        ),
                      ),
                    ),
                    const Icon(Icons.edit_rounded, color: AppColors.blue, size: 20),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 10),
          InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: _pickTime,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFFF0FBFF), Color(0xFFE5F3FF)]),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white),
              ),
              child: Row(
                children: [
                  const AppIconTile(
                    icon: Icons.schedule_rounded,
                    size: 46,
                    iconSize: 24,
                    background: Colors.white,
                    color: AppColors.blue,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _timeText,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                  const Icon(Icons.edit_rounded, color: AppColors.blue, size: 20),
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
      title: '设置每次剂量',
      step: '3',
      trailing: const Text('请按医嘱', style: TextStyle(fontSize: 13, color: AppColors.muted2)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _ji_liang_kong_zhi_qi,
            style: const TextStyle(fontSize: 19),
            decoration: const InputDecoration(labelText: '每次剂量', hintText: '例如：1片 / 1袋 / 10ml'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _kuai_su_ji_liang.map((dose) {
              final selected = _ji_liang_kong_zhi_qi.text == dose;
              return ChoiceChip(
                label: Text(dose),
                selected: selected,
                onSelected: (_) => setState(() => _ji_liang_kong_zhi_qi.text = dose),
                selectedColor: AppColors.blue,
                labelStyle: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : AppColors.muted,
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _section({
    required String title,
    required String step,
    required Widget child,
    Widget? trailing,
  }) {
    return AppGlassCard(
      radius: 24,
      padding: const EdgeInsets.fromLTRB(15, 14, 15, 15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 31,
                height: 31,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.blueTint,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  step,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF2B7FC9),
                  ),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                    color: AppColors.ink2,
                  ),
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  String get _timeText =>
      '${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}';

  String get _dateText => '${_specificDate.year}年${_specificDate.month}月${_specificDate.day}日';

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
          reminderReady = await NotificationService.instance.requestPermissions();
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
          backgroundColor: reminderReady ? ElderTheme.successColor : ElderTheme.warningColor,
        ),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('保存失败：$e'), backgroundColor: ElderTheme.errorColor));
    } finally {
      if (mounted) setState(() => _bao_cun_zhong = false);
    }
  }
}
