import 'package:flutter/material.dart';

import '../../core/design_system.dart';
import '../../core/theme.dart';
import '../../models/medicine.dart';
import '../../services/api_service.dart';
import '../elder/add_schedule_screen.dart';
import '../elder/ai_recognize_screen.dart';

class ChildElderDetailScreen extends StatefulWidget {
  final int elderId;
  final String elderName;

  const ChildElderDetailScreen({super.key, required this.elderId, required this.elderName});

  @override
  State<ChildElderDetailScreen> createState() => _ChildElderDetailScreenState();
}

class _ChildElderDetailScreenState extends State<ChildElderDetailScreen> {
  bool _jia_zai_zhong = true;
  List<Medicine> _yao_pin_lie_biao = [];
  List<Schedule> _yong_yao_ji_hua_lie_biao = [];
  List<MedicationLog> _logs = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: Text('${widget.elderName}的药箱')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _jia_zai_zhong
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(18, 2, 18, 28),
                children: [
                  _buildOverview(),
                  const SizedBox(height: 10),
                  _buildMedicines(),
                  const SizedBox(height: 10),
                  _buildSchedules(),
                  const SizedBox(height: 10),
                  _buildLogs(),
                ],
              ),
      ),
    );
  }

  Widget _buildOverview() {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 15),
      decoration: BoxDecoration(
        gradient: AppGradients.hero,
        borderRadius: BorderRadius.circular(27),
        boxShadow: AppShadows.blue,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AppAvatar(
                size: 66,
                icon: Icons.elderly_rounded,
                tint: Colors.white.withValues(alpha: 0.9),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.elderName,
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text('今天也要按时吃药', style: TextStyle(fontSize: 14, color: Colors.white70)),
                  ],
                ),
              ),
              const AppPill(
                label: '守护中',
                background: Color(0x33FFFFFF),
                foreground: Colors.white,
                borderColor: Color(0x55FFFFFF),
                fontSize: 11,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _OverviewStat(value: '${_yao_pin_lie_biao.length}', label: '药品'),
              _OverviewStat(value: '${_yong_yao_ji_hua_lie_biao.length}', label: '提醒'),
              _OverviewStat(value: '${_logs.length}', label: '记录'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMedicines() {
    return _section(
      title: '药品',
      action: TextButton.icon(
        onPressed: () => Navigator.of(context).push(
          ElderPageRoute(
            page: AIRecognizeScreen(elderId: widget.elderId, onSuccess: _load),
          ),
        ),
        icon: const Icon(Icons.camera_alt_rounded),
        label: const Text('帮老人加药'),
      ),
      child: _yao_pin_lie_biao.isEmpty
          ? const Text('老人还没有录入药品。', style: TextStyle(color: ElderTheme.textSecondary))
          : Column(
              children: _yao_pin_lie_biao
                  .map(
                    (medicine) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.medication_rounded, color: ElderTheme.primaryColor),
                      title: Text(medicine.name),
                      subtitle: Text(medicine.dosage ?? medicine.category ?? '未填写用法'),
                    ),
                  )
                  .toList(),
            ),
    );
  }

  Widget _buildSchedules() {
    return _section(
      title: '服药提醒',
      action: TextButton.icon(
        onPressed: () => Navigator.of(context)
            .push(ElderPageRoute(page: AddScheduleScreen(elderId: widget.elderId)))
            .then((_) => _load()),
        icon: const Icon(Icons.add_alarm_rounded),
        label: const Text('添加提醒'),
      ),
      child: _yong_yao_ji_hua_lie_biao.isEmpty
          ? const Text('还没有提醒计划。', style: TextStyle(color: ElderTheme.textSecondary))
          : Column(
              children: _yong_yao_ji_hua_lie_biao
                  .map(
                    (schedule) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.alarm_rounded, color: ElderTheme.successColor),
                      title: Text(schedule.yao_pin_ming_cheng ?? '药品'),
                      subtitle: Text(
                        '${schedule.ti_xing_shi_jian.substring(0, 5)}  ${schedule.dose ?? ''}',
                      ),
                    ),
                  )
                  .toList(),
            ),
    );
  }

  Widget _buildLogs() {
    return _section(
      title: '最近服药记录',
      child: _logs.isEmpty
          ? const Text('暂无服药记录。', style: TextStyle(color: ElderTheme.textSecondary))
          : Column(
              children: _logs
                  .take(8)
                  .map(
                    (log) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(
                        Icons.check_circle_rounded,
                        color: ElderTheme.successColor,
                      ),
                      title: Text(log.yao_pin_ming_cheng ?? '药品 ${log.yao_pin_bian_hao}'),
                      subtitle: Text(
                        log.actualTime?.toString().substring(0, 16) ??
                            log.plannedTime.toString().substring(0, 16),
                      ),
                    ),
                  )
                  .toList(),
            ),
    );
  }

  Widget _section({required String title, required Widget child, Widget? action}) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
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
              if (action != null) action,
            ],
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }

  Widget _card({required Widget child}) {
    return AppGlassCard(
      radius: 24,
      padding: const EdgeInsets.fromLTRB(15, 14, 15, 12),
      child: child,
    );
  }

  Future<void> _load() async {
    setState(() => _jia_zai_zhong = true);
    try {
      final result = await Future.wait([
        ApiService.getMedicines(elderId: widget.elderId),
        ApiService.getSchedules(elderId: widget.elderId),
        ApiService.getHistory(widget.elderId),
      ]);
      if (!mounted) return;
      setState(() {
        _yao_pin_lie_biao = result[0] as List<Medicine>;
        _yong_yao_ji_hua_lie_biao = result[1] as List<Schedule>;
        _logs = result[2] as List<MedicationLog>;
        _jia_zai_zhong = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _jia_zai_zhong = false);
    }
  }
}

class _OverviewStat extends StatelessWidget {
  const _OverviewStat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white),
          ),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.white70)),
        ],
      ),
    );
  }
}
