import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/auth_service.dart';
import '../../core/theme.dart';
import '../child/child_home_screen.dart';
import '../elder/elder_home_screen.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _jia_zai_zhong = false;
  bool _obscure = true;

  @override
  void dispose() {
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ElderTheme.bgColor,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 24),
            _buildHeader(),
            const SizedBox(height: 32),
            _buildForm(),
            const SizedBox(height: 18),
            const SizedBox(height: 18),
            _buildRegisterLink(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        Container(
          width: 106,
          height: 106,
          decoration: BoxDecoration(
            color: ElderTheme.primaryColor.withOpacity(0.12),
            borderRadius: BorderRadius.circular(28),
          ),
          child: const Icon(Icons.medication_rounded, size: 60, color: ElderTheme.primaryColor),
        ),
        const SizedBox(height: 22),
        const Text('智能药箱', style: TextStyle(fontSize: 34, fontWeight: FontWeight.bold, color: ElderTheme.textPrimary)),
        const SizedBox(height: 8),
        const Text('AI 识药 · 服药提醒 · 家属守护', style: TextStyle(fontSize: 17, color: ElderTheme.textSecondary)),
      ],
    );
  }

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: '手机号', prefixIcon: Icon(Icons.phone_android_rounded)),
            validator: (value) => value == null || value.trim().length < 6 ? '请输入手机号' : null,
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _passwordController,
            obscureText: _obscure,
            decoration: InputDecoration(
              labelText: '密码',
              prefixIcon: const Icon(Icons.lock_outline_rounded),
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility_rounded : Icons.visibility_off_rounded),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            validator: (value) => value == null || value.length < 6 ? '密码至少 6 位' : null,
          ),
          const SizedBox(height: 22),
          ElevatedButton.icon(
            onPressed: _jia_zai_zhong ? null : _login,
            icon: _jia_zai_zhong
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.login_rounded),
            label: const Text('登录'),
          ),
        ],
      ),
    );
  }

  Widget _buildRegisterLink() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text('还没有账号？', style: TextStyle(fontSize: 16, color: ElderTheme.textSecondary)),
        TextButton(
          onPressed: () => Navigator.of(context).push(ElderPageRoute(page: const RegisterScreen())),
          child: const Text('立即注册'),
        ),
      ],
    );
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _jia_zai_zhong = true);
    final auth = context.read<AuthService>();
    final ok = await auth.login(_phoneController.text.trim(), _passwordController.text);
    if (!mounted) return;
    setState(() => _jia_zai_zhong = false);
    if (ok) {
      _goHome(auth.dang_qian_yong_hu?.role ?? 'elder');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(auth.lastError ?? '登录失败'), backgroundColor: ElderTheme.errorColor),
      );
    }
  }

  void _goHome(String role) {
    Navigator.of(context).pushAndRemoveUntil(
      ElderPageRoute(page: role == 'child' ? const ChildHomeScreen() : const ElderHomeScreen()),
      (_) => false,
    );
  }
}
