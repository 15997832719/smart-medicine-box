import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/auth_service.dart';
import '../../core/design_system.dart';
import '../../core/theme.dart';
import '../child/child_home_screen.dart';
import 'face_enroll_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _phoneController = TextEditingController();
  final _nicknameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  String _role = 'elder';
  bool _jia_zai_zhong = false;
  bool _obscure = true;

  @override
  void dispose() {
    _phoneController.dispose();
    _nicknameController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('注册账号')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
          children: [
            const Text(
              '选择你的使用身份',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: AppColors.ink),
            ),
            const SizedBox(height: 7),
            const Text(
              '老人管理自己，家属远程守护',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: AppColors.muted),
            ),
            const SizedBox(height: 18),
            _buildRoleSelector(),
            const SizedBox(height: 18),
            _buildForm(),
          ],
        ),
      ),
    );
  }

  Widget _buildRoleSelector() {
    return Row(
      children: [
        Expanded(
          child: _roleCard(
            role: 'elder',
            title: '老人端',
            subtitle: '管理自己的药品和提醒',
            icon: Icons.person_rounded,
            color: AppColors.blue,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _roleCard(
            role: 'child',
            title: '家属端',
            subtitle: '查看老人服药情况',
            icon: Icons.people_alt_rounded,
            color: AppColors.mintDeep,
          ),
        ),
      ],
    );
  }

  Widget _roleCard({
    required String role,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    final selected = _role == role;
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: () => setState(() => _role = role),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 17),
        decoration: BoxDecoration(
          gradient: selected
              ? const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFE3F8FF), Color(0xFFE9EFFF)],
                )
              : AppGradients.glassSoft,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: selected ? color.withValues(alpha: 0.76) : Colors.white,
            width: selected ? 1.6 : 1.1,
          ),
          boxShadow: AppShadows.soft,
        ),
        child: Column(
          children: [
            AppIconTile(
              icon: icon,
              size: 62,
              iconSize: 32,
              gradient: selected ? AppGradients.primaryButton : null,
              background: selected ? null : Colors.white.withValues(alpha: 0.74),
              color: selected ? Colors.white : AppColors.muted,
            ),
            const SizedBox(height: 10),
            Text(
              title,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: AppColors.muted2, height: 1.35),
            ),
          ],
        ),
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
            style: const TextStyle(fontSize: 19),
            decoration: const InputDecoration(
              labelText: '手机号',
              prefixIcon: Icon(Icons.phone_android_rounded),
            ),
            validator: (value) => value == null || value.trim().length < 6 ? '请输入手机号' : null,
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: _nicknameController,
            textInputAction: TextInputAction.next,
            style: const TextStyle(fontSize: 19),
            decoration: const InputDecoration(
              labelText: '昵称',
              prefixIcon: Icon(Icons.person_outline_rounded),
            ),
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: _passwordController,
            obscureText: _obscure,
            textInputAction: TextInputAction.next,
            style: const TextStyle(fontSize: 19),
            decoration: InputDecoration(
              labelText: '密码（至少 6 位）',
              prefixIcon: const Icon(Icons.lock_outline_rounded),
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility_rounded : Icons.visibility_off_rounded),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            validator: (value) => value == null || value.length < 6 ? '密码至少 6 位' : null,
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: _confirmController,
            obscureText: _obscure,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _register(),
            style: const TextStyle(fontSize: 19),
            decoration: const InputDecoration(
              labelText: '确认密码',
              prefixIcon: Icon(Icons.lock_reset_rounded),
            ),
            validator: (value) => value != _passwordController.text ? '两次密码不一致' : null,
          ),
          const SizedBox(height: 20),
          AppGradientButton(
            label: '完成注册',
            icon: Icons.check_circle_outline_rounded,
            loading: _jia_zai_zhong,
            onPressed: _jia_zai_zhong ? null : _register,
          ),
          const SizedBox(height: 12),
          const AppNotice(text: '注册信息会保存到服务器；请使用本人手机号并妥善保管密码。'),
        ],
      ),
    );
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _jia_zai_zhong = true);
    final auth = context.read<AuthService>();
    final ok = await auth.register(
      phone: _phoneController.text.trim(),
      password: _passwordController.text,
      role: _role,
      nickname: _nicknameController.text.trim().isEmpty ? null : _nicknameController.text.trim(),
    );
    if (!mounted) return;
    setState(() => _jia_zai_zhong = false);
    if (ok) {
      Navigator.of(context).pushAndRemoveUntil(
        ElderPageRoute(page: _role == 'child' ? const ChildHomeScreen() : const FaceEnrollScreen()),
        (_) => false,
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(auth.lastError ?? '注册失败'), backgroundColor: ElderTheme.errorColor),
      );
    }
  }
}
