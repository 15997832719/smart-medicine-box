import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/auth_service.dart';
import '../../core/design_system.dart';
import '../../core/theme.dart';
import '../child/child_home_screen.dart';
import '../elder/elder_home_screen.dart';
import 'elder_activation_screen.dart';
import 'face_login_screen.dart';
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
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
          children: [
            _buildHeader(),
            const SizedBox(height: 24),
            _buildForm(),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: AppSecondaryButton(
                    label: '让家人帮我开通',
                    icon: Icons.family_restroom_rounded,
                    fontSize: 15,
                    height: 58,
                    onPressed: () => Navigator.of(
                      context,
                    ).push(ElderPageRoute(page: const ElderActivationScreen())),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: AppSecondaryButton(
                    label: '刷脸登录',
                    icon: Icons.face_retouching_natural_rounded,
                    fontSize: 15,
                    height: 58,
                    onPressed: _jia_zai_zhong
                        ? null
                        : () => Navigator.of(
                            context,
                          ).push(ElderPageRoute(page: const FaceLoginScreen())),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('还没有账号？', style: TextStyle(fontSize: 16, color: AppColors.muted)),
                TextButton(
                  onPressed: () =>
                      Navigator.of(context).push(ElderPageRoute(page: const RegisterScreen())),
                  child: const Text('立即注册'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              '登录即代表你同意《用户协议》与《隐私政策》',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppColors.muted2),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
      decoration: BoxDecoration(
        gradient: AppGradients.glass,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: Colors.white, width: 1.2),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFF8FDFF), Color(0xFFE3F7FF)],
              ),
              borderRadius: BorderRadius.circular(31),
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: const [
                BoxShadow(color: Color(0x24216BAA), blurRadius: 28, offset: Offset(0, 12)),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                const Icon(Icons.medication_rounded, size: 56, color: AppColors.blue),
                Positioned(
                  right: 16,
                  top: 14,
                  child: Container(
                    width: 23,
                    height: 23,
                    decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                    child: const Icon(Icons.add_rounded, size: 16, color: AppColors.blue),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            '智能药箱',
            style: TextStyle(
              fontSize: 44,
              fontWeight: FontWeight.w900,
              color: AppColors.ink,
              letterSpacing: -1.2,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'AI 识药 · 服药提醒 · 家属守护',
            style: TextStyle(
              fontSize: 18,
              color: AppColors.muted,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 14),
          Container(
            width: 92,
            height: 38,
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: const Color(0xFFD9EEFC),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: Align(
              alignment: Alignment.centerRight,
              child: Container(
                width: 29,
                height: 29,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(colors: [Color(0xFFD8FBFF), Color(0xFF68C8EE)]),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(color: Color(0x523B8FC7), blurRadius: 10, offset: Offset(0, 4)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
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
            textInputAction: TextInputAction.next,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            decoration: const InputDecoration(
              labelText: '手机号',
              prefixIcon: Icon(Icons.phone_android_rounded, size: 26),
            ),
            validator: (value) => value == null || value.trim().length < 6 ? '请输入手机号' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _passwordController,
            obscureText: _obscure,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _login(),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            decoration: InputDecoration(
              labelText: '密码',
              prefixIcon: const Icon(Icons.lock_outline_rounded, size: 26),
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility_rounded : Icons.visibility_off_rounded),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            validator: (value) => value == null || value.length < 6 ? '密码至少 6 位' : null,
          ),
          const SizedBox(height: 22),
          AppGradientButton(
            label: '登录',
            icon: Icons.login_rounded,
            height: 70,
            fontSize: 24,
            loading: _jia_zai_zhong,
            onPressed: _jia_zai_zhong ? null : _login,
          ),
        ],
      ),
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
