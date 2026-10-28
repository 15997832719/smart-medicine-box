import 'package:flutter/material.dart';

import '../../core/design_system.dart';
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
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('删除')),
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
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('用药计划已删除')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('删除失败：$e')));
    }
  }

  void _edit(Schedule schedule) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            AddScheduleScreen(elderId: widget.elderId, schedule: schedule),
      ),
    ).then((_) => _reload());
  }

  void _add() {
    Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => AddScheduleScreen(elderId: widget.elderId)),
    ).then((_) => _reload());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(widget.title ?? '我的用药计划'),
        actions: [
          IconButton(
              tooltip: '添加计划',
              onPressed: _add,
              icon: const Icon(Icons.add_alarm_rounded)),
          const SizedBox(width: 8),
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
            return ListView(
              padding: const EdgeInsets.fromLTRB(22, 60, 22, 24),
              children: [
                AppGlassCard(
                  radius: 28,
                  padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
                  child: Column(
                    children: [
                      const AppIconTile(
                        icon: Icons.alarm_add_rounded,
                        size: 80,
                        iconSize: 40,
                        background: AppColors.blueTint,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        '暂无用药计划',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          color: AppColors.ink,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '添加计划后，系统会按时提醒你服药。',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 16, color: AppColors.muted, height: 1.5),
                      ),
                      const SizedBox(height: 18),
                      AppGradientButton(
                        label: '添加计划',
                        icon: Icons.add_rounded,
                        height: 54,
                        fontSize: 19,
                        onPressed: _add,
                      ),
                    ],
                  ),
                ),
              ],
            );
          }

          final next = schedules.first;
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 104),
            itemCount: schedules.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.fromLTRB(18, 17, 18, 16),
                      decoration: BoxDecoration(
                        gradient: AppGradients.hero,
                        borderRadius: BorderRadius.circular(27),
                        boxShadow: AppShadows.blue,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '今天要吃的药',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${schedules.length} 项计划',
                            style: const TextStyle(
                              fontSize: 34,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 7),
                          Text(
                            '下一次 ${next.ti_xing_shi_jian} · ${next.yao_pin_ming_cheng ?? '药品'}',
                            style: TextStyle(
                              fontSize: 15,
                              color: Colors.white.withValues(alpha: 0.92),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 13),
                  ],
                );
              }
              final schedule = schedules[index - 1];
              return Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: AppGlassCard(
                  radius: 23,
                  padding: const EdgeInsets.fromLTRB(14, 13, 6, 13),
                  onTap: () => _edit(schedule),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 71,
                        child: Column(
                          children: [
                            Text(
                              schedule.ti_xing_shi_jian,
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                                color: AppColors.ink,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              _dateText(schedule),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14,
                                color: AppColors.muted2,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              schedule.yao_pin_ming_cheng ?? '药品',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: AppColors.ink,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              schedule.dose?.isNotEmpty == true
                                  ? '每次 ${schedule.dose}'
                                  : '按计划服用',
                              style: const TextStyle(
                                fontSize: 17,
                                color: AppColors.muted,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: '编辑计划',
                        onPressed: () => _edit(schedule),
                        icon: const Icon(Icons.edit_rounded,
                            color: Color(0xFF5B91C5), size: 22),
                      ),
                      IconButton(
                        tooltip: '删除计划',
                        onPressed: () => _delete(schedule),
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          color: AppColors.red,
                          size: 22,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(20, 0, 20, 14),
        child: AppGradientButton(
          label: '添加用药计划',
          icon: Icons.add_rounded,
          height: 58,
          fontSize: 20,
          onPressed: _add,
        ),
      ),
    );
  }
}
