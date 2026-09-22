import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/auth_service.dart';
import '../../core/theme.dart';
import '../auth/login_screen.dart';
import 'bind_elder_screen.dart';

class ChildProfileScreen extends StatelessWidget {
  const ChildProfileScreen({super.key, this.showAppBar = true});

  
  final bool showAppBar;

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthService>().dang_qian_yong_hu;

    return Scaffold(
      backgroundColor: ElderTheme.bgColor,
      appBar: showAppBar ? AppBar(title: const Text('家属中心')) : null,
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _profileCard(
            name: user?.nickname ?? '家属用户',
            phone: user?.phone ?? '',
          ),
          const SizedBox(height: 14),
          _menuItem(
            context,
            icon: Icons.family_restroom_rounded,
            title: '已绑定老人',
            subtitle: '查看当前守护对象，也可以使用邀请码重新绑定',
            page: const BindElderScreen(),
          ),
          _infoItem(
            icon: Icons.notifications_active_outlined,
            title: '通知设置',
            subtitle: '服药提醒、漏服提醒和风险通知会显示在系统通知栏',
          ),
          _infoItem(
            icon: Icons.privacy_tip_outlined,
            title: '用药安全声明',
            subtitle: '本系统用于识别、提醒和记录，不替代医生诊断或药师建议',
          ),
          _infoItem(
            icon: Icons.speaker_rounded,
            title: '智能音箱接入',
            subtitle: '请用老人账号登录后，在「我的 → 音箱接入」里生成配对码',
          ),
          _infoItem(
            icon: Icons.cloud_done_outlined,
            title: '团队运维方式',
            subtitle: 'App 调用同一个后端接口，药品、计划、日志都保存在云端数据库',
          ),
          const SizedBox(height: 18),
          OutlinedButton.icon(
            onPressed: () => _logout(context),
            icon: const Icon(Icons.logout_rounded),
            label: const Text('退出登录'),
            style: OutlinedButton.styleFrom(
              foregroundColor: ElderTheme.errorColor,
              side: const BorderSide(color: ElderTheme.errorColor, width: 1.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _profileCard({required String name, required String phone}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: ElderTheme.cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 34,
            backgroundColor: ElderTheme.successColor.withOpacity(0.12),
            child: const Icon(
              Icons.volunteer_activism_rounded,
              color: ElderTheme.successColor,
              size: 38,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  phone,
                  style: const TextStyle(fontSize: 16, color: ElderTheme.textSecondary),
                ),
              ],
            ),
          ),
          const Chip(label: Text('家属端')),
        ],
      ),
    );
  }

  Widget _menuItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget page,
  }) {
    return _tile(
      icon: icon,
      title: title,
      subtitle: subtitle,
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () => Navigator.of(context).push(ElderPageRoute(page: page)),
    );
  }

  Widget _infoItem({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return _tile(icon: icon, title: title, subtitle: subtitle);
  }

  Widget _tile({
    required IconData icon,
    required String title,
    required String subtitle,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Icon(icon, color: ElderTheme.primaryColor, size: 30),
        title: Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(subtitle, style: const TextStyle(fontSize: 14)),
        ),
        trailing: trailing,
      ),
    );
  }

  Future<void> _logout(BuildContext context) async {
    await context.read<AuthService>().logout();
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      ElderPageRoute(page: const LoginScreen()),
      (_) => false,
    );
  }
}
