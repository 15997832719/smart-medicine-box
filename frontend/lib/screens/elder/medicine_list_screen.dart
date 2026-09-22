import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../models/medicine.dart';
import '../../services/api_service.dart';
import 'ai_recognize_screen.dart';

class MedicineListScreen extends StatefulWidget {
  const MedicineListScreen({super.key, this.elderId});

  
  final int? elderId;

  @override
  State<MedicineListScreen> createState() => _MedicineListScreenState();
}

class _MedicineListScreenState extends State<MedicineListScreen> {
  final _searchController = TextEditingController();
  bool _jia_zai_zhong = true;
  String _filter = 'all';
  String? _cuo_wu;
  List<Medicine> _yao_pin_lie_biao = [];

  @override
  void initState() {
    super.initState();
    _loadMedicines();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Medicine> get _filtered {
    final keyword = _searchController.text.trim();
    return _yao_pin_lie_biao.where((medicine) {
      if (keyword.isNotEmpty && !medicine.name.contains(keyword)) return false;
      if (_filter == 'all') return true;
      return _status(medicine) == _filter;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ElderTheme.bgColor,
      appBar: AppBar(title: const Text('药品管理')),
      body: Column(
        children: [
          _buildSearch(),
          _buildFilters(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadMedicines,
              child: _jia_zai_zhong
                  ? const Center(child: CircularProgressIndicator())
                  : _cuo_wu != null
                      ? _buildMessage(Icons.cloud_off_rounded, '加载失败', _cuo_wu!, retry: true)
                      : _filtered.isEmpty
                          ? _buildMessage(Icons.medication_rounded, '暂无药品', '点击右下角按钮拍照识别并添加药品')
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(14, 8, 14, 100),
                              itemCount: _filtered.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 10),
                              itemBuilder: (context, index) => _buildMedicineItem(_filtered[index]),
                            ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(ElderPageRoute(page: const AIRecognizeScreen())).then((_) => _loadMedicines()),
        icon: const Icon(Icons.camera_alt_rounded),
        label: const Text('拍照识药'),
      ),
    );
  }

  Widget _buildSearch() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
      color: ElderTheme.cardColor,
      child: TextField(
        controller: _searchController,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          hintText: '搜索药品名称',
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: _searchController.text.isEmpty
              ? null
              : IconButton(
                  onPressed: () {
                    _searchController.clear();
                    setState(() {});
                  },
                  icon: const Icon(Icons.close_rounded),
                ),
        ),
      ),
    );
  }

  Widget _buildFilters() {
    final filters = const [
      ('all', '全部'),
      ('normal', '正常'),
      ('expiring', '临期'),
      ('expired', '过期'),
    ];
    return Container(
      width: double.infinity,
      color: ElderTheme.cardColor,
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
      child: Wrap(
        spacing: 8,
        children: filters.map((item) {
          final selected = _filter == item.$1;
          return ChoiceChip(
            label: Text(item.$2),
            selected: selected,
            onSelected: (_) => setState(() => _filter = item.$1),
            selectedColor: ElderTheme.primaryColor.withOpacity(0.18),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildMedicineItem(Medicine medicine) {
    final status = _status(medicine);
    final color = _statusColor(status);
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => _showDetail(medicine),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: ElderTheme.cardColor,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withOpacity(status == 'normal' ? 0.08 : 0.36)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(16)),
              child: Icon(Icons.medication_rounded, color: color, size: 32),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(medicine.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 5),
                  Text(
                    medicine.dosage ?? medicine.frequency ?? medicine.category ?? '未填写用法',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: ElderTheme.textSecondary, fontSize: 15),
                  ),
                  const SizedBox(height: 5),
                  Text(_validText(medicine), style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            IconButton(
              onPressed: () => _delete(medicine),
              icon: const Icon(Icons.delete_outline_rounded, color: ElderTheme.errorColor),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessage(IconData icon, String title, String subtitle, {bool retry = false}) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 120),
        Icon(icon, size: 76, color: ElderTheme.textSecondary.withOpacity(0.45)),
        const SizedBox(height: 16),
        Center(child: Text(title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold))),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, color: ElderTheme.textSecondary)),
        ),
        if (retry) ...[
          const SizedBox(height: 18),
          Center(child: ElevatedButton.icon(onPressed: _loadMedicines, icon: const Icon(Icons.refresh_rounded), label: const Text('重试'))),
        ],
      ],
    );
  }

  void _showDetail(Medicine medicine) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(medicine.name, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
            const SizedBox(height: 14),
            _detailRow('规格/分类', medicine.spec ?? medicine.category),
            _detailRow('厂家', medicine.manufacturer),
            _detailRow('用法用量', medicine.dosage),
            _detailRow('服用频次', medicine.frequency),
            _detailRow('有效期', medicine.you_xiao_ri_qi == null ? null : _date(medicine.you_xiao_ri_qi!)),
            _detailRow('库存', '还剩 ${medicine.stockCount} 片'),
            _detailRow('提醒数量', '少于 ${medicine.lowStockThreshold} 片时提醒你'),
            _detailRow('注意事项', medicine.precautions),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close_rounded),
              label: const Text('关闭'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String? value) {
    if (value == null || value.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 86, child: Text(label, style: const TextStyle(color: ElderTheme.textSecondary, fontSize: 15))),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 16, height: 1.35))),
        ],
      ),
    );
  }

  Future<void> _loadMedicines() async {
    setState(() {
      _jia_zai_zhong = true;
      _cuo_wu = null;
    });
    try {
      final medicines = await ApiService.getMedicines(elderId: widget.elderId);
      if (!mounted) return;
      setState(() {
        _yao_pin_lie_biao = medicines;
        _jia_zai_zhong = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cuo_wu = '请确认后端已启动，并且手机可以访问电脑 IP。';
        _jia_zai_zhong = false;
      });
    }
  }

  Future<void> _delete(Medicine medicine) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除药品'),
        content: Text('确定删除“${medicine.name}”吗？相关提醒也会失效。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('删除')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ApiService.deleteMedicine(medicine.id, elderId: widget.elderId);
      await _loadMedicines();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('删除失败：$e'), backgroundColor: ElderTheme.errorColor));
    }
  }

  String _status(Medicine medicine) {
    final date = medicine.you_xiao_ri_qi;
    if (date == null) return 'normal';
    final today = DateTime.now();
    final current = DateTime(today.year, today.month, today.day);
    final target = DateTime(date.year, date.month, date.day);
    if (target.isBefore(current)) return 'expired';
    if (target.difference(current).inDays <= 30) return 'expiring';
    return 'normal';
  }

  Color _statusColor(String status) {
    if (status == 'expired') return ElderTheme.errorColor;
    if (status == 'expiring') return ElderTheme.warningColor;
    return ElderTheme.successColor;
  }

  String _validText(Medicine medicine) {
    if (medicine.you_xiao_ri_qi == null) return '未填写有效期';
    final status = _status(medicine);
    if (status == 'expired') return '已过期：${_date(medicine.you_xiao_ri_qi!)}';
    if (status == 'expiring') return '临近有效期：${_date(medicine.you_xiao_ri_qi!)}';
    return '有效期：${_date(medicine.you_xiao_ri_qi!)}';
  }

  String _date(DateTime date) => '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}
