import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/alert_text.dart';
import '../../core/auth_service.dart';
import '../../core/design_system.dart';
import '../../models/medicine.dart';
import '../../services/api_service.dart';
import '../../services/notification_service.dart';
import '../common/alert_center_screen.dart';
import 'add_schedule_screen.dart';
import 'ai_recognize_screen.dart';
import 'elder_bind_child_screen.dart';
import 'elder_profile_screen.dart';
import 'medicine_list_screen.dart';
import 'schedule_list_screen.dart';
import 'voice_assistant_screen.dart';

class ElderHomeScreen extends StatefulWidget {
  const ElderHomeScreen({super.key});

  @override
  State<ElderHomeScreen> createState() => _ElderHomeScreenState();
}

class _ElderHomeScreenState extends State<ElderHomeScreen> with WidgetsBindingObserver {
  List<Medicine> _yao_pin_lie_biao = <Medicine>[];
  List<Schedule> _yong_yao_ji_hua_lie_biao = <Schedule>[];
  List<MedicineAlert> _jing_gao_lie_biao = <MedicineAlert>[];
  TodaySummary? _today;
  bool _jia_zai_zhong = true;
  int _tabIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait<Object>([
        ApiService.getMedicines(),
        ApiService.getSchedules(),
        ApiService.getTodayLogs(),
        ApiService.getAlerts(),
      ]);
      final schedules = results[1] as List<Schedule>;
      final today = results[2] as TodaySummary;
      if (!mounted) return;
      setState(() {
        _yao_pin_lie_biao = results[0] as List<Medicine>;
        _yong_yao_ji_hua_lie_biao = schedules;
        _today = today;
        _jing_gao_lie_biao = results[3] as List<MedicineAlert>;
        _jia_zai_zhong = false;
      });

      try {
        await NotificationService.instance.syncMedicationSchedules(schedules, today: today);
      } catch (_) {}
    } catch (_) {
      if (!mounted) return;
      setState(() => _jia_zai_zhong = false);
    }
  }

  void _open(Widget page) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => page)).then((_) => _load());
  }

  void _onTabSelected(int index) {
    setState(() => _tabIndex = index);
    if (index == 0) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: IndexedStack(
          index: _tabIndex,
          children: [_buildHomeTab(), const ElderProfileScreen(showAppBar: false)],
        ),
      ),
      bottomNavigationBar: AppFloatingNavBar(
        currentIndex: _tabIndex,
        onTap: _onTabSelected,
        largeText: true,
        items: const [
          AppNavItem(icon: Icons.home_outlined, selectedIcon: Icons.home_rounded, label: '首页'),
          AppNavItem(
            icon: Icons.person_outline_rounded,
            selectedIcon: Icons.person_rounded,
            label: '我的',
          ),
        ],
      ),
    );
  }

  Widget _buildHomeTab() {
    if (_jia_zai_zhong) {
      return const Center(child: CircularProgressIndicator());
    }
    final user = context.watch<AuthService>().dang_qian_yong_hu;
    final total = _today?.total ?? _yong_yao_ji_hua_lie_biao.length;
    final taken = _today?.taken ?? 0;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 118),
        children: [
          _HomeHero(
            name: user?.nickname?.trim().isNotEmpty == true ? user!.nickname! : '陈爷爷',
            total: total,
            taken: taken,
            alertCount: _jing_gao_lie_biao.length,
            onBindFamily: () => _open(const ElderBindChildScreen()),
            onAlerts: () => _open(const AlertCenterScreen()),
          ),
          const SizedBox(height: 14),
          _buildStatsRow(),
          const SizedBox(height: 12),
          if (_yong_yao_ji_hua_lie_biao.isNotEmpty) _buildNextReminderCard(),
          if (_jing_gao_lie_biao.isNotEmpty) _buildAlertCard(),
          const SizedBox(height: 12),
          _buildActionGrid(),
        ],
      ),
    );
  }

  Widget _buildStatsRow() {
    return Row(
      children: [
        Expanded(
          child: _StatTile(
            value: '${_yao_pin_lie_biao.length}',
            label: '药品',
            onTap: () => _open(const MedicineListScreen()),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatTile(
            value: '${_yong_yao_ji_hua_lie_biao.length}',
            label: '计划',
            onTap: () => _open(const ScheduleListScreen()),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatTile(
            value: '${_jing_gao_lie_biao.length}',
            label: '告警',
            onTap: () => _open(const AlertCenterScreen()),
          ),
        ),
      ],
    );
  }

  Widget _buildNextReminderCard() {
    final schedule = _yong_yao_ji_hua_lie_biao.first;
    return AppGlassCard(
      radius: 27,
      margin: const EdgeInsets.only(top: 2, bottom: 4),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Row(
        children: [
          const AppIconTile(
            icon: Icons.medication_rounded,
            size: 58,
            iconSize: 30,
            background: AppColors.mintTint,
            color: AppColors.mintDeep,
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.location_on_rounded, size: 20, color: AppColors.blue),
                    SizedBox(width: 4),
                    Text(
                      '下一次提醒',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink2,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  schedule.ti_xing_shi_jian,
                  style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                    color: AppColors.ink,
                    height: 1.1,
                  ),
                ),
                Text(
                  '${schedule.yao_pin_ming_cheng ?? '药品'} · ${schedule.dose ?? '按计划服用'}',
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    color: AppColors.muted,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 58,
            height: 58,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 58,
                  height: 58,
                  child: CircularProgressIndicator(
                    value: 0.76,
                    strokeWidth: 5,
                    strokeCap: StrokeCap.round,
                    backgroundColor: const Color(0xFFDFF3EF),
                    valueColor: const AlwaysStoppedAnimation<Color>(AppColors.mintDeep),
                  ),
                ),
                const Icon(Icons.check_rounded, size: 27, color: AppColors.mintDeep),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAlertCard() {
    final info = describeAlert(_jing_gao_lie_biao.first, _yao_pin_lie_biao);
    return AppGlassCard(
      margin: const EdgeInsets.only(top: 2, bottom: 2),
      radius: 22,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      onTap: () => _open(const AlertCenterScreen()),
      child: Row(
        children: [
          AppIconTile(
            icon: info.icon,
            size: 46,
            iconSize: 24,
            background: AppColors.mintTint,
            color: info.color,
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              _jing_gao_lie_biao.length > 1
                  ? '${info.title} 等 ${_jing_gao_lie_biao.length} 条'
                  : info.title,
              style: const TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                color: AppColors.ink2,
                height: 1.35,
              ),
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: Color(0xFFE0954A), size: 26),
        ],
      ),
    );
  }

  Widget _buildActionGrid() {
    final ownerId = Provider.of<AuthService>(context, listen: false).dang_qian_yong_hu?.id;
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _HomeActionTile(
                icon: Icons.camera_alt_rounded,
                title: '拍照识药',
                background: const LinearGradient(colors: [Color(0xFFEFFCFF), Color(0xFFD7F4FF)]),
                iconGradient: AppGradients.primaryButton,
                onTap: () => _open(const AIRecognizeScreen()),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _HomeActionTile(
                icon: Icons.calendar_month_rounded,
                title: '用药计划',
                background: const LinearGradient(colors: [Color(0xFFF0FFF8), Color(0xFFD9F8EE)]),
                iconGradient: const LinearGradient(colors: [Color(0xFF70E7C7), Color(0xFF35BDA1)]),
                onTap: () => _open(const ScheduleListScreen()),
              ),
            ),
          ],
        ),
        const SizedBox(height: 9),
        Row(
          children: [
            Expanded(
              child: _HomeActionTile(
                icon: Icons.add_alarm_rounded,
                title: '添加计划',
                background: const LinearGradient(colors: [Color(0xFFFFFAF4), Color(0xFFFFEBD7)]),
                iconGradient: const LinearGradient(colors: [Color(0xFFFFD2A7), Color(0xFFF2A657)]),
                iconColor: const Color(0xFFC9752A),
                onTap: () => _open(const AddScheduleScreen()),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _HomeActionTile(
                icon: Icons.medication_liquid_rounded,
                title: '药品管理',
                background: const LinearGradient(colors: [Color(0xFFFAF8FF), Color(0xFFEDE7FF)]),
                iconGradient: const LinearGradient(colors: [Color(0xFFD6C8FF), Color(0xFFA78BFA)]),
                iconColor: const Color(0xFF6D53C8),
                onTap: () => _open(const MedicineListScreen()),
              ),
            ),
          ],
        ),
        const SizedBox(height: 9),
        _HomeActionTile(
          icon: Icons.mic_rounded,
          title: '语音助手',
          background: const LinearGradient(colors: [Color(0xFFEFFBFF), Color(0xFFDFEEFF)]),
          iconGradient: AppGradients.primaryButton,
          wide: true,
          onTap: () => _open(VoiceAssistantScreen(ownerId: ownerId, ownerLabel: '我的药箱')),
        ),
      ],
    );
  }
}

class _HomeHero extends StatelessWidget {
  const _HomeHero({
    required this.name,
    required this.total,
    required this.taken,
    required this.alertCount,
    required this.onBindFamily,
    required this.onAlerts,
  });

  final String name;
  final int total;
  final int taken;
  final int alertCount;
  final VoidCallback onBindFamily;
  final VoidCallback onAlerts;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 2),
      padding: const EdgeInsets.fromLTRB(22, 20, 20, 26),
      decoration: BoxDecoration(
        gradient: AppGradients.hero,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(36)),
        boxShadow: AppShadows.blue,
      ),
      child: Stack(
        children: [
          Positioned(
            right: -56,
            top: -78,
            child: Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '早上好，$name',
                          style: const TextStyle(
                            fontSize: 17,
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          '智能药箱',
                          style: TextStyle(
                            fontSize: 38,
                            height: 1.16,
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -1,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          total > 0 ? '今天 $total 项用药 · 已完成 $taken 项' : '今天也要按时吃药哦',
                          style: TextStyle(
                            fontSize: 17,
                            color: Colors.white.withValues(alpha: 0.92),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Row(
                    children: [
                      _HeroAction(icon: Icons.family_restroom_rounded, onTap: onBindFamily),
                      const SizedBox(width: 8),
                      _HeroAction(
                        icon: Icons.notifications_rounded,
                        onTap: onAlerts,
                        badge: alertCount > 0,
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroAction extends StatelessWidget {
  const _HeroAction({required this.icon, required this.onTap, this.badge = false});

  final IconData icon;
  final VoidCallback onTap;
  final bool badge;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.16),
      borderRadius: BorderRadius.circular(17),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(17),
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(17),
            border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 25),
              if (badge)
                Positioned(
                  right: 7,
                  top: 7,
                  child: Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF8A8A),
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFF4B9BF1), width: 1.5),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.value, required this.label, required this.onTap});

  final String value;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppGlassCard(
      radius: 24,
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      onTap: onTap,
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              fontSize: 44,
              height: 1.05,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
              letterSpacing: -1.5,
            ),
          ),
          const SizedBox(height: 9),
          Text(
            label,
            style: const TextStyle(
              fontSize: 23,
              fontWeight: FontWeight.w800,
              color: Color(0xFF31597F),
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeActionTile extends StatelessWidget {
  const _HomeActionTile({
    required this.icon,
    required this.title,
    required this.background,
    required this.iconGradient,
    required this.onTap,
    this.iconColor = Colors.white,
    this.wide = false,
  });

  final IconData icon;
  final String title;
  final Gradient background;
  final Gradient iconGradient;
  final Color iconColor;
  final VoidCallback onTap;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(23),
        child: Container(
          height: wide ? 76 : 82,
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
          decoration: BoxDecoration(
            gradient: background,
            borderRadius: BorderRadius.circular(23),
            border: Border.all(color: Colors.white.withValues(alpha: 0.94)),
            boxShadow: AppShadows.soft,
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: iconGradient,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.7)),
                ),
                child: Icon(icon, color: iconColor, size: 27),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 22,
                    height: 1.22,
                    fontWeight: FontWeight.w900,
                    color: AppColors.ink2,
                  ),
                ),
              ),
              if (wide) const Icon(Icons.chevron_right_rounded, size: 25, color: Color(0xFF5C8FBA)),
            ],
          ),
        ),
      ),
    );
  }
}
