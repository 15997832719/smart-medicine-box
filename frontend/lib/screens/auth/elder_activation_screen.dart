import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/auth_service.dart';
import '../../core/design_system.dart';
import '../../core/theme.dart';
import '../../services/api_service.dart';
import '../elder/elder_home_screen.dart';

class ElderActivationScreen extends StatefulWidget {
  const ElderActivationScreen({super.key});

  @override
  State<ElderActivationScreen> createState() => _ElderActivationScreenState();
}

class _ElderActivationScreenState extends State<ElderActivationScreen> {
  Timer? _pollTimer;
  bool _loading = true;
  bool _completed = false;
  int? _activationId;
  String? _activationCode;
  String? _deviceSecret;
  String? _error;

  @override
  void initState() {
    super.initState();
    _startActivation();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _startActivation() async {
    _pollTimer?.cancel();
    setState(() {
      _loading = true;
      _error = null;
      _activationId = null;
      _activationCode = null;
      _deviceSecret = null;
    });
    try {
      final data = await ApiService.startActivation();
      if (!mounted) return;
      setState(() {
        _activationId = int.tryParse('${data['activation_id']}');
        _activationCode = data['activation_code']?.toString();
        _deviceSecret = data['device_secret']?.toString();
        _loading = false;
      });
      if (_activationId == null || _activationCode == null || _deviceSecret == null) {
        throw Exception('服务器返回的开通信息不完整');
      }
      _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) => _pollActivation());
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _pollActivation() async {
    if (_completed || _activationId == null || _deviceSecret == null) return;
    try {
      final result = await ApiService.exchangeActivation(
        activationId: _activationId!,
        deviceSecret: _deviceSecret!,
        platform: Platform.isAndroid
            ? 'android'
            : Platform.isIOS
            ? 'ios'
            : Platform.operatingSystem,
      );
      if (result == null) return;
      if (!mounted) return;
      final accepted = await context.read<AuthService>().acceptDeviceLogin(
        result,
        activationId: _activationId!,
        deviceSecret: _deviceSecret!,
        platform: Platform.operatingSystem,
      );
      if (!accepted || !mounted) return;
      _completed = true;
      _pollTimer?.cancel();
      Navigator.of(
        context,
      ).pushAndRemoveUntil(ElderPageRoute(page: const ElderHomeScreen()), (_) => false);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('让家人帮我开通')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(22, 2, 22, 28),
          children: [
            Center(
              child: AppIconTile(
                icon: Icons.family_restroom_rounded,
                size: 104,
                iconSize: 54,
                background: AppColors.blueTint,
              ),
            ),
            const SizedBox(height: 17),
            const Text(
              '把这 6 位数字\n告诉家人',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 32,
                height: 1.22,
                fontWeight: FontWeight.w900,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              '家人输入数字和你的称呼后，这里会自动进入首页。',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: AppColors.muted, height: 1.5),
            ),
            const SizedBox(height: 20),
            AppGlassCard(
              radius: 28,
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
              child: Column(
                children: [
                  const Text(
                    '开通码 · 10 分钟内有效',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.muted,
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 22),
                      child: CircularProgressIndicator(),
                    )
                  else if (_activationCode != null)
                    _CodeDigits(code: _activationCode!)
                  else
                    const Text('未生成', style: TextStyle(fontSize: 24, color: AppColors.muted)),
                  const SizedBox(height: 10),
                  const Text(
                    '请把数字一个一个读给家人听',
                    style: TextStyle(fontSize: 14, color: AppColors.muted2),
                  ),
                ],
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              AppNotice(
                text: _error!,
                icon: Icons.error_outline_rounded,
                background: AppColors.redTint,
                foreground: const Color(0xFF95606A),
                iconColor: AppColors.red,
              ),
            ],
            if (!_loading && _activationCode != null) ...[
              const SizedBox(height: 12),
              const AppNotice(text: '正在等待家人完成开通，请不要关闭此页面。', icon: Icons.cloud_sync_rounded),
            ],
            const SizedBox(height: 14),
            AppSecondaryButton(
              label: '重新生成开通码',
              icon: Icons.refresh_rounded,
              height: 56,
              onPressed: _loading ? null : _startActivation,
            ),
            const SizedBox(height: 12),
            const Text(
              '设备验证通过后，App 会保存本机设备凭据。以后打开 App 可自动登录，忘记密码时也可请家人重新开通。',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppColors.muted2, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}

class _CodeDigits extends StatelessWidget {
  const _CodeDigits({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: code.split('').map((digit) {
        return Container(
          width: 43,
          height: 56,
          margin: const EdgeInsets.symmetric(horizontal: 3.5),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.88),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: const Color(0x5784BFE8), width: 1),
            boxShadow: const [
              BoxShadow(color: Color(0x14266EA6), blurRadius: 12, offset: Offset(0, 5)),
            ],
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
    );
  }
}
