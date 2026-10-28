import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/auth_service.dart';
import '../../core/design_system.dart';
import '../../core/theme.dart';
import '../../services/api_service.dart';
import '../../services/face_camera_service.dart';
import '../child/child_home_screen.dart';
import '../elder/elder_home_screen.dart';

class FaceEnrollScreen extends StatefulWidget {
  const FaceEnrollScreen({super.key});

  @override
  State<FaceEnrollScreen> createState() => _FaceEnrollScreenState();
}

class _FaceEnrollScreenState extends State<FaceEnrollScreen> {
  bool _loading = false;
  Uint8List? _imageBytes;

  Future<void> _pick() async {
    try {
      final bytes = await FaceCameraService.takeFacePhoto(mode: 'enroll', hint: '请把脸放进圆框');
      if (!mounted || bytes == null) return;
      setState(() => _imageBytes = bytes);
    } on FaceCaptureException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message), backgroundColor: ElderTheme.errorColor),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
          backgroundColor: ElderTheme.errorColor,
        ),
      );
    }
  }

  Future<void> _submit({bool skip = false}) async {
    if (skip) {
      _goHome();
      return;
    }
    final bytes = _imageBytes;
    if (bytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请先拍摄一张清晰的正脸照片')));
      return;
    }
    setState(() => _loading = true);
    final auth = context.read<AuthService>();
    try {
      await ApiService.recordFaceConsent();
      final deviceKey = await auth.getDeviceKey();
      await ApiService.enrollFace(bytes, deviceKey: deviceKey);
      if (!mounted) return;
      _goHome();
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

  void _goHome() {
    final role = context.read<AuthService>().dang_qian_yong_hu?.role ?? 'elder';
    Navigator.of(context).pushAndRemoveUntil(
      ElderPageRoute(page: role == 'child' ? const ChildHomeScreen() : const ElderHomeScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _imageBytes;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('录入人脸')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(22, 2, 22, 28),
          children: [
            Text(
              FaceCameraService.runningOnOhos ? '把脸放进圆框' : '请正对手机拍正脸',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w900,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '人脸照片只用于登录核验，并会加密保存',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: AppColors.muted, height: 1.5),
            ),
            const SizedBox(height: 18),
            Container(
              height: 300,
              decoration: BoxDecoration(
                gradient: AppGradients.glass,
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: Colors.white, width: 1.2),
                boxShadow: AppShadows.card,
              ),
              clipBehavior: Clip.antiAlias,
              child: bytes == null
                  ? Center(
                      child: Container(
                        width: 210,
                        height: 210,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const RadialGradient(colors: [Colors.white, Color(0xFFDCF3FF)]),
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: const Icon(
                          Icons.face_retouching_natural_rounded,
                          size: 104,
                          color: AppColors.blue,
                        ),
                      ),
                    )
                  : Image.memory(bytes, fit: BoxFit.cover),
            ),
            const SizedBox(height: 14),
            const AppNotice(text: '光线充足，摘掉帽子和口罩，正对手机。', icon: Icons.wb_sunny_outlined),
            const SizedBox(height: 16),
            AppSecondaryButton(
              label: bytes == null ? '拍摄人脸照片' : '重新拍摄',
              icon: Icons.camera_alt_rounded,
              height: 58,
              onPressed: _loading ? null : _pick,
            ),
            const SizedBox(height: 10),
            AppGradientButton(
              label: '完成录入',
              icon: Icons.check_circle_rounded,
              gradient: AppGradients.mintButton,
              loading: _loading,
              onPressed: _loading ? null : () => _submit(),
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: _loading ? null : () => _submit(skip: true),
              child: const Text('以后再说'),
            ),
          ],
        ),
      ),
    );
  }
}
