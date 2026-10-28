import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/auth_service.dart';
import '../../core/design_system.dart';
import '../../core/theme.dart';
import '../../services/api_service.dart';
import '../auth/login_screen.dart';

class DeleteAccountScreen extends StatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  State<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends State<DeleteAccountScreen> {
  final _passwordController = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    final password = _passwordController.text;
    if (password.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除账号'),
        content: const Text('账号、药品、计划、服药记录和设备绑定都将被删除，且无法恢复。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('确认删除')),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _loading = true);
    try {
      await ApiService.deleteAccount(password);
      if (!mounted) return;
      await context.read<AuthService>().logout();
      if (!mounted) return;
      Navigator.of(
        context,
      ).pushAndRemoveUntil(ElderPageRoute(page: const LoginScreen()), (_) => false);
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
      appBar: AppBar(title: const Text('删除账号')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 2, 20, 28),
        children: [
          Center(
            child: Container(
              width: 98,
              height: 98,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFFFFF5F5), Color(0xFFFFDFE2)]),
                borderRadius: BorderRadius.circular(32),
                border: Border.all(color: Colors.white),
                boxShadow: AppShadows.soft,
              ),
              child: const Icon(Icons.warning_amber_rounded, size: 52, color: AppColors.red),
            ),
          ),
          const SizedBox(height: 15),
          const Text(
            '删除后无法恢复',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: Color(0xFF6E2B33)),
          ),
          const SizedBox(height: 8),
          const Text(
            '请确认你不再需要这个账号里的所有数据',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, color: Color(0xFF80616A)),
          ),
          const SizedBox(height: 16),
          AppGlassCard(
            radius: 23,
            padding: const EdgeInsets.fromLTRB(15, 14, 15, 9),
            child: const Column(
              children: [
                _DangerBullet('药品、用药计划和库存记录将被删除。'),
                _DangerBullet('全部服药记录与家庭绑定将被删除。'),
                _DangerBullet('音箱绑定、设备凭据和人脸数据将被删除。'),
              ],
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _passwordController,
            obscureText: true,
            style: const TextStyle(fontSize: 18),
            decoration: const InputDecoration(
              labelText: '输入当前密码确认',
              prefixIcon: Icon(Icons.lock_outline_rounded),
            ),
          ),
          const SizedBox(height: 18),
          AppGradientButton(
            label: '永久删除账号',
            icon: Icons.delete_forever_rounded,
            gradient: AppGradients.redButton,
            loading: _loading,
            onPressed: _loading ? null : _delete,
          ),
          const SizedBox(height: 12),
          const Text(
            '如果只是更换手机，建议先在“设备管理”中撤销旧设备',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: AppColors.muted2),
          ),
        ],
      ),
    );
  }
}

class _DangerBullet extends StatelessWidget {
  const _DangerBullet(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 7,
            height: 7,
            margin: const EdgeInsets.only(top: 7),
            decoration: const BoxDecoration(color: Color(0xFFE4858C), shape: BoxShape.circle),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 15, height: 1.5, color: Color(0xFF6B5660)),
            ),
          ),
        ],
      ),
    );
  }
}
