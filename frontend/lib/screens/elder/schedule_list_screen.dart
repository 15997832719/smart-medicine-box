import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../models/medicine.dart';
import '../../services/api_service.dart';
import '../../services/notification_service.dart';
import 'add_schedule_screen.dart';



class ScheduleListScreen extends StatefulWidget {
  const ScheduleListScreen({super.key, this.elderId, this.title});

  final int? elderId;
  final String? title;

  @override
  State<ScheduleListScreen> createState() => _ScheduleListScreenState();
}

class _ScheduleListScreenState extends State<ScheduleListScreen> {
  late Future<List<Schedule>> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      _future = ApiService.getSchedules(elderId: widget.elderId);
    });
  }

  String _dateText(Schedule schedule) {
    final date = schedule.ji_hua_ri_qi;
    if (date == null) return '每天';
    return '${date.year}年${date.month}月${date.day}日';
  }

  Future<void> _delete(Schedule schedule) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除用药计划'),
        content: Text('确定删除“${schedule.yao_pin_ming_cheng ?? '药品'}”这条计划吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ApiService.deleteSchedule(schedule.id, elderId: widget.elderId);
      if (widget.elderId == null) {
        final schedules = await ApiService.getSchedules();
        await NotificationService.instance.syncMedicationSchedules(schedules);
      }
      if (!mounted) return;
      _reload();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('用药计划已删除')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('删除失败：$e')),
      );
    }
  }

  void _edit(Schedule schedule) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddScheduleScreen(
          elderId: widget.elderId,
          schedule: schedule,
        ),
      ),
    ).then((_) => _reload());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ElderTheme.bgColor,
      appBar: AppBar(
        title: Text(widget.title ?? '我的用药计划'),
        actions: [
          IconButton(
            tooltip: '添加计划',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => AddScheduleScreen(elderId: widget.elderId)),
            ).then((_) => _reload()),
            icon: const Icon(Icons.add_alarm),
          ),
        ],
      ),
      body: FutureBuilder<List<Schedule>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final schedules = snapshot.data ?? const <Schedule>[];
          if (schedules.isEmpty) {
            return const Center(
              child: Text('暂无用药计划', style: TextStyle(fontSize: 18, color: ElderTheme.textSecondary)),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: schedules.length,
            itemBuilder: (context, index) {
              final schedule = schedules[index];
              return Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  leading: const Icon(Icons.alarm, color: ElderTheme.primaryColor, size: 30),
                  title: Text(
                    schedule.yao_pin_ming_cheng ?? '药品',
                    style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '${_dateText(schedule)}  ${schedule.ti_xing_shi_jian}  ${schedule.dose ?? ''}',
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                  onTap: () => _edit(schedule),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: '编辑计划',
                        onPressed: () => _edit(schedule),
                        icon: const Icon(Icons.edit_rounded),
                      ),
                      IconButton(
                        tooltip: '删除计划',
                        onPressed: () => _delete(schedule),
                        icon: const Icon(Icons.delete_outline_rounded),
                        color: ElderTheme.errorColor,
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}