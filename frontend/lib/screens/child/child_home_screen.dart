import 'package:flutter/material.dart';

import '../../core/alert_text.dart';
import '../../core/theme.dart';
import '../../models/medicine.dart';
import '../../services/api_service.dart';
import '../../services/notification_service.dart';
import '../common/alert_center_screen.dart';
import '../elder/add_schedule_screen.dart';
import '../elder/ai_recognize_screen.dart';
import '../elder/medicine_list_screen.dart';
import '../elder/schedule_list_screen.dart';
import '../elder/voice_assistant_screen.dart';
import 'bind_elder_screen.dart';
import 'child_elder_detail_screen.dart';
import 'child_profile_screen.dart';






class ChildHomeScreen extends StatefulWidget {
  const ChildHomeScreen({super.key});

  @override
  State<ChildHomeScreen> createState() => _ChildHomeScreenState();
}

class _ChildHomeScreenState extends State<ChildHomeScreen>
    with WidgetsBindingObserver {
  bool _jia_zai_zhong = true;
  int _dang_qian_biao_qian = 0; 

  List<Medicine> _myMedicines = <Medicine>[];
  List<Schedule> _mySchedules = <Schedule>[];
  List<MedicineAlert> _myAlerts = <MedicineAlert>[];
  TodaySummary? _myToday;

  int? _elderId;
  String? _elderName;
  List<Medicine> _elderMedicines = <Medicine>[];
  List<Schedule> _elderSchedules = <Schedule>[];
  List<MedicineAlert> _elderAlerts = <MedicineAlert>[];
  TodaySummary? _elderToday;

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
    setState(() => _jia_zai_zhong = true);
    try {
      Map<String, dynamic> family = <String, dynamic>{};
      try {
        family = await ApiService.getMyFamily();
      } catch (_) {
        
      }
      final elders = (family['elders'] as List?) ?? const [];
      final elder = elders.isEmpty ? null : Map<String, dynamic>.from(elders.first as Map);
      final elderId = elder == null ? null : int.tryParse('${elder['id']}');

      final mine = await Future.wait<Object>([
        ApiService.getMedicines(),
        ApiService.getSchedules(),
        ApiService.getTodayLogs(),
        ApiService.getAlerts(),
      ]);

      List<Medicine> elderMedicines = <Medicine>[];
      List<Schedule> elderSchedules = <Schedule>[];
      List<MedicineAlert> elderAlerts = <MedicineAlert>[];
      TodaySummary? elderToday;
      if (elderId != null) {
        final theirs = await Future.wait<Object>([
          ApiService.getMedicines(elderId: elderId),
          ApiService.getSchedules(elderId: elderId),
          ApiService.getTodayLogs(elderId: elderId),
          ApiService.getAlerts(elderId: elderId),
        ]);
        elderMedicines = theirs[0] as List<Medicine>;
        elderSchedules = theirs[1] as List<Schedule>;
        elderToday = theirs[2] as TodaySummary;
        elderAlerts = theirs[3] as List<MedicineAlert>;
      }

      try {
        await NotificationService.instance.notifyGuardianAlerts(elderAlerts, today: elderToday);
      } catch (_) {
        
      }

      if (!mounted) return;
      setState(() {
        _myMedicines = mine[0] as List<Medicine>;
        _mySchedules = mine[1] as List<Schedule>;
        _myToday = mine[2] as TodaySummary;
        _myAlerts = mine[3] as List<MedicineAlert>;
        _elderId = elderId;
        _elderName = elder?['nickname']?.toString() ?? (elderId == null ? null : '老人');
        _elderMedicines = elderMedicines;
        _elderSchedules = elderSchedules;
        _elderToday = elderToday;
        _elderAlerts = elderAlerts;
        _jia_zai_zhong = false;
      });

      try {
        await NotificationService.instance.syncMedicationSchedules(
          mine[1] as List<Schedule>,
          today: mine[2] as TodaySummary,
        );
      } catch (_) {
        
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _jia_zai_zhong = false);
    }
  }

  void _open(Widget page) {
    Navigator.of(context).push(ElderPageRoute(page: page)).then((_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ElderTheme.bgColor,
      appBar: AppBar(
        title: Text(_dang_qian_biao_qian == 0
            ? '我的用药'
            : _dang_qian_biao_qian == 1
                ? '${_elderName ?? '老人'}的用药'
                : '家属中心'),
        actions: [
          if (_dang_qian_biao_qian != 2)
            IconButton(
              tooltip: '家属中心',
              onPressed: () => setState(() => _dang_qian_biao_qian = 2),
              icon: const Icon(Icons.person_rounded),
            ),
        ],
      ),
      body: IndexedStack(
        index: _dang_qian_biao_qian,
        children: [
          _buildMineTab(),
          _buildElderTab(),
          const ChildProfileScreen(showAppBar: false),
        ],
      ),
      
      bottomNavigationBar: NavigationBar(
        selectedIndex: _dang_qian_biao_qian,
        onDestinationSelected: (index) => setState(() => _dang_qian_biao_qian = index),
        height: 78,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.medication_outlined, size: 28),
            selectedIcon: Icon(Icons.medication, size: 28),
            label: '我的用药',
          ),
          NavigationDestination(
            icon: Icon(Icons.elderly_outlined, size: 28),
            selectedIcon: Icon(Icons.elderly, size: 28),
            label: '老人用药',
          ),
          NavigationDestination(
            icon: Icon(Icons.account_circle_outlined, size: 28),
            selectedIcon: Icon(Icons.account_circle, size: 28),
            label: '家属中心',
          ),
        ],
      ),
    );
  }

  

  Widget _buildMineTab() {
    if (_jia_zai_zhong) return const Center(child: CircularProgressIndicator());
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _todayCard(
            title: '我今日服药',
            today: _myToday,
            schedules: _mySchedules,
          ),
          const SizedBox(height: 12),
          _statsRow(
            medicines: _myMedicines,
            schedules: _mySchedules,
            alerts: _myAlerts,
            onMedicines: () => _open(const MedicineListScreen()),
            onSchedules: () => _open(const ScheduleListScreen()),
            onAlerts: () => _open(const AlertCenterScreen()),
          ),
          const SizedBox(height: 12),
          _alertCard(
            alerts: _myAlerts,
            medicines: _myMedicines,
            onOpenAll: () => _open(const AlertCenterScreen()),
          ),
          const SizedBox(height: 16),
          _actionGrid([
            _action('拍照识药', Icons.camera_alt, () => _open(const AIRecognizeScreen())),
            _action('用药计划', Icons.list_alt, () => _open(const ScheduleListScreen())),
            _action('添加计划', Icons.add_alarm, () => _open(const AddScheduleScreen())),
            _action('药品管理', Icons.inventory_2, () => _open(const MedicineListScreen())),
            _action('语音助手', Icons.mic, () => _open(const VoiceAssistantScreen())),
          ]),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  

  Widget _buildElderTab() {
    if (_jia_zai_zhong) return const Center(child: CircularProgressIndicator());
    final elderId = _elderId;
    if (elderId == null) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  const Icon(Icons.family_restroom, size: 54, color: ElderTheme.primaryColor),
                  const SizedBox(height: 12),
                  const Text('还没有绑定老人', style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text(
                    '请老人先在「我的 → 绑定家属」里生成邀请码，再回到这里输入邀请码完成绑定。',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16, color: ElderTheme.textSecondary, height: 1.4),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () => _open(const BindElderScreen()),
                    icon: const Icon(Icons.link_rounded),
                    label: const Text('去绑定老人'),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _todayCard(
            title: '${_elderName ?? '老人'}今日服药',
            today: _elderToday,
            schedules: _elderSchedules,
          ),
          const SizedBox(height: 12),
          _statsRow(
            medicines: _elderMedicines,
            schedules: _elderSchedules,
            alerts: _elderAlerts,
            onMedicines: () => _open(MedicineListScreen(elderId: elderId)),
            onSchedules: () => _open(ScheduleListScreen(elderId: elderId, title: '${_elderName ?? '老人'}的用药计划')),
            onAlerts: () => _open(const AlertCenterScreen(title: '家人提醒')),
          ),
          const SizedBox(height: 12),
          _alertCard(
            alerts: _elderAlerts,
            medicines: _elderMedicines,
            onOpenAll: () => _open(const AlertCenterScreen(title: '家人提醒')),
          ),
          const SizedBox(height: 16),
          _actionGrid([
            _action('拍照识药', Icons.camera_alt, () => _open(AIRecognizeScreen(elderId: elderId))),
            _action('用药计划', Icons.list_alt, () => _open(ScheduleListScreen(elderId: elderId, title: '${_elderName ?? '老人'}的用药计划'))),
            _action('添加计划', Icons.add_alarm, () => _open(AddScheduleScreen(elderId: elderId))),
            _action('药品管理', Icons.inventory_2, () => _open(MedicineListScreen(elderId: elderId))),
            _action('查看药箱', Icons.visibility, () => _open(ChildElderDetailScreen(elderId: elderId, elderName: _elderName ?? '老人'))),
          ]),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  

  Widget _todayCard({
    required String title,
    required TodaySummary? today,
    required List<Schedule> schedules,
  }) {
    final total = today?.total ?? schedules.length;
    final taken = today?.taken ?? 0;
    final pending = today?.pending ?? 0;
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: const Icon(Icons.today, size: 36, color: ElderTheme.primaryColor),
        title: Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
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

  Widget _statsRow({
    required List<Medicine> medicines,
    required List<Schedule> schedules,
    required List<MedicineAlert> alerts,
    required VoidCallback onMedicines,
    required VoidCallback onSchedules,
    required VoidCallback onAlerts,
  }) {
    return Row(
      children: [
        Expanded(child: _stat('药品', '${medicines.length}', Icons.medication, ElderTheme.infoColor, onMedicines)),
        Expanded(child: _stat('计划', '${schedules.length}', Icons.alarm, ElderTheme.successColor, onSchedules)),
        Expanded(child: _stat('告警', '${alerts.length}', Icons.warning, ElderTheme.warningColor, onAlerts)),
      ],
    );
  }

  Widget _stat(String label, String value, IconData icon, Color color, VoidCallback onTap) {
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
              Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color)),
              Text(label, style: const TextStyle(fontSize: 16, color: ElderTheme.textSecondary)),
            ],
          ),
        ),
      ),
    );
  }

  
  Widget _alertCard({
    required List<MedicineAlert> alerts,
    required List<Medicine> medicines,
    required VoidCallback onOpenAll,
  }) {
    if (alerts.isEmpty) return const SizedBox.shrink();
    final info = describeAlert(alerts.first, medicines);
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: Icon(info.icon, size: 32, color: info.color),
        title: const Text('用药提醒', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(alerts.length > 1 ? '${info.title} 等 ${alerts.length} 条' : info.title),
        ),
        trailing: const Icon(Icons.chevron_right, size: 30),
        onTap: onOpenAll,
      ),
    );
  }

  Widget _action(String text, IconData icon, VoidCallback onTap) {
    return _ActionItem(text: text, icon: icon, onTap: onTap);
  }

  Widget _actionGrid(List<Widget> items) {
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      children: items,
    );
  }
}

class _ActionItem extends StatelessWidget {
  const _ActionItem({required this.text, required this.icon, required this.onTap});

  final String text;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
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