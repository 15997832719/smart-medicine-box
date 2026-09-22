import 'package:flutter/material.dart';

import '../../core/alert_text.dart';
import '../../core/theme.dart';
import '../../models/medicine.dart';
import '../../services/api_service.dart';
import '../../services/notification_service.dart';
import '../auth/login_screen.dart';
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

class _ElderHomeScreenState extends State<ElderHomeScreen>
    with WidgetsBindingObserver {
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
        await NotificationService.instance.syncMedicationSchedules(
          schedules,
          today: today,
        );
      } catch (_) {
        
      }
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
      appBar: AppBar(
        title: Text(_tabIndex == 0 ? '智能药盒' : '我的'),
        actions: _tabIndex == 0
            ? [
                IconButton(
                  tooltip: '绑定子女',
                  onPressed: () => _open(const ElderBindChildScreen()),
                  icon: const Icon(Icons.family_restroom),
                ),
                IconButton(
                  tooltip: '切换账号',
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                  ),
                  icon: const Icon(Icons.swap_horiz),
                ),
              ]
            : null,
      ),
      body: IndexedStack(
        index: _tabIndex,
        children: [
          _buildHomeTab(),
          const ElderProfileScreen(showAppBar: false),
        ],
      ),
      
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: _onTabSelected,
        height: 78,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined, size: 30),
            selectedIcon: Icon(Icons.home, size: 30),
            label: '首页',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline, size: 30),
            selectedIcon: Icon(Icons.person, size: 30),
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
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildTodayCard(),
          const SizedBox(height: 12),
          _buildStatsRow(),
          const SizedBox(height: 12),
          if (_yong_yao_ji_hua_lie_biao.isNotEmpty) _buildNextReminderCard(),
          if (_jing_gao_lie_biao.isNotEmpty) _buildAlertCard(),
          const SizedBox(height: 16),
          _buildActionGrid(),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  
  Widget _buildTodayCard() {
    final total = _today?.total ?? _yong_yao_ji_hua_lie_biao.length;
    final taken = _today?.taken ?? 0;
    final pending = _today?.pending ?? 0;
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: const Icon(Icons.today, size: 36, color: ElderTheme.primaryColor),
        title: const Text(
          '今日服药',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text('共 $total 项，已完成 $taken 项，待确认 $pending 项'),
        ),
        trailing: pending > 0
            ? const Icon(Icons.warning_amber_rounded, color: ElderTheme.warningColor, size: 34)
            : const Icon(Icons.check_circle, color: ElderTheme.successColor, size: 34),
        onTap: null,
      ),
    );
  }

  
  Widget _buildStatsRow() {
    return Row(
      children: [
        Expanded(
          child: _buildStatItem(
            label: '药品',
            value: '${_yao_pin_lie_biao.length}',
            icon: Icons.medication,
            color: ElderTheme.infoColor,
            onTap: () => _open(const MedicineListScreen()),
          ),
        ),
        Expanded(
          child: _buildStatItem(
            label: '计划',
            value: '${_yong_yao_ji_hua_lie_biao.length}',
            icon: Icons.alarm,
            color: ElderTheme.successColor,
            onTap: () => _open(const ScheduleListScreen()),
          ),
        ),
        Expanded(
          child: _buildStatItem(
            label: '告警',
            value: '${_jing_gao_lie_biao.length}',
            icon: Icons.warning,
            color: ElderTheme.warningColor,
            onTap: () => _open(const AlertCenterScreen()),
          ),
        ),
      ],
    );
  }

  Widget _buildStatItem({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
    VoidCallback? onTap,
  }) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Column(
            children: [
              Icon(icon, color: color, size: 30),
              const SizedBox(height: 6),
              Text(
                value,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color),
              ),
              Text(label, style: const TextStyle(fontSize: 16, color: ElderTheme.textSecondary)),
            ],
          ),
        ),
      ),
    );
  }

  
  Widget _buildNextReminderCard() {
    final schedule = _yong_yao_ji_hua_lie_biao.first;
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: const Icon(Icons.schedule, size: 32, color: ElderTheme.primaryColor),
        title: const Text(
          '下一次提醒',
          style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            '${schedule.ti_xing_shi_jian}  ${schedule.yao_pin_ming_cheng ?? '药品'}  ${schedule.dose ?? ''}',
          ),
        ),
        onTap: null,
      ),
    );
  }

  
  Widget _buildAlertCard() {
    final info = describeAlert(_jing_gao_lie_biao.first, _yao_pin_lie_biao);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Card(
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          leading: Icon(info.icon, size: 32, color: info.color),
          title: const Text(
            '用药提醒',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              _jing_gao_lie_biao.length > 1 ? '${info.title} 等 ${_jing_gao_lie_biao.length} 条' : info.title,
            ),
          ),
          trailing: const Icon(Icons.chevron_right, size: 30),
          onTap: () => _open(const AlertCenterScreen()),
        ),
      ),
    );
  }
  
  Widget _buildActionGrid() {
    final items = <Widget>[
      _buildActionCard('拍照识药', Icons.camera_alt, () => _open(const AIRecognizeScreen())),
      _buildActionCard('用药计划', Icons.list_alt, () => _open(const ScheduleListScreen())),
      _buildActionCard('添加计划', Icons.add_alarm, () => _open(const AddScheduleScreen())),
      _buildActionCard('药品管理', Icons.inventory_2, () => _open(const MedicineListScreen())),
      _buildActionCard('语音助手', Icons.mic, () => _open(const VoiceAssistantScreen())),
    ];
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      children: items,
    );
  }

  Widget _buildActionCard(String text, IconData icon, VoidCallback onTap) {
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(ElderTheme.cardRadius),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 38, color: ElderTheme.primaryColor),
            const SizedBox(height: 8),
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}