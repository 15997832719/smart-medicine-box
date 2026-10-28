import 'package:flutter/material.dart';

import '../../core/design_system.dart';
import '../../core/theme.dart';
import '../../services/api_service.dart';

class ClaimElderScreen extends StatefulWidget {
  const ClaimElderScreen({super.key});

  @override
  State<ClaimElderScreen> createState() => _ClaimElderScreenState();
}

class _ClaimElderScreenState extends State<ClaimElderScreen> {
  final _codeController = TextEditingController();
  final _nicknameController = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _codeController.dispose();
    _nicknameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final code = _codeController.text.replaceAll(RegExp(r'\D'), '');
    final nickname = _nicknameController.text.trim();
    if (code.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请输入老人手机上的 6 位开通码')));
      return;
    }
    if (nickname.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请输入老人称呼')));
      return;
    }
    setState(() => _loading = true);
    try {
      await ApiService.claimActivation(activationCode: code, nickname: nickname);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('老人账号已开通，请让老人等待自动进入首页')));
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
          backgroundColor: ElderTheme.errorColor,
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('帮家人开通')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 2, 20, 28),
        children: [
          const Center(
            child: AppIconTile(
              icon: Icons.key_rounded,
              size: 104,
              iconSize: 54,
              background: Color(0xFFE3F8FF),
              color: Color(0xFF318EDC),
            ),
          ),
          const SizedBox(height: 15),
          const Text(
            '帮家人开通账号',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: AppColors.ink),
          ),
          const SizedBox(height: 8),
          const Text(
            '输入老人手机上的 6 位开通码，帮家人快速进入药箱。',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, color: AppColors.muted, height: 1.5),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _codeController,
            keyboardType: TextInputType.number,
            maxLength: 6,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w900, letterSpacing: 8),
            decoration: const InputDecoration(
              labelText: '6 位开通码',
              prefixIcon: Icon(Icons.pin_rounded),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _nicknameController,
            style: const TextStyle(fontSize: 18),
            decoration: const InputDecoration(
              labelText: '老人称呼',
              hintText: '例如：妈妈、爷爷',
              prefixIcon: Icon(Icons.badge_outlined),
            ),
          ),
          const SizedBox(height: 18),
          AppGradientButton(
            label: '确认开通',
            icon: Icons.check_circle_rounded,
            loading: _loading,
            onPressed: _loading ? null : _submit,
          ),
          const SizedBox(height: 13),
          const Text(
            '开通不会索取老人的人脸照片，也不会把设备密钥发送给其他手机。',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: AppColors.muted2, height: 1.5),
          ),
        ],
      ),
    );
  }
}
