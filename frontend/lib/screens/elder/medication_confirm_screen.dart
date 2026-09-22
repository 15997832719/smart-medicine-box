import 'package:flutter/material.dart';

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
  State<MedicationConfirmScreen> createState() => _MedicationConfirmScreenState();
}

class _MedicationConfirmScreenState extends State<MedicationConfirmScreen> {
  bool _bao_cun_zhong = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ElderTheme.bgColor,
      appBar: AppBar(
        title: const Text('服药确认'),
        backgroundColor: ElderTheme.successColor,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: ElderTheme.cardColor,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 16, offset: const Offset(0, 6))],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 112,
                          height: 112,
                          decoration: BoxDecoration(
                            color: ElderTheme.successColor.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(30),
                          ),
                          child: const Icon(Icons.medication_rounded, size: 66, color: ElderTheme.successColor),
                        ),
                        const SizedBox(height: 22),
                        const Text('到时间吃药啦', style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        const Text('请按医生或说明书指导用药', style: TextStyle(fontSize: 16, color: ElderTheme.textSecondary)),
                        const SizedBox(height: 24),
                        _infoRow(Icons.medication_rounded, '药品', widget.yao_pin_ming_cheng),
                        const Divider(height: 26),
                        _infoRow(Icons.straighten_rounded, '剂量', widget.dosage),
                        const Divider(height: 26),
                        _infoRow(Icons.access_time_rounded, '确认时间', _currentTime()),
                      ],
                    ),
                  ),
                ),
              ),
              ElevatedButton.icon(
                onPressed: _bao_cun_zhong ? null : _confirm,
                icon: _bao_cun_zhong
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.check_circle_rounded),
                label: const Text('我已吃药'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _bao_cun_zhong ? null : _snooze,
                icon: const Icon(Icons.schedule_rounded),
                label: const Text('稍后提醒'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: ElderTheme.successColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: ElderTheme.successColor),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 14, color: ElderTheme.textSecondary)),
              const SizedBox(height: 3),
              Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _confirm() async {
    setState(() => _bao_cun_zhong = true);
    try {
      await ApiService.confirmMedication(widget.ji_hua_bian_hao);
      try {
        await NotificationService.instance.markMedicationTaken(
          widget.ji_hua_bian_hao,
          ji_hua_shi_jian: widget.ji_hua_shi_jian,
        );
      } catch (_) {
        
        
      }
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.check_circle_rounded, color: ElderTheme.successColor, size: 58),
          title: const Text('已记录服药'),
          content: Text('已保存 ${widget.yao_pin_ming_cheng} 的本次服药记录，家属端可以查看。'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('知道了')),
          ],
        ),
      );
      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('记录失败：$e'), backgroundColor: ElderTheme.errorColor));
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
    } catch (_) {
      
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已设置 30 分钟后的系统提醒。'), backgroundColor: ElderTheme.warningColor),
    );
    Navigator.pop(context);
  }

  String _currentTime() {
    final now = DateTime.now();
    return '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
  }
}
