import 'package:flutter/material.dart';

import '../../core/alert_text.dart';
import '../../core/design_system.dart';
import '../../core/theme.dart';
import '../../models/medicine.dart';
import '../../services/api_service.dart';

class AlertCenterScreen extends StatefulWidget {
  final String title;
  final int? ownerId;

  const AlertCenterScreen({super.key, this.title = '提醒中心', this.ownerId});

  @override
  State<AlertCenterScreen> createState() => _AlertCenterScreenState();
}

class _AlertCenterScreenState extends State<AlertCenterScreen> {
  bool _jia_zai_zhong = true;
  List<MedicineAlert> _jing_gao_lie_biao = [];
  TodaySummary? _today;
  List<Medicine> _yao_pin_lie_biao = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final today = _today;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: Text(widget.title)),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 28),
          children: [
            _summaryCard(today),
            const SizedBox(height: 8),
            _sectionTitle('风险提醒'),
            const SizedBox(height: 4),
            if (_jia_zai_zhong)
              const Center(
                child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()),
              )
            else if (_jing_gao_lie_biao.isEmpty)
              _emptyCard('当前没有高风险提醒。')
            else ...[
              ..._jing_gao_lie_biao.map(_alertTile),
              if (_jing_gao_lie_biao.any((alert) => alert.type == 'low_stock')) _thresholdHelp(),
            ],
            const SizedBox(height: 8),
            _sectionTitle('今日服药记录'),
            const SizedBox(height: 4),
            if (today == null || today.logs.isEmpty)
              _emptyCard('今天还没有确认服药记录。')
            else
              ...today.logs.take(8).map(_logTile),
          ],
        ),
      ),
    );
  }

  Widget _summaryCard(TodaySummary? today) {
    final total = today?.total ?? 0;
    final taken = today?.taken ?? 0;
    final pending = today?.pending ?? 0;
    final ratio = total == 0 ? 0.0 : (taken / total).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 17, 18, 16),
      decoration: BoxDecoration(
        gradient: AppGradients.hero,
        borderRadius: BorderRadius.circular(27),
        boxShadow: AppShadows.blue,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '今日守护状态',
                  style: TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 5),
                Text(
                  _jia_zai_zhong ? '正在同步提醒…' : '已确认 $taken/$total，待确认 $pending',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.92), fontSize: 15),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 68,
            height: 68,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 68,
                  height: 68,
                  child: CircularProgressIndicator(
                    value: ratio,
                    strokeWidth: 6,
                    strokeCap: StrokeCap.round,
                    backgroundColor: Colors.white.withValues(alpha: 0.2),
                    valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
                Text(
                  '${(ratio * 100).round()}%',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _alertTile(MedicineAlert alert) {
    final info = describeAlert(alert, _yao_pin_lie_biao);
    final high = alert.severity == 'high';
    final color = high ? ElderTheme.errorColor : info.color;
    return AppGlassCard(
      margin: const EdgeInsets.only(bottom: 9),
      radius: 21,
      padding: const EdgeInsets.fromLTRB(13, 12, 13, 11),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AppIconTile(
                icon: info.icon,
                size: 45,
                iconSize: 23,
                background: color.withValues(alpha: 0.13),
                color: color,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  info.title,
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: color),
                ),
              ),
              if (high)
                const AppPill(
                  label: '高风险',
                  background: AppColors.redTint,
                  foreground: AppColors.red,
                  fontSize: 11,
                ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            info.detail,
            style: const TextStyle(fontSize: 15, height: 1.45, color: AppColors.ink2),
          ),
          if (info.canEditThreshold && info.medicine != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _showThresholdDialog(info.medicine!),
                icon: const Icon(Icons.tune, size: 19),
                label: const Text('修改提醒数量', style: TextStyle(fontSize: 15)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _thresholdHelp() {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ElderTheme.cardColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Text(
        '提醒数量是什么意思？\n药的剩余数量少于你设定的数字时，App 就会提醒你。数字调大，提醒会更早；调到 1 就是只剩最后 1 片才提醒。',
        style: TextStyle(fontSize: 15, color: ElderTheme.textSecondary, height: 1.5),
      ),
    );
  }

  Future<void> _showThresholdDialog(Medicine medicine) async {
    var value = medicine.lowStockThreshold;
    final saved = await showDialog<int>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('提醒数量', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '药品快吃完时，希望 App 提醒你。\n剩余数量少于下面这个数字，就会开始提醒。',
                style: TextStyle(fontSize: 17, height: 1.5),
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton.filledTonal(
                    iconSize: 30,
                    onPressed: value <= 1 ? null : () => setDialogState(() => value -= 1),
                    icon: const Icon(Icons.remove),
                  ),
                  SizedBox(
                    width: 96,
                    child: Text(
                      '$value',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 34, fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton.filledTonal(
                    iconSize: 30,
                    onPressed: value >= 99 ? null : () => setDialogState(() => value += 1),
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Center(
                child: Text(
                  '剩 $value 片以下时提醒你',
                  style: const TextStyle(fontSize: 17, color: ElderTheme.textSecondary),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消', style: TextStyle(fontSize: 18)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, value),
              child: const Text('保存', style: TextStyle(fontSize: 18)),
            ),
          ],
        ),
      ),
    );
    if (saved == null || saved == medicine.lowStockThreshold) return;
    try {
      await ApiService.updateMedicine(_copyWithThreshold(medicine, saved));
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已保存：剩 $saved 片以下时会提醒你')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('保存失败，请稍后再试')));
    }
  }

  Medicine _copyWithThreshold(Medicine medicine, int threshold) {
    return Medicine(
      id: medicine.id,
      yong_hu_bian_hao: medicine.yong_hu_bian_hao,
      name: medicine.name,
      spec: medicine.spec,
      category: medicine.category,
      manufacturer: medicine.manufacturer,
      description: medicine.description,
      dosage: medicine.dosage,
      frequency: medicine.frequency,
      precautions: medicine.precautions,
      conflictTags: medicine.conflictTags,
      stockCount: medicine.stockCount,
      lowStockThreshold: threshold,
      you_xiao_ri_qi: medicine.you_xiao_ri_qi,
      imageUrl: medicine.imageUrl,
      aiResult: medicine.aiResult,
      createdAt: medicine.createdAt,
    );
  }

  Widget _logTile(MedicationLog log) {
    final time = log.actualTime ?? log.plannedTime;
    final hh = time.hour.toString().padLeft(2, '0');
    final mm = time.minute.toString().padLeft(2, '0');
    return AppGlassCard(
      margin: const EdgeInsets.only(bottom: 8),
      radius: 19,
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      child: Row(
        children: [
          const AppIconTile(
            icon: Icons.check_circle_rounded,
            size: 42,
            iconSize: 22,
            background: AppColors.mintTint,
            color: AppColors.mintDeep,
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  log.yao_pin_ming_cheng ?? '药品',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '$hh:$mm  ${log.confirmMethod ?? '已确认'}',
                  style: const TextStyle(fontSize: 14, color: AppColors.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyCard(String text) {
    return AppGlassCard(
      radius: 20,
      padding: const EdgeInsets.all(16),
      child: Text(text, style: const TextStyle(fontSize: 15, color: AppColors.muted)),
    );
  }

  Widget _sectionTitle(String text) {
    return AppSectionTitle(title: text);
  }

  Future<void> _load() async {
    setState(() => _jia_zai_zhong = true);
    try {
      final result = await Future.wait([
        ApiService.getAlerts(elderId: widget.ownerId),
        ApiService.getTodayLogs(elderId: widget.ownerId),
        ApiService.getMedicines(elderId: widget.ownerId),
      ]);
      if (!mounted) return;
      setState(() {
        _jing_gao_lie_biao = result[0] as List<MedicineAlert>;
        _today = result[1] as TodaySummary;
        _yao_pin_lie_biao = result[2] as List<Medicine>;
        _jia_zai_zhong = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _jia_zai_zhong = false);
    }
  }
}
