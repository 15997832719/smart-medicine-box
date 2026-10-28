import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/auth_service.dart';
import '../../core/design_system.dart';
import '../../services/api_service.dart';
import 'smart_box_device_screen.dart';

class DeviceManagementScreen extends StatefulWidget {
  const DeviceManagementScreen({super.key});

  @override
  State<DeviceManagementScreen> createState() => _DeviceManagementScreenState();
}

class _DeviceManagementScreenState extends State<DeviceManagementScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _devices = <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final devices = await ApiService.getAuthDevices();
      if (!mounted) return;
      setState(() {
        _devices = devices.where((item) => item['revoked_at'] == null).toList();
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _revoke(int id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('撤销设备'),
        content: const Text('撤销后，这台设备需要重新完成家属代办开通，确定继续吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('撤销')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ApiService.revokeAuthDevice(id);
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _revokeAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('撤销全部设备'),
        content: const Text('所有已绑定设备都将退出快捷登录，需要重新开通。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('全部撤销')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ApiService.revokeAllAuthDevices();
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentDeviceId = context.watch<AuthService>().deviceId;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('设备管理')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 2, 18, 28),
          children: [
            const Center(
              child: AppIconTile(
                icon: Icons.devices_rounded,
                size: 98,
                iconSize: 50,
                background: Color(0xFFE3F8FF),
                color: Color(0xFF318EDC),
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              '设备快捷登录',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: AppColors.ink),
            ),
            const SizedBox(height: 7),
            const Text(
              '只显示当前账号的设备，撤销后需要重新开通',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: AppColors.muted),
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(30),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              _messageCard(_error!, retry: true)
            else if (_devices.isEmpty)
              _messageCard('当前没有已绑定设备')
            else
              for (final device in _devices)
                Padding(
                  padding: const EdgeInsets.only(bottom: 9),
                  child: _deviceTile(device, currentDeviceId: currentDeviceId),
                ),
            const SizedBox(height: 12),
            AppGlassCard(
              radius: 22,
              padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
              onTap: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const SmartBoxDeviceScreen()))
                  .then((_) => _load()),
              child: const Row(
                children: [
                  AppIconTile(
                    icon: Icons.videocam_rounded,
                    size: 46,
                    iconSize: 24,
                    background: Color(0xFFE3F8FF),
                    color: Color(0xFF318EDC),
                  ),
                  SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '智能药箱设备',
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.ink),
                        ),
                        SizedBox(height: 3),
                        Text(
                          '摄像头、人脸注册与识别测试',
                          style: TextStyle(fontSize: 12, color: AppColors.muted2),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, color: AppColors.muted),
                ],
              ),
            ),
            const SizedBox(height: 7),
            const AppNotice(text: '撤销后，该设备需要重新完成家属代办开通，才能继续快捷登录。', icon: Icons.shield_outlined),
            if (!_loading && _devices.isNotEmpty) ...[
              const SizedBox(height: 12),
              AppSecondaryButton(
                label: '重新加载',
                icon: Icons.refresh_rounded,
                height: 52,
                onPressed: _load,
              ),
              const SizedBox(height: 9),
              AppSecondaryButton(
                label: '撤销全部设备',
                icon: Icons.logout_rounded,
                height: 52,
                foreground: AppColors.red,
                onPressed: _revokeAll,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _deviceTile(Map<String, dynamic> device, {String? currentDeviceId}) {
    final id = int.tryParse('${device['id']}');
    final deviceId = device['device_id']?.toString() ?? '';
    final isCurrent = currentDeviceId != null && currentDeviceId == deviceId;
    final platform = device['platform']?.toString() ?? 'unknown';
    final lastSeen = device['last_seen_at']?.toString() ?? '';
    return AppGlassCard(
      radius: 22,
      padding: const EdgeInsets.fromLTRB(13, 12, 10, 12),
      child: Row(
        children: [
          AppIconTile(
            icon: isCurrent ? Icons.phone_android_rounded : Icons.devices_other_rounded,
            size: 46,
            iconSize: 24,
            background: isCurrent ? AppColors.blueTint : const Color(0xFFE3F8FF),
            color: isCurrent ? AppColors.blue : const Color(0xFF278FC4),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        isCurrent ? '本机 · ${_platformName(platform)}' : _platformName(platform),
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: AppColors.ink,
                        ),
                      ),
                    ),
                    AppPill(
                      label: isCurrent ? '当前设备' : '已绑定',
                      background: isCurrent ? AppColors.mintTint : AppColors.blueTint,
                      foreground: isCurrent ? AppColors.mintDeep : const Color(0xFF2676C9),
                      fontSize: 11,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '设备标识：${deviceId.length > 12 ? '${deviceId.substring(0, 12)}…' : deviceId}\n最近使用：$lastSeen',
                  style: const TextStyle(fontSize: 12, color: AppColors.muted2, height: 1.45),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: id == null ? null : () => _revoke(id),
            child: const Text('撤销', style: TextStyle(fontSize: 14)),
          ),
        ],
      ),
    );
  }

  Widget _messageCard(String text, {bool retry = false}) {
    return AppGlassCard(
      radius: 24,
      padding: const EdgeInsets.fromLTRB(18, 24, 18, 20),
      child: Column(
        children: [
          const AppIconTile(
            icon: Icons.devices_other_rounded,
            size: 68,
            iconSize: 34,
            background: AppColors.blueTint,
          ),
          const SizedBox(height: 13),
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, color: AppColors.muted, height: 1.5),
          ),
          if (retry) ...[
            const SizedBox(height: 14),
            AppSecondaryButton(
              label: '重新加载',
              icon: Icons.refresh_rounded,
              height: 50,
              onPressed: _load,
            ),
          ],
        ],
      ),
    );
  }

  String _platformName(String value) {
    switch (value.toLowerCase()) {
      case 'ohos':
        return '鸿蒙设备';
      case 'android':
        return 'Android 设备';
      case 'ios':
        return 'iPhone';
      default:
        return '其他设备';
    }
  }
}
