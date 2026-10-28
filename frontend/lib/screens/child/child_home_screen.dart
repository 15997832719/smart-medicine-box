import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/alert_text.dart';
import '../../core/auth_service.dart';
import '../../core/design_system.dart';
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

class _ChildHomeScreenState extends State<ChildHomeScreen> with WidgetsBindingObserver {
  bool _jia_zai_zhong = true;
  int _dang_qian_biao_qian = 0;

  List<Medicine> _myMedicines = <Medicine>[];
  List<Schedule> _mySchedules = <Schedule>[];
  List<MedicineAlert> _myAlerts = <MedicineAlert>[];
  TodaySummary? _myToday;

  int? _elderId;
  String? _elderName;
  List<Map<String, dynamic>> _elders = <Map<String, dynamic>>[];
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
      } catch (_) {}
      final elderRows = ((family['elders'] as List?) ?? const [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .where((item) => int.tryParse('${item['id']}') != null)
          .toList();
      int? elderId = _elderId;
      if (!elderRows.any((item) => int.tryParse('${item['id']}') == elderId)) {
        elderId = elderRows.isEmpty ? null : int.tryParse('${elderRows.first['id']}');
      }
      Map<String, dynamic>? elder;
      for (final item in elderRows) {
        if (int.tryParse('${item['id']}') == elderId) {
          elder = item;
          break;
        }
      }

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
      } catch (_) {}

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
      } catch (_) {}
    } catch (_) {
      if (!mounted) return;
      setState(() => _jia_zai_zhong = false);
    }
  }

  Future<void> _chooseElder() async {
    if (_elders.length < 2) return;
    final selected = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(
              title: Text('选择药箱', style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
            ),
            for (final elder in _elders)
              ListTile(
                leading: const Icon(Icons.elderly_rounded, size: 32),
                title: Text(
                  elder['nickname']?.toString() ?? '老人',
                  style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600),
                ),
                trailing: int.tryParse('${elder['id']}') == _elderId
                    ? const Icon(Icons.check_circle_rounded, color: ElderTheme.successColor)
                    : null,
                onTap: () => Navigator.pop(context, int.tryParse('${elder['id']}')),
              ),
          ],
        ),
      ),
    );
    if (selected != null) await _selectElder(selected);
  }

  Future<void> _selectElder(int elderId) async {
    if (elderId == _elderId) return;
    setState(() {
      _elderId = elderId;
      _elderName =
          _elders
              .firstWhere(
                (item) => int.tryParse('${item['id']}') == elderId,
                orElse: () => <String, dynamic>{},
              )['nickname']
              ?.toString() ??
          '老人';
      _elderMedicines = <Medicine>[];
      _elderSchedules = <Schedule>[];
      _elderAlerts = <MedicineAlert>[];
      _elderToday = null;
      _jia_zai_zhong = true;
    });
    await _load();
  }

  Widget _buildTitle() {
    if (_dang_qian_biao_qian == 0) return const Text('我的用药');
    if (_dang_qian_biao_qian == 2) return const Text('家属中心');
    return InkWell(
      onTap: _elders.length > 1 ? _chooseElder : null,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${_elderName ?? '老人'}的用药'),
            if (_elders.length > 1) ...[
              const SizedBox(width: 4),
              const Icon(Icons.expand_more_rounded),
            ],
          ],
        ),
      ),
    );
  }

  void _open(Widget page) {
    Navigator.of(context).push(ElderPageRoute(page: page)).then((_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: _buildTitle(),
        actions: [
          if (_dang_qian_biao_qian == 1 && _elders.length > 1)
            IconButton(
              tooltip: '切换老人',
              onPressed: _chooseElder,
              icon: const Icon(Icons.switch_account_rounded),
            ),
          if (_dang_qian_biao_qian != 2)
            IconButton(
              tooltip: '家属中心',
              onPressed: () => setState(() => _dang_qian_biao_qian = 2),
              icon: const Icon(Icons.person_rounded),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        bottom: false,
        child: IndexedStack(
          index: _dang_qian_biao_qian,
          children: [
            _buildMineTab(),
            _buildElderTab(),
            const ChildProfileScreen(showAppBar: false),
          ],
        ),
      ),
      bottomNavigationBar: AppFloatingNavBar(
        currentIndex: _dang_qian_biao_qian,
        onTap: (index) {
          setState(() => _dang_qian_biao_qian = index);
          if (index == 0 || index == 1) _load();
        },
        items: const [
          AppNavItem(
            icon: Icons.medication_outlined,
            selectedIcon: Icons.medication_rounded,
            label: '我的用药',
          ),
          AppNavItem(
            icon: Icons.elderly_outlined,
            selectedIcon: Icons.elderly_rounded,
            label: '老人用药',
          ),
          AppNavItem(
            icon: Icons.account_circle_outlined,
            selectedIcon: Icons.account_circle_rounded,
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
        padding: const EdgeInsets.fromLTRB(18, 2, 18, 118),
        children: [
          _ChildHero(
            title: '我的用药',
            subtitle:
                '今天共 ${_myToday?.total ?? _mySchedules.length} 项，已完成 ${_myToday?.taken ?? 0} 项',
            icon: Icons.medication_rounded,
          ),
          const SizedBox(height: 11),
          _todayCard(title: '我今日服药', today: _myToday, schedules: _mySchedules),
          const SizedBox(height: 11),
          _statsRow(
            medicines: _myMedicines,
            schedules: _mySchedules,
            alerts: _myAlerts,
            onMedicines: () => _open(const MedicineListScreen()),
            onSchedules: () => _open(const ScheduleListScreen()),
            onAlerts: () => _open(const AlertCenterScreen()),
          ),
          const SizedBox(height: 10),
          _alertCard(
            alerts: _myAlerts,
            medicines: _myMedicines,
            onOpenAll: () => _open(const AlertCenterScreen()),
          ),
          const AppSectionTitle(title: '常用功能'),
          _actionGrid([
            _action('拍照识药', Icons.camera_alt_rounded, () => _open(const AIRecognizeScreen())),
            _action('用药计划', Icons.list_alt_rounded, () => _open(const ScheduleListScreen())),
            _action('添加计划', Icons.add_alarm_rounded, () => _open(const AddScheduleScreen())),
            _action('药品管理', Icons.inventory_2_rounded, () => _open(const MedicineListScreen())),
            _action('语音助手', Icons.mic_rounded, () {
              final ownerId = Provider.of<AuthService>(
                context,
                listen: false,
              ).dang_qian_yong_hu?.id;
              _open(VoiceAssistantScreen(ownerId: ownerId, ownerLabel: '我的药箱'));
            }),
          ]),
        ],
      ),
    );
  }

  Widget _buildElderTab() {
    if (_jia_zai_zhong) return const Center(child: CircularProgressIndicator());
    final elderId = _elderId;
    if (elderId == null) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(18, 30, 18, 30),
        children: [
          AppGlassCard(
            radius: 28,
            padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
            child: Column(
              children: [
                const AppIconTile(
                  icon: Icons.family_restroom_rounded,
                  size: 80,
                  iconSize: 40,
                  background: AppColors.blueTint,
                ),
                const SizedBox(height: 14),
                const Text(
                  '还没有绑定老人',
                  style: TextStyle(fontSize: 23, fontWeight: FontWeight.w900, color: AppColors.ink),
                ),
                const SizedBox(height: 8),
                const Text(
                  '请老人先在「我的 → 绑定家属」里生成邀请码，再回到这里输入邀请码完成绑定。',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, color: AppColors.muted, height: 1.5),
                ),
                const SizedBox(height: 17),
                AppGradientButton(
                  label: '去绑定老人',
                  icon: Icons.link_rounded,
                  height: 56,
                  fontSize: 19,
                  onPressed: () => _open(const BindElderScreen()),
                ),
              ],
            ),
          ),
        ],
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 2, 18, 118),
        children: [
          _ChildHero(
            title: '${_elderName ?? '老人'}的用药',
            subtitle:
                '今天共 ${_elderToday?.total ?? _elderSchedules.length} 项，已完成 ${_elderToday?.taken ?? 0} 项',
            icon: Icons.elderly_rounded,
            onTap: _elders.length > 1 ? _chooseElder : null,
          ),
          const SizedBox(height: 11),
          _todayCard(
            title: '${_elderName ?? '老人'}今日服药',
            today: _elderToday,
            schedules: _elderSchedules,
          ),
          const SizedBox(height: 11),
          _statsRow(
            medicines: _elderMedicines,
            schedules: _elderSchedules,
            alerts: _elderAlerts,
            onMedicines: () => _open(MedicineListScreen(elderId: elderId)),
            onSchedules: () =>
                _open(ScheduleListScreen(elderId: elderId, title: '${_elderName ?? '老人'}的用药计划')),
            onAlerts: () => _open(AlertCenterScreen(title: '家人提醒', ownerId: elderId)),
          ),
          const SizedBox(height: 10),
          _alertCard(
            alerts: _elderAlerts,
            medicines: _elderMedicines,
            onOpenAll: () => _open(AlertCenterScreen(title: '家人提醒', ownerId: elderId)),
          ),
          const AppSectionTitle(title: '常用功能'),
          _actionGrid([
            _action(
              '拍照识药',
              Icons.camera_alt_rounded,
              () => _open(AIRecognizeScreen(elderId: elderId)),
            ),
            _action(
              '用药计划',
              Icons.list_alt_rounded,
              () =>
                  _open(ScheduleListScreen(elderId: elderId, title: '${_elderName ?? '老人'}的用药计划')),
            ),
            _action(
              '添加计划',
              Icons.add_alarm_rounded,
              () => _open(AddScheduleScreen(elderId: elderId)),
            ),
            _action(
              '药品管理',
              Icons.inventory_2_rounded,
              () => _open(MedicineListScreen(elderId: elderId)),
            ),
            _action(
              '语音助手',
              Icons.mic_rounded,
              () => _open(
                VoiceAssistantScreen(ownerId: elderId, ownerLabel: '${_elderName ?? '老人'}的药箱'),
              ),
            ),
            _action(
              '查看药箱',
              Icons.visibility_rounded,
              () => _open(ChildElderDetailScreen(elderId: elderId, elderName: _elderName ?? '老人')),
            ),
          ]),
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
    final ratio = total == 0 ? 0.0 : (taken / total).clamp(0.0, 1.0);
    return AppGlassCard(
      radius: 24,
      padding: const EdgeInsets.fromLTRB(15, 14, 15, 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const AppIconTile(
                icon: Icons.today_rounded,
                size: 45,
                iconSize: 23,
                background: AppColors.blueTint,
                color: AppColors.blue,
              ),
              const SizedBox(width: 11),
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
              AppPill(
                label: pending > 0 ? '待确认 $pending 项' : '已完成',
                background: pending > 0 ? AppColors.peachTint : AppColors.mintTint,
                foreground: pending > 0 ? const Color(0xFFD6762D) : AppColors.mintDeep,
                fontSize: 11,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '共 $total 项，已完成 $taken 项，待确认 $pending 项',
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.muted,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 9),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 8,
              backgroundColor: const Color(0xFFE3F1F8),
              valueColor: const AlwaysStoppedAnimation<Color>(AppColors.blue),
            ),
          ),
        ],
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
        Expanded(
          child: _stat(
            '药品',
            '${medicines.length}',
            Icons.medication_rounded,
            const Color(0xFF2676C9),
            AppColors.blueTint,
            onMedicines,
          ),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: _stat(
            '计划',
            '${schedules.length}',
            Icons.alarm_rounded,
            AppColors.mintDeep,
            AppColors.mintTint,
            onSchedules,
          ),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: _stat(
            '告警',
            '${alerts.length}',
            Icons.warning_amber_rounded,
            const Color(0xFFD6762D),
            AppColors.peachTint,
            onAlerts,
          ),
        ),
      ],
    );
  }

  Widget _stat(
    String label,
    String value,
    IconData icon,
    Color color,
    Color background,
    VoidCallback onTap,
  ) {
    return AppGlassCard(
      radius: 21,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
      onTap: onTap,
      child: Column(
        children: [
          AppIconTile(icon: icon, size: 39, iconSize: 21, background: background, color: color),
          const SizedBox(height: 7),
          Text(
            value,
            style: const TextStyle(
              fontSize: 25,
              height: 1.1,
              fontWeight: FontWeight.w900,
              color: AppColors.ink,
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.muted,
            ),
          ),
        ],
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
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: AppGlassCard(
        radius: 21,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        onTap: onOpenAll,
        child: Row(
          children: [
            AppIconTile(
              icon: info.icon,
              size: 44,
              iconSize: 22,
              background: AppColors.mintTint,
              color: info.color,
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '用药提醒',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    alerts.length > 1 ? '${info.title} 等 ${alerts.length} 条' : info.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14, color: AppColors.muted),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Color(0xFF8FA6B8), size: 24),
          ],
        ),
      ),
    );
  }

  Widget _action(String text, IconData icon, VoidCallback onTap) {
    return _ActionItem(text: text, icon: icon, onTap: onTap);
  }

  Widget _actionGrid(List<Widget> items) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 9,
      crossAxisSpacing: 9,
      childAspectRatio: 2.35,
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
    return AppGlassCard(
      radius: 20,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      onTap: onTap,
      child: Row(
        children: [
          AppIconTile(
            icon: icon,
            size: 42,
            iconSize: 22,
            background: AppColors.blueTint,
            color: AppColors.blue,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppColors.ink2,
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChildHero extends StatelessWidget {
  const _ChildHero({required this.title, required this.subtitle, required this.icon, this.onTap});

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(28),
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 16, 16, 16),
          decoration: BoxDecoration(
            gradient: AppGradients.heroSoft,
            borderRadius: BorderRadius.circular(28),
            boxShadow: AppShadows.blue,
          ),
          child: Row(
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.17),
                  borderRadius: BorderRadius.circular(19),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                ),
                child: Icon(icon, size: 31, color: Colors.white),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 25,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withValues(alpha: 0.92),
                      ),
                    ),
                  ],
                ),
              ),
              if (onTap != null)
                const Icon(Icons.swap_horiz_rounded, color: Colors.white, size: 25),
            ],
          ),
        ),
      ),
    );
  }
}
