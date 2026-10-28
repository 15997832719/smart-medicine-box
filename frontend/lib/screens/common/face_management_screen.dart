import 'package:flutter/material.dart';

import '../../core/design_system.dart';
import '../../core/theme.dart';
import '../../services/api_service.dart';
import '../auth/face_enroll_screen.dart';

class FaceManagementScreen extends StatefulWidget {
  const FaceManagementScreen({super.key});

  @override
  State<FaceManagementScreen> createState() => _FaceManagementScreenState();
}

class _FaceManagementScreenState extends State<FaceManagementScreen> {
  bool _loading = true;
  Map<String, dynamic> _status = <String, dynamic>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await ApiService.faceStatus();
      if (!mounted) return;
      setState(() => _status = data);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除人脸数据'),
        content: const Text('删除后无法继续刷脸登录，只能使用手机号验证码登录。确定删除吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('删除')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ApiService.deleteFace();
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    final enrolled = _status['enrolled'] == true;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('人脸数据管理')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 2, 20, 28),
              children: [
                AppGlassCard(
                  radius: 28,
                  padding: const EdgeInsets.fromLTRB(18, 22, 18, 18),
                  child: Column(
                    children: [
                      AppAvatar(
                        size: 112,
                        tint: enrolled ? const Color(0xFFE3F8FF) : const Color(0xFFF1F4F7),
                      ),
                      const SizedBox(height: 13),
                      Text(
                        enrolled ? '已录入人脸数据' : '尚未录入人脸数据',
                        style: const TextStyle(
                          fontSize: 25,
                          fontWeight: FontWeight.w900,
                          color: AppColors.ink,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        '服务商：${_status['provider'] ?? '未配置'} · 状态：${_status['status'] ?? '未录入'}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 14, color: AppColors.muted),
                      ),
                      if (enrolled) ...[
                        const SizedBox(height: 10),
                        const AppPill(
                          label: '刷脸登录已开启',
                          background: AppColors.mintTint,
                          foreground: AppColors.mintDeep,
                          fontSize: 12,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                const AppSectionTitle(title: '隐私说明'),
                AppGlassCard(
                  radius: 22,
                  padding: const EdgeInsets.fromLTRB(15, 13, 15, 10),
                  child: const Column(
                    children: [
                      _Bullet('人脸信息仅用于登录身份核验。'),
                      _Bullet('人脸数据采用加密方式保存。'),
                      _Bullet('你可以随时申请删除，删除后使用验证码登录。'),
                    ],
                  ),
                ),
                const SizedBox(height: 13),
                Row(
                  children: [
                    Expanded(
                      child: AppSecondaryButton(
                        label: enrolled ? '重新录入' : '录入人脸',
                        icon: Icons.camera_alt_rounded,
                        height: 54,
                        fontSize: 16,
                        onPressed: () => Navigator.of(
                          context,
                        ).push(ElderPageRoute(page: const FaceEnrollScreen())).then((_) => _load()),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: AppSecondaryButton(
                        label: '申请删除',
                        icon: Icons.delete_outline_rounded,
                        height: 54,
                        fontSize: 16,
                        foreground: AppColors.red,
                        onPressed: enrolled ? _delete : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 11),
                const AppNotice(text: '删除人脸数据不会影响药品、计划和历史服药记录。', icon: Icons.info_outline_rounded),
              ],
            ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.text);

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
            decoration: const BoxDecoration(color: Color(0xFF65B8E8), shape: BoxShape.circle),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 15, height: 1.5, color: AppColors.ink2),
            ),
          ),
        ],
      ),
    );
  }
}
