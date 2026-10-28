import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/design_system.dart';
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
    final canBind = !_jia_zai_zhong && _codeController.text.trim().length >= 4;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('绑定老人')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 2, 20, 28),
        children: [
          const Center(
            child: AppIconTile(
              icon: Icons.family_restroom_rounded,
              size: 104,
              iconSize: 54,
              background: Color(0xFFE3F8FF),
              color: Color(0xFF318EDC),
            ),
          ),
          const SizedBox(height: 15),
          const Text(
            '输入老人的邀请码',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: AppColors.ink),
          ),
          const SizedBox(height: 8),
          const Text(
            '请让老人在「我的 → 绑定家属」中打开邀请码。',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, color: AppColors.muted, height: 1.5),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _codeController,
            textAlign: TextAlign.center,
            textCapitalization: TextCapitalization.characters,
            style: const TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w900,
              letterSpacing: 6,
              color: AppColors.ink,
            ),
            decoration: const InputDecoration(labelText: '6 位邀请码', hintText: '请输入邀请码'),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
              LengthLimitingTextInputFormatter(8),
            ],
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 13),
          const AppNotice(text: '绑定后可以查看老人药品、服药计划和记录，也可以帮助老人录入药品。', icon: Icons.shield_outlined),
          const SizedBox(height: 18),
          AppGradientButton(
            label: '确认绑定',
            icon: Icons.link_rounded,
            loading: _jia_zai_zhong,
            onPressed: canBind ? _bind : null,
          ),
          const SizedBox(height: 12),
          const Text(
            '请输入老人端生成的有效邀请码。',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: AppColors.muted2),
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
          page: elderId == null
              ? const BindElderScreen()
              : ChildElderDetailScreen(elderId: elderId, elderName: elderName),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('绑定失败：$e'), backgroundColor: ElderTheme.errorColor));
    } finally {
      if (mounted) setState(() => _jia_zai_zhong = false);
    }
  }
}
