import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme.dart';
import '../../services/api_service.dart';
import 'child_elder_detail_screen.dart';

class BindElderScreen extends StatefulWidget {
  const BindElderScreen({super.key});

  @override
  State<BindElderScreen> createState() => _BindElderScreenState();
}

class _BindElderScreenState extends State<BindElderScreen> {
  final _codeController = TextEditingController();
  bool _jia_zai_zhong = false;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ElderTheme.bgColor,
      appBar: AppBar(title: const Text('绑定老人')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _introCard(),
          const SizedBox(height: 18),
          TextField(
            controller: _codeController,
            textAlign: TextAlign.center,
            textCapitalization: TextCapitalization.characters,
            style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold, letterSpacing: 5),
            decoration: const InputDecoration(labelText: '邀请码', hintText: '请输入老人端显示的 6 位邀请码'),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
              LengthLimitingTextInputFormatter(8),
            ],
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 22),
          ElevatedButton.icon(
            onPressed: _jia_zai_zhong || _codeController.text.trim().length < 4 ? null : _bind,
            icon: _jia_zai_zhong
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.link_rounded),
            label: const Text('确认绑定'),
          ),
          const SizedBox(height: 12),
          const Text(
            '请输入老人端生成的有效邀请码。',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: ElderTheme.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _introCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: ElderTheme.cardColor,
        borderRadius: BorderRadius.circular(18),
      ),
      child: const Column(
        children: [
          Icon(Icons.family_restroom_rounded, color: ElderTheme.primaryColor, size: 60),
          SizedBox(height: 12),
          Text('绑定老人账号', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          SizedBox(height: 8),
          Text(
            '绑定后可以查看老人药品、服药计划和服药记录，也可以帮助老人录入药品。',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, color: ElderTheme.textSecondary, height: 1.35),
          ),
        ],
      ),
    );
  }

  Future<void> _bind() async {
    setState(() => _jia_zai_zhong = true);
    try {
      await ApiService.bindFamily(_codeController.text.trim());
      if (!mounted) return;
      final family = await ApiService.getMyFamily();
      final elders = (family['elders'] as List?) ?? const [];
      final elder = elders.isEmpty ? null : Map<String, dynamic>.from(elders.first as Map);
      final elderId = int.tryParse('${elder?['id']}');
      final elderName = elder?['nickname']?.toString() ?? '老人';
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('绑定成功'), backgroundColor: ElderTheme.successColor),
      );
      Navigator.of(context).pushReplacement(
        ElderPageRoute(
          page: elderId == null ? const BindElderScreen() : ChildElderDetailScreen(elderId: elderId, elderName: elderName),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('绑定失败：$e'), backgroundColor: ElderTheme.errorColor),
      );
    } finally {
      if (mounted) setState(() => _jia_zai_zhong = false);
    }
  }
}
