import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/design_system.dart';
import '../../core/theme.dart';
import '../../services/api_service.dart';

class ElderBindChildScreen extends StatefulWidget {
  const ElderBindChildScreen({super.key});

  @override
  State<ElderBindChildScreen> createState() => _ElderBindChildScreenState();
}

class _ElderBindChildScreenState extends State<ElderBindChildScreen> {
  bool _jia_zai_zhong = true;
  String? _code;
  String? _cuo_wu;

  @override
  void initState() {
    super.initState();
    _generate();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('绑定家属')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 2, 20, 28),
        children: [
          Center(
            child: const AppIconTile(
              icon: Icons.family_restroom_rounded,
              size: 104,
              iconSize: 54,
              background: Color(0xFFE3F8FF),
              color: Color(0xFF318EDC),
            ),
          ),
          const SizedBox(height: 15),
          const Text(
            '把邀请码告诉家属',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 31, fontWeight: FontWeight.w900, color: AppColors.ink),
          ),
          const SizedBox(height: 8),
          const Text(
            '家属输入后，就能查看你的药品、提醒和服药记录。',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: AppColors.muted, height: 1.5),
          ),
          const SizedBox(height: 18),
          _codeCard(),
          if (_cuo_wu != null) ...[
            const SizedBox(height: 12),
            AppNotice(
              text: _cuo_wu!,
              icon: Icons.error_outline_rounded,
              background: AppColors.redTint,
              foreground: const Color(0xFF95606A),
              iconColor: AppColors.red,
            ),
          ],
          const SizedBox(height: 12),
          const AppNotice(text: '家属绑定后，可以帮你在手机上添加药品和用药计划。你的密码不会告诉家属。', icon: Icons.shield_outlined),
        ],
      ),
    );
  }

  Widget _codeCard() {
    final raw = _code ?? '';
    return AppGlassCard(
      radius: 28,
      padding: const EdgeInsets.fromLTRB(16, 19, 16, 16),
      child: Column(
        children: [
          const Text(
            '我的邀请码',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.muted),
          ),
          const SizedBox(height: 13),
          if (_jia_zai_zhong)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: CircularProgressIndicator(),
            )
          else if (raw.length == 6)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: raw.split('').map((digit) {
                return Container(
                  width: 43,
                  height: 56,
                  margin: const EdgeInsets.symmetric(horizontal: 3.5),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: const Color(0x5784BFE8)),
                    boxShadow: AppShadows.soft,
                  ),
                  child: Text(
                    digit,
                    style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w900,
                      color: AppColors.ink2,
                    ),
                  ),
                );
              }).toList(),
            )
          else
            Text(
              _code ?? '未生成',
              style: const TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w800,
                color: AppColors.muted,
              ),
            ),
          const SizedBox(height: 8),
          const Text('邀请码 30 分钟内有效', style: TextStyle(fontSize: 13, color: AppColors.muted2)),
          const SizedBox(height: 15),
          Row(
            children: [
              Expanded(
                child: AppSecondaryButton(
                  label: '复制',
                  icon: Icons.copy_rounded,
                  height: 52,
                  fontSize: 17,
                  onPressed: _jia_zai_zhong || _code == null ? null : _copy,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: AppGradientButton(
                  label: '重新生成',
                  icon: Icons.refresh_rounded,
                  height: 52,
                  fontSize: 17,
                  onPressed: _jia_zai_zhong ? null : _generate,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _generate() async {
    setState(() {
      _jia_zai_zhong = true;
      _cuo_wu = null;
    });
    try {
      final code = await ApiService.generateBindCode();
      if (!mounted) return;
      setState(() {
        _code = code;
        _jia_zai_zhong = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _code = null;
        _cuo_wu = '邀请码生成失败，请确认服务器已登录并重试。';
        _jia_zai_zhong = false;
      });
    }
  }

  void _copy() {
    Clipboard.setData(ClipboardData(text: _code!));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('邀请码已复制'), backgroundColor: ElderTheme.successColor),
    );
  }
}
