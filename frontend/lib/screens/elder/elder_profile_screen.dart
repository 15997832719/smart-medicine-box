import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/auth_service.dart';
import '../../core/theme.dart';
import '../auth/login_screen.dart';
import 'elder_bind_child_screen.dart';
import 'speaker_bind_screen.dart';

class ElderProfileScreen extends StatelessWidget {
  const ElderProfileScreen({super.key, this.showAppBar = true});

  
  final bool showAppBar;

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthService>().dang_qian_yong_hu;
    return Scaffold(
      backgroundColor: ElderTheme.bgColor,
      appBar: showAppBar ? AppBar(title: const Text('个人中心')) : null,
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _profileCard(user?.nickname ?? '老人用户', user?.phone ?? ''),
          const SizedBox(height: 14),
          _menuItem(context, Icons.family_restroom_rounded, '绑定家属账号', '生成邀请码，让家属端绑定查看', const ElderBindChildScreen()),
          _infoItem(Icons.privacy_tip_outlined, '用药安全声明', '本系统用于提醒和记录，不替代医生诊断。'),
          _menuItem(context, Icons.speaker_rounded, '音箱接入', '生成配对码，把小度音箱连到这台账号', const SpeakerBindScreen()),
          const SizedBox(height: 18),
          OutlinedButton.icon(
            onPressed: () => _logout(context),
            icon: const Icon(Icons.logout_rounded),
            label: const Text('退出登录'),
          ),
        ],
      ),
    );
  }

  Widget _profileCard(String name, String phone) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: ElderTheme.cardColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 34,
            backgroundColor: ElderTheme.primaryColor.withOpacity(0.12),
            child: const Icon(Icons.elderly_rounded, color: ElderTheme.primaryColor, size: 38),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(phone, style: const TextStyle(color: ElderTheme.textSecondary)),
              ],
            ),
          ),
          const Chip(label: Text('老人端')),
        ],
      ),
    );
  }

  Widget _menuItem(BuildContext context, IconData icon, String title, String subtitle, Widget page) {
    return _tile(
      icon,
      title,
      subtitle,
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () => Navigator.of(context).push(ElderPageRoute(page: page)),
    );
  }

  Widget _infoItem(IconData icon, String title, String subtitle) {
    return _tile(icon, title, subtitle);
  }

  Widget _tile(IconData icon, String title, String subtitle, {Widget? trailing, VoidCallback? onTap}) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        onTap: onTap,
        leading: Icon(icon, color: ElderTheme.primaryColor),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(subtitle),
        trailing: trailing,
      ),
    );
  }

  Future<void> _logout(BuildContext context) async {
    await context.read<AuthService>().logout();
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(ElderPageRoute(page: const LoginScreen()), (_) => false);
  }
}
