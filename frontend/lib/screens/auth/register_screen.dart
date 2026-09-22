import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/auth_service.dart';
import '../../core/theme.dart';
import '../child/child_home_screen.dart';
import '../elder/elder_home_screen.dart';

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
      backgroundColor: ElderTheme.bgColor,
      appBar: AppBar(
        title: const Text('注册账号'),
        backgroundColor: ElderTheme.primaryColor,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
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
            icon: Icons.elderly_rounded,
            color: ElderTheme.primaryColor,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _roleCard(
            role: 'child',
            title: '家属端',
            subtitle: '查看老人服药情况',
            icon: Icons.family_restroom_rounded,
            color: ElderTheme.successColor,
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
      borderRadius: BorderRadius.circular(18),
      onTap: () => setState(() => _role = role),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.12) : ElderTheme.cardColor,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: selected ? color : ElderTheme.dividerColor, width: selected ? 2 : 1),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 42),
            const SizedBox(height: 8),
            Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: selected ? color : ElderTheme.textPrimary)),
            const SizedBox(height: 4),
            Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: ElderTheme.textSecondary)),
            if (selected) ...[
              const SizedBox(height: 8),
              Icon(Icons.check_circle_rounded, color: color, size: 22),
            ],
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
            decoration: const InputDecoration(labelText: '手机号', prefixIcon: Icon(Icons.phone_android_rounded)),
            validator: (value) => value == null || value.trim().length < 6 ? '请输入手机号' : null,
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _nicknameController,
            decoration: const InputDecoration(labelText: '昵称', prefixIcon: Icon(Icons.person_outline_rounded)),
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
          const SizedBox(height: 14),
          TextFormField(
            controller: _confirmController,
            obscureText: _obscure,
            decoration: const InputDecoration(labelText: '确认密码', prefixIcon: Icon(Icons.lock_reset_rounded)),
            validator: (value) => value != _passwordController.text ? '两次密码不一致' : null,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _jia_zai_zhong ? null : _register,
            icon: _jia_zai_zhong
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.check_circle_outline_rounded),
            label: const Text('完成注册'),
          ),
          const SizedBox(height: 12),
          const Text(
            '注册信息会保存到服务器；请使用本人手机号并妥善保管密码。',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: ElderTheme.textSecondary),
          ),
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
        ElderPageRoute(page: _role == 'child' ? const ChildHomeScreen() : const ElderHomeScreen()),
        (_) => false,
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(auth.lastError ?? '注册失败'), backgroundColor: ElderTheme.errorColor),
      );
    }
  }
}
