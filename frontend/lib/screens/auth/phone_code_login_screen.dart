import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/auth_service.dart';
import '../../core/design_system.dart';
import '../../core/theme.dart';
import '../../services/api_service.dart';
import '../child/child_home_screen.dart';
import '../elder/elder_home_screen.dart';

class PhoneCodeLoginScreen extends StatefulWidget {
  const PhoneCodeLoginScreen({super.key});

  @override
  State<PhoneCodeLoginScreen> createState() => _PhoneCodeLoginScreenState();
}

class _PhoneCodeLoginScreenState extends State<PhoneCodeLoginScreen> {
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();
  bool _loading = false;
  bool _sent = false;
  String? _message;

  @override
  void dispose() {
    _phoneController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final phone = _phoneController.text.trim();
    if (phone.length < 6) return;
    setState(() => _loading = true);
    try {
      final data = await ApiService.sendSmsCode(phone);
      if (!mounted) return;
      setState(() {
        _sent = true;
        _message = data['debug_code'] == null ? '验证码已发送' : '测试验证码：${data['debug_code']}';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _message = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _login() async {
    setState(() => _loading = true);
    try {
      final data = await ApiService.smsLogin(
        _phoneController.text.trim(),
        _codeController.text.trim(),
      );
      final auth = context.read<AuthService>();
      final ok = await auth.acceptSmsLogin(data);
      if (!mounted) return;
      if (!ok) throw Exception('登录响应无效');
      final role = auth.dang_qian_yong_hu?.role ?? 'elder';
      Navigator.of(context).pushAndRemoveUntil(
        ElderPageRoute(page: role == 'child' ? const ChildHomeScreen() : const ElderHomeScreen()),
        (_) => false,
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _message = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('手机号验证码登录')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(22, 4, 22, 28),
        children: [
          const SizedBox(height: 8),
          Center(
            child: AppIconTile(
              icon: Icons.phone_iphone_rounded,
              size: 78,
              iconSize: 38,
              gradient: AppGradients.primaryButton,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            '用验证码登录',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: AppColors.ink),
          ),
          const SizedBox(height: 8),
          const Text(
            '忘记密码时，可以用手机号快速进入药箱',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: AppColors.muted, height: 1.5),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.next,
            style: const TextStyle(fontSize: 20),
            decoration: const InputDecoration(
              labelText: '手机号',
              prefixIcon: Icon(Icons.phone_android_rounded),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _codeController,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _login(),
                  style: const TextStyle(fontSize: 20),
                  decoration: const InputDecoration(
                    labelText: '验证码',
                    prefixIcon: Icon(Icons.sms_rounded),
                  ),
                ),
              ),
              const SizedBox(width: 9),
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: SizedBox(
                  height: 50,
                  child: TextButton(
                    onPressed: _loading ? null : _send,
                    style: TextButton.styleFrom(
                      backgroundColor: AppColors.blueTint,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      padding: const EdgeInsets.symmetric(horizontal: 11),
                    ),
                    child: Text(_sent ? '重新发送' : '获取验证码', style: const TextStyle(fontSize: 13)),
                  ),
                ),
              ),
            ],
          ),
          if (_message != null) ...[
            const SizedBox(height: 12),
            AppNotice(
              text: _message!,
              icon: _loading ? Icons.sync_rounded : Icons.info_outline_rounded,
            ),
          ],
          const SizedBox(height: 22),
          AppGradientButton(
            label: '登录',
            icon: Icons.check_circle_rounded,
            loading: _loading,
            onPressed: _loading ? null : _login,
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('想起密码了？', style: TextStyle(fontSize: 16, color: AppColors.muted)),
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('使用密码登录')),
            ],
          ),
          const AppNotice(text: '验证码 5 分钟内有效，请勿告诉他人。', icon: Icons.shield_outlined),
        ],
      ),
    );
  }
}
