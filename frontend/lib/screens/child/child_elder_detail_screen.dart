import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../models/medicine.dart';
import '../../services/api_service.dart';
import '../elder/add_schedule_screen.dart';
import '../elder/ai_recognize_screen.dart';

class ChildElderDetailScreen extends StatefulWidget {
  final int elderId;
  final String elderName;

  const ChildElderDetailScreen({
    super.key,
    required this.elderId,
    required this.elderName,
  });

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
      backgroundColor: ElderTheme.bgColor,
      appBar: AppBar(title: Text('${widget.elderName}的药箱')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _jia_zai_zhong
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildOverview(),
                  const SizedBox(height: 14),
                  _buildMedicines(),
                  const SizedBox(height: 14),
                  _buildSchedules(),
                  const SizedBox(height: 14),
                  _buildLogs(),
                ],
              ),
      ),
    );
  }

  Widget _buildOverview() {
    return _card(
      child: Row(
        children: [
          const CircleAvatar(
            radius: 28,
            backgroundColor: Color(0xFFEAF5FF),
            child: Icon(Icons.elderly_rounded, color: ElderTheme.primaryColor, size: 34),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.elderName, style: const TextStyle(fontSize: 23, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text('药品 ${_yao_pin_lie_biao.length} 种，提醒 ${_yong_yao_ji_hua_lie_biao.length} 条，记录 ${_logs.length} 条',
                    style: const TextStyle(color: ElderTheme.textSecondary)),
              ],
            ),
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
          ElderPageRoute(page: AIRecognizeScreen(elderId: widget.elderId, onSuccess: _load)),
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
        onPressed: () => Navigator.of(context).push(ElderPageRoute(page: const AddScheduleScreen())).then((_) => _load()),
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
                      subtitle: Text('${schedule.ti_xing_shi_jian.substring(0, 5)}  ${schedule.dose ?? ''}'),
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
                      leading: const Icon(Icons.check_circle_rounded, color: ElderTheme.successColor),
                      title: Text(log.yao_pin_ming_cheng ?? '药品 ${log.yao_pin_bian_hao}'),
                      subtitle: Text(log.actualTime?.toString().substring(0, 16) ?? log.plannedTime.toString().substring(0, 16)),
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
              Expanded(child: Text(title, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold))),
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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ElderTheme.cardColor,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 12, offset: const Offset(0, 5))],
      ),
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
