import 'package:flutter/material.dart';

import '../../core/design_system.dart';
import '../../core/theme.dart';
import '../../services/api_service.dart';
import '../../services/notification_service.dart';

class MedicationConfirmScreen extends StatefulWidget {
  final String yao_pin_ming_cheng;
  final String dosage;
  final int ji_hua_bian_hao;
  final int? yong_hu_bian_hao;
  final DateTime? ji_hua_shi_jian;

  const MedicationConfirmScreen({
    super.key,
    required this.yao_pin_ming_cheng,
    required this.dosage,
    required this.ji_hua_bian_hao,
    this.yong_hu_bian_hao,
    this.ji_hua_shi_jian,
  });

  @override
  State<MedicationConfirmScreen> createState() =>
      _MedicationConfirmScreenState();
}

class _MedicationConfirmScreenState extends State<MedicationConfirmScreen> {
  bool _bao_cun_zhong = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('服药确认')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 2, 20, 18),
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: AppGlassCard(
                    radius: 32,
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 124,
                          height: 124,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Color(0xFFCFFFF1),
                                Color(0xFF79E9CD),
                                Color(0xFF4ACBAF)
                              ],
                            ),
                            borderRadius: BorderRadius.circular(42),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x3C2AAB8F),
                                blurRadius: 28,
                                offset: Offset(0, 14),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.medication_rounded,
                            size: 66,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          '到时间吃药啦',
                          style: TextStyle(
                            fontSize: 36,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF0B3F39),
                          ),
                        ),
                        const SizedBox(height: 7),
                        const Text(
                          '请按医生或说明书指导用药',
                          style:
                              TextStyle(fontSize: 17, color: AppColors.muted),
                        ),
                        const SizedBox(height: 20),
                        Container(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.68),
                            borderRadius: BorderRadius.circular(23),
                            border: Border.all(color: Colors.white),
                          ),
                          child: Column(
                            children: [
                              Text(
                                widget.yao_pin_ming_cheng,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 27,
                                  fontWeight: FontWeight.w900,
                                  color: AppColors.ink,
                                ),
                              ),
                              const SizedBox(height: 14),
                              Row(
                                children: [
                                  Expanded(
                                    child: _InfoBox(
                                        label: '本次剂量', value: widget.dosage),
                                  ),
                                  const SizedBox(width: 10),
                                  const Expanded(
                                    child: _InfoBox(label: '确认时间', value: '现在'),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Text(
                                '计划时间 ${widget.ji_hua_shi_jian == null ? _currentTime() : _formatTime(widget.ji_hua_shi_jian!)}',
                                style: const TextStyle(
                                    fontSize: 16, color: AppColors.muted),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              AppGradientButton(
                label: '我已吃药',
                icon: Icons.check_circle_rounded,
                gradient: AppGradients.mintButton,
                loading: _bao_cun_zhong,
                height: 64,
                fontSize: 22,
                onPressed: _bao_cun_zhong ? null : _confirm,
              ),
              const SizedBox(height: 10),
              AppSecondaryButton(
                label: '稍后提醒（30 分钟）',
                icon: Icons.schedule_rounded,
                height: 56,
                fontSize: 18,
                onPressed: _bao_cun_zhong ? null : _snooze,
              ),
              const SizedBox(height: 8),
              const Text(
                '确认后家属端会看到本次服药记录',
                style: TextStyle(fontSize: 14, color: AppColors.muted2),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime time) =>
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

  Future<void> _confirm() async {
    setState(() => _bao_cun_zhong = true);
    try {
      await ApiService.confirmMedication(widget.ji_hua_bian_hao);
      try {
        await NotificationService.instance.markMedicationTaken(
          widget.ji_hua_bian_hao,
          ji_hua_shi_jian: widget.ji_hua_shi_jian,
        );
      } catch (_) {}
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.check_circle_rounded,
              color: ElderTheme.successColor, size: 58),
          title: const Text('已记录服药'),
          content: Text('已保存 ${widget.yao_pin_ming_cheng} 的本次服药记录，家属端可以查看。'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('知道了'))
          ],
        ),
      );
      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(
          content: Text('记录失败：$e'), backgroundColor: ElderTheme.errorColor));
    } finally {
      if (mounted) setState(() => _bao_cun_zhong = false);
    }
  }

  Future<void> _snooze() async {
    try {
      await NotificationService.instance.scheduleSnooze(
        ji_hua_bian_hao: widget.ji_hua_bian_hao,
        yong_hu_bian_hao: widget.yong_hu_bian_hao ?? 0,
        yao_pin_ming_cheng: widget.yao_pin_ming_cheng,
        dose: widget.dosage,
        ji_hua_shi_jian: widget.ji_hua_shi_jian,
      );
    } catch (_) {}
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('已设置 30 分钟后的系统提醒。'),
          backgroundColor: ElderTheme.warningColor),
    );
    Navigator.pop(context);
  }

  String _currentTime() {
    final now = DateTime.now();
    return '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
  }
}

class _InfoBox extends StatelessWidget {
  const _InfoBox({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF2FCFA),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Text(label,
              style: const TextStyle(fontSize: 15, color: Color(0xFF789B95))),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.w900,
              color: Color(0xFF174F62),
            ),
          ),
        ],
      ),
    );
  }
}
