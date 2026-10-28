import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/auth_service.dart';
import '../../core/design_system.dart';
import '../../core/theme.dart';
import '../../services/api_service.dart';
import '../../services/face_camera_service.dart';
import '../child/child_home_screen.dart';
import '../elder/elder_home_screen.dart';
import 'phone_code_login_screen.dart';

class FaceLoginScreen extends StatefulWidget {
  const FaceLoginScreen({super.key});

  @override
  State<FaceLoginScreen> createState() => _FaceLoginScreenState();
}

class _FaceLoginScreenState extends State<FaceLoginScreen> {
  bool _loading = false;
  String? _error;

  Future<void> _login() async {
    final auth = context.read<AuthService>();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final bytes = await FaceCameraService.takeFacePhoto(mode: 'login', hint: '请把脸放进圆框');
      if (bytes == null) return;
      final deviceKey = await auth.getDeviceKey();
      final data = await ApiService.faceLogin(bytes, deviceKey: deviceKey);
      final ok = await auth.acceptFaceLogin(data);
      if (!mounted) return;
      if (!ok) throw Exception('登录响应无效');
      final role = auth.dang_qian_yong_hu?.role ?? 'elder';
      Navigator.of(context).pushAndRemoveUntil(
        ElderPageRoute(page: role == 'child' ? const ChildHomeScreen() : const ElderHomeScreen()),
        (_) => false,
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('刷脸登录')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(22, 2, 22, 28),
          children: [
            const SizedBox(height: 4),
            const Text(
              '请正对手机摄像头',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: AppColors.ink),
            ),
            const SizedBox(height: 8),
            const Text(
              '把脸放进圆框里，手机会自动拍照识别',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: AppColors.muted, height: 1.5),
            ),
            const SizedBox(height: 20),
            Center(child: _FaceScanCircle(loading: _loading)),
            const SizedBox(height: 18),
            const AppNotice(text: '光线充足，摘掉帽子和口罩，识别会更顺利。', icon: Icons.wb_sunny_outlined),
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
            const SizedBox(height: 18),
            AppGradientButton(
              label: '开始刷脸登录',
              icon: Icons.camera_alt_rounded,
              loading: _loading,
              onPressed: _loading ? null : _login,
            ),
            const SizedBox(height: 10),
            AppSecondaryButton(
              label: '使用手机号验证码登录',
              icon: Icons.sms_rounded,
              height: 54,
              fontSize: 16,
              onPressed: () => Navigator.of(
                context,
              ).pushReplacement(ElderPageRoute(page: const PhoneCodeLoginScreen())),
            ),
          ],
        ),
      ),
    );
  }
}

class _FaceScanCircle extends StatelessWidget {
  const _FaceScanCircle({required this.loading});

  final bool loading;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 310,
      height: 310,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 292,
            height: 292,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0x4D42A6E8), width: 1.2),
            ),
          ),
          Container(
            width: 264,
            height: 264,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const RadialGradient(
                center: Alignment.topCenter,
                radius: 0.9,
                colors: [Color(0xFFFFFFFF), Color(0xFFDFF4FF), Color(0xFFBFE5FA)],
              ),
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: AppShadows.card,
            ),
            child: Center(
              child: loading
                  ? const SizedBox(
                      width: 54,
                      height: 54,
                      child: CircularProgressIndicator(strokeWidth: 3, color: AppColors.blue),
                    )
                  : Container(
                      width: 170,
                      height: 170,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.76),
                        shape: BoxShape.circle,
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x1F3C8FD6),
                            blurRadius: 24,
                            offset: Offset(0, 10),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.face_retouching_natural_rounded,
                        size: 84,
                        color: AppColors.blue,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
