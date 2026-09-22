import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
      backgroundColor: ElderTheme.bgColor,
      appBar: AppBar(title: const Text('绑定家属')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _header(),
          const SizedBox(height: 18),
          _codeCard(),
          if (_cuo_wu != null) ...[
            const SizedBox(height: 12),
            Text(_cuo_wu!, style: const TextStyle(color: ElderTheme.errorColor)),
          ],
        ],
      ),
    );
  }

  Widget _header() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: ElderTheme.cardColor,
        borderRadius: BorderRadius.circular(18),
      ),
      child: const Column(
        children: [
          Icon(Icons.family_restroom_rounded, color: ElderTheme.successColor, size: 60),
          SizedBox(height: 12),
          Text('把邀请码告诉家属', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          SizedBox(height: 8),
          Text(
            '家属端输入邀请码后，就可以查看你的药品、提醒和服药记录。邀请码仅在有效期内可用。',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, color: ElderTheme.textSecondary, height: 1.35),
          ),
        ],
      ),
    );
  }

  Widget _codeCard() {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: ElderTheme.primaryColor.withOpacity(0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: ElderTheme.primaryColor.withOpacity(0.28)),
      ),
      child: Column(
        children: [
          const Text('邀请码', style: TextStyle(fontSize: 16, color: ElderTheme.textSecondary)),
          const SizedBox(height: 10),
          if (_jia_zai_zhong)
            const CircularProgressIndicator()
          else
            Text(
              _code ?? '未生成',
              style: const TextStyle(
                fontSize: 44,
                fontWeight: FontWeight.bold,
                color: ElderTheme.primaryColor,
                letterSpacing: 6,
              ),
            ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _jia_zai_zhong || _code == null ? null : _copy,
                  icon: const Icon(Icons.copy_rounded),
                  label: const Text('复制'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _jia_zai_zhong ? null : _generate,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('重新生成'),
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
