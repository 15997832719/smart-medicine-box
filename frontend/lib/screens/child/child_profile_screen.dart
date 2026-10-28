import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/auth_service.dart';
import '../../core/config.dart';
import '../../core/design_system.dart';
import '../../core/theme.dart';
import '../auth/login_screen.dart';
import '../common/delete_account_screen.dart';
import '../common/edit_profile_screen.dart';
import '../common/device_management_screen.dart';
import 'bind_elder_screen.dart';
import 'claim_elder_screen.dart';

class ChildProfileScreen extends StatelessWidget {
  const ChildProfileScreen({super.key, this.showAppBar = true});

  final bool showAppBar;

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthService>().dang_qian_yong_hu;
    final avatarImage = ApiConfig.resolveMediaUrl(user?.avatarUrl);
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: showAppBar ? AppBar(title: const Text('家属中心')) : null,
      body: ListView(
        padding: EdgeInsets.fromLTRB(18, showAppBar ? 4 : 0, 18, 118),
        children: [
          _profileHero(context, user?.nickname ?? '家属用户', user?.phone ?? '', avatarImage),
          const SizedBox(height: 4),
          AppGlassCard(
            radius: 27,
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 5),
            child: Column(
              children: [
                AppMenuTile(
                  icon: Icons.family_restroom_rounded,
                  title: '已绑定老人',
                  iconColor: AppColors.mintDeep,
                  iconBackground: AppColors.mintTint,
                  onTap: () => _push(context, const BindElderScreen()),
                ),
                const Divider(),
                AppMenuTile(
                  icon: Icons.key_rounded,
                  title: '帮家人开通',
                  iconColor: const Color(0xFF278FC4),
                  iconBackground: const Color(0xFFE1F8FF),
                  onTap: () => _push(context, const ClaimElderScreen()),
                ),
                const Divider(),
                AppMenuTile(
                  icon: Icons.notifications_rounded,
                  title: '通知设置',
                  iconColor: const Color(0xFF7659CF),
                  iconBackground: AppColors.lavenderTint,
                  onTap: () => _showInfo(context, '通知设置', '服药提醒、漏服提醒和风险通知会显示在系统通知栏。'),
                ),
                const Divider(),
                AppMenuTile(
                  icon: Icons.shield_outlined,
                  title: '用药安全声明',
                  iconColor: const Color(0xFFD6762D),
                  iconBackground: AppColors.peachTint,
                  onTap: () => _showInfo(context, '用药安全声明', '本系统用于识别、提醒和记录，不替代医生诊断或药师建议。'),
                ),
                const Divider(),
                AppMenuTile(
                  icon: Icons.devices_rounded,
                  title: '设备管理',
                  iconColor: const Color(0xFF267FCF),
                  iconBackground: AppColors.blueTint,
                  onTap: () => _push(context, const DeviceManagementScreen()),
                ),
                const Divider(),
                AppMenuTile(
                  icon: Icons.delete_forever_rounded,
                  title: '删除账号',
                  danger: true,
                  onTap: () => _push(context, const DeleteAccountScreen()),
                ),
              ],
            ),
          ),
          const SizedBox(height: 13),
          AppSecondaryButton(
            label: '退出登录',
            icon: Icons.logout_rounded,
            height: 56,
            fontSize: 19,
            foreground: AppColors.red,
            onPressed: () => _logout(context),
          ),
        ],
      ),
    );
  }

  Widget _profileHero(BuildContext context, String name, String phone, String avatarImage) {
    return SizedBox(
      height: 252,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: Container(
              height: 170,
              decoration: BoxDecoration(
                gradient: AppGradients.hero,
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(38)),
                boxShadow: AppShadows.blue,
              ),
              child: Stack(
                children: [
                  Positioned(
                    right: -50,
                    top: -70,
                    child: Container(
                      width: 190,
                      height: 190,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  const Center(
                    child: Text(
                      '我的',
                      style: TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 108,
            child: AppGlassCard(
              radius: 29,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
              onTap: () => _push(context, const EditProfileScreen()),
              child: Row(
                children: [
                  _editableAvatar(
                    avatarImage,
                    const Color(0xFFE8F8F4),
                    Icons.volunteer_activism_rounded,
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
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            color: AppColors.ink,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          phone.isEmpty ? '已绑定 1 位老人' : phone,
                          style: const TextStyle(fontSize: 16, color: AppColors.muted),
                        ),
                      ],
                    ),
                  ),
                  const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AppPill(
                        label: '家属端',
                        background: AppColors.mintTint,
                        foreground: AppColors.mintDeep,
                        fontSize: 13,
                      ),
                      SizedBox(height: 5),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.edit_rounded, size: 13, color: AppColors.blue),
                          SizedBox(width: 3),
                          Text(
                            '编辑资料',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.blue,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _editableAvatar(String avatarImage, Color tint, IconData fallbackIcon) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        AppAvatar(
          size: 82,
          icon: fallbackIcon,
          tint: tint,
          imageUrl: avatarImage.isEmpty ? null : avatarImage,
        ),
        Positioned(
          right: -1,
          bottom: -1,
          child: Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              gradient: AppGradients.primaryButton,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: AppShadows.soft,
            ),
            child: const Icon(Icons.camera_alt_rounded, size: 13, color: Colors.white),
          ),
        ),
      ],
    );
  }

  void _push(BuildContext context, Widget page) {
    Navigator.of(context).push(ElderPageRoute(page: page));
  }

  void _showInfo(BuildContext context, String title, String content) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(content, style: const TextStyle(fontSize: 17, height: 1.55)),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('知道了'))],
      ),
    );
  }

  Future<void> _logout(BuildContext context) async {
    await context.read<AuthService>().logout();
    if (!context.mounted) return;
    Navigator.of(
      context,
    ).pushAndRemoveUntil(ElderPageRoute(page: const LoginScreen()), (_) => false);
  }
}
