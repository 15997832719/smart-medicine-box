import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/design_system.dart';
import '../../services/api_service.dart';
import 'smart_box_camera_screen.dart';
import 'smart_box_face_identity_screen.dart';

class SmartBoxDeviceScreen extends StatefulWidget {
  const SmartBoxDeviceScreen({super.key});

  @override
  State<SmartBoxDeviceScreen> createState() => _SmartBoxDeviceScreenState();
}

class _SmartBoxDeviceScreenState extends State<SmartBoxDeviceScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _devices = <Map<String, dynamic>>[];
  Map<String, dynamic> _family = <String, dynamic>{};

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
      final results = await Future.wait<Object>([
        ApiService.getHardwareDevices(),
        ApiService.getMyFamily(),
      ]);
      if (!mounted) return;
      setState(() {
        _devices = (results[0] as List).cast<Map<String, dynamic>>();
        _family = Map<String, dynamic>.from(results[1] as Map);
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

  List<Map<String, dynamic>> get _elders =>
      ((_family['elders'] as List?) ?? const [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();

  List<Map<String, dynamic>> get _members {
    final result = <Map<String, dynamic>>[];
    for (final key in ['elders', 'children']) {
      final rows = ((_family[key] as List?) ?? const []);
      for (final item in rows.whereType<Map>()) {
        final map = Map<String, dynamic>.from(item);
        if (int.tryParse('${map['id']}') != null) result.add(map);
      }
    }
    return result;
  }

  Future<void> _addDevice() async {
    if (_elders.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先在家庭绑定中添加老人')),
      );
      return;
    }
    final uid = TextEditingController(text: 'orangepi-001');
    final name = TextEditingController(text: '客厅智能药箱');
    final owner = ValueNotifier<int>(int.parse('${_elders.first['id']}'));
    final created = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('添加智能药箱'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: '设备名称'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: uid,
                decoration: const InputDecoration(
                  labelText: '设备标识',
                  hintText: 'orangepi-001',
                ),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<int>(
                initialValue: owner.value,
                decoration: const InputDecoration(labelText: '所属老人'),
                items: _elders
                    .map(
                      (item) => DropdownMenuItem<int>(
                        value: int.parse('${item['id']}'),
                        child: Text(
                            '${item['nickname'] ?? item['phone'] ?? '老人'}'),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) owner.value = value;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          FilledButton(
            onPressed: () async {
              try {
                await ApiService.createHardwareDevice(
                  deviceUid: uid.text.trim(),
                  name: name.text.trim(),
                  ownerId: owner.value,
                );
                if (!context.mounted) return;
                Navigator.pop(context, true);
              } catch (error) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(error.toString())),
                );
              }
            },
            child: const Text('添加'),
          ),
        ],
      ),
    );
    uid.dispose();
    name.dispose();
    owner.dispose();
    if (created == true) await _load();
  }

  Future<void> _enrollFace(Map<String, dynamic> device) async {
    final deviceId = int.tryParse('${device['id']}');
    if (deviceId == null) return;
    final member = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('选择要注册的成员'),
        children: _members
            .map(
              (item) => SimpleDialogOption(
                onPressed: () => Navigator.pop(context, item),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      const Icon(Icons.person_rounded),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                            '${item['nickname'] ?? item['phone'] ?? '家庭成员'}'),
                      ),
                      Text(
                        item['role'] == 'child' ? '子女' : '老人',
                        style: const TextStyle(
                            color: AppColors.muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
    if (member == null) return;
    final command = await ApiService.createHardwareDeviceCommand(
      deviceId: deviceId,
      commandType: 'face_enroll',
      payload: {'user_id': int.parse('${member['id']}'), 'samples': 5},
    );
    await _showCommandProgress(deviceId, command, title: '人脸注册');
    await _load();
  }

  Future<void> _testRecognition(Map<String, dynamic> device) async {
    final deviceId = int.tryParse('${device['id']}');
    if (deviceId == null) return;
    final command = await ApiService.createHardwareDeviceCommand(
      deviceId: deviceId,
      commandType: 'face_recognize',
    );
    await _showCommandProgress(deviceId, command, title: '识别测试');
    await _load();
  }

  Future<void> _deleteFace(
      Map<String, dynamic> device, Map<String, dynamic> face) async {
    final deviceId = int.tryParse('${device['id']}');
    final userId = int.tryParse('${face['user_id']}');
    if (deviceId == null || userId == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除设备人脸'),
        content: Text('确定删除 ${face['display_name'] ?? '该成员'} 在本设备上的人脸模板吗？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('删除')),
        ],
      ),
    );
    if (confirmed != true) return;
    final command = await ApiService.createHardwareDeviceCommand(
      deviceId: deviceId,
      commandType: 'face_delete',
      payload: {'user_id': userId},
    );
    await _showCommandProgress(deviceId, command, title: '删除人脸');
    await _load();
  }

  Future<void> _showCommandProgress(
    int deviceId,
    Map<String, dynamic> command, {
    required String title,
  }) async {
    final commandId = int.tryParse('${command['id']}');
    if (commandId == null) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _CommandProgressDialog(
        deviceId: deviceId,
        commandId: commandId,
        title: title,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('智能药箱设备')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 30),
          children: [
            const Center(
              child: AppIconTile(
                icon: Icons.videocam_rounded,
                size: 88,
                iconSize: 44,
                background: Color(0xFFE3F8FF),
                color: Color(0xFF318EDC),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              '摄像头与人脸',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  color: AppColors.ink),
            ),
            const SizedBox(height: 6),
            const Text(
              '这里的设备绑定用于摄像头识别和雷达播报，不影响手机快捷登录。',
              textAlign: TextAlign.center,
              style:
                  TextStyle(fontSize: 14, color: AppColors.muted, height: 1.5),
            ),
            const SizedBox(height: 14),
            AppGradientButton(
              label: '添加智能药箱',
              icon: Icons.add_rounded,
              height: 52,
              fontSize: 17,
              onPressed: _addDevice,
            ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(30),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              AppNotice(text: _error!, icon: Icons.error_outline_rounded)
            else if (_devices.isEmpty)
              const AppNotice(
                text: '还没有添加智能药箱。添加后会在这里注册老人和子女的人脸。',
                icon: Icons.devices_other_rounded,
              )
            else
              for (final device in _devices) ...[
                const SizedBox(height: 12),
                _deviceCard(device),
              ],
            const SizedBox(height: 12),
            const AppNotice(
              text: '人脸模板存储在香橙派本地。识别失败或未注册人员不会播报个人药品信息。',
              icon: Icons.shield_outlined,
            ),
          ],
        ),
      ),
    );
  }

  Widget _deviceCard(Map<String, dynamic> device) {
    final faces = ((device['faces'] as List?) ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    final online = '${device['status']}' == 'online';
    return AppGlassCard(
      radius: 24,
      padding: const EdgeInsets.fromLTRB(15, 14, 15, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AppIconTile(
                icon: Icons.developer_board_rounded,
                size: 46,
                iconSize: 25,
                background:
                    online ? AppColors.mintTint : const Color(0xFFF1F4F7),
                color: online ? AppColors.mintDeep : AppColors.muted,
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${device['name'] ?? '智能药箱'}',
                      style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: AppColors.ink),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${device['device_uid'] ?? ''}',
                      style:
                          const TextStyle(fontSize: 12, color: AppColors.muted),
                    ),
                  ],
                ),
              ),
              AppPill(
                label: online ? '在线' : '离线',
                background:
                    online ? AppColors.mintTint : const Color(0xFFF1F4F7),
                foreground: online ? AppColors.mintDeep : AppColors.muted,
                fontSize: 12,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              AppPill(
                label: device['camera_ready'] == true ? '摄像头正常' : '摄像头未就绪',
                icon: Icons.videocam_rounded,
                fontSize: 11,
              ),
              AppPill(
                label: device['radar_ready'] == true ? '雷达正常' : '雷达未就绪',
                icon: Icons.sensors_rounded,
                fontSize: 11,
              ),
              AppPill(
                label: device['tts_ready'] == true ? '播报正常' : '播报未就绪',
                icon: Icons.volume_up_rounded,
                fontSize: 11,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: AppSecondaryButton(
                  label: '注册人脸',
                  icon: Icons.face_retouching_natural_rounded,
                  height: 46,
                  fontSize: 14,
                  onPressed: () => _enrollFace(device),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: AppSecondaryButton(
                  label: '测试识别',
                  icon: Icons.center_focus_strong_rounded,
                  height: 46,
                  fontSize: 14,
                  onPressed: () => _testRecognition(device),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          AppSecondaryButton(
            label: '摄像头抓拍与服药录像',
            icon: Icons.photo_camera_back_rounded,
            height: 46,
            fontSize: 14,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => SmartBoxCameraScreen(device: device),
              ),
            ),
          ),
          const SizedBox(height: 8),
          AppSecondaryButton(
            label: '人脸身份设置',
            icon: Icons.manage_accounts_rounded,
            height: 46,
            fontSize: 14,
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute(
                  builder: (_) => SmartBoxFaceIdentityScreen(device: device),
                ))
                .then((_) => _load()),
          ),
          const SizedBox(height: 10),
          const Text('已注册成员',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink2)),
          const SizedBox(height: 6),
          if (faces.isEmpty)
            const Text('暂无设备人脸',
                style: TextStyle(fontSize: 13, color: AppColors.muted))
          else
            for (final face in faces)
              Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Row(
                  children: [
                    const Icon(Icons.person_rounded,
                        size: 18, color: AppColors.blue),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        '${face['display_name'] ?? '家庭成员'} · ${face['sample_count'] ?? 0} 张',
                        style: const TextStyle(
                            fontSize: 13, color: AppColors.ink2),
                      ),
                    ),
                    TextButton(
                      onPressed: () => _deleteFace(device, face),
                      child: const Text('删除', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

class _CommandProgressDialog extends StatefulWidget {
  const _CommandProgressDialog({
    required this.deviceId,
    required this.commandId,
    required this.title,
  });

  final int deviceId;
  final int commandId;
  final String title;

  @override
  State<_CommandProgressDialog> createState() => _CommandProgressDialogState();
}

class _CommandProgressDialogState extends State<_CommandProgressDialog> {
  String _status = 'pending';
  Map<String, dynamic>? _result;
  String? _error;
  Timer? _timer;
  int _polls = 0;

  @override
  void initState() {
    super.initState();
    _poll();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _poll() async {
    if (!mounted) return;
    if (_polls++ > 90) {
      setState(() => _error = '设备长时间没有响应，请检查香橙派电源和网络');
      return;
    }
    try {
      final command = await ApiService.getHardwareDeviceCommand(
        deviceId: widget.deviceId,
        commandId: widget.commandId,
      );
      if (!mounted) return;
      final status = '${command['status']}';
      setState(() {
        _status = status;
        _result = command['result'] is Map
            ? Map<String, dynamic>.from(command['result'] as Map)
            : null;
        _error = command['error']?.toString();
      });
      if (status == 'completed' || status == 'failed' || status == 'expired') {
        return;
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    }
  }

  bool get _done =>
      _status == 'completed' ||
      _status == 'failed' ||
      _status == 'expired' ||
      _error != null;

  @override
  Widget build(BuildContext context) {
    final result = _result ?? const <String, dynamic>{};
    final identity = result['identity'] ?? result['name'];
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!_done) ...[
            const LinearProgressIndicator(),
            const SizedBox(height: 14),
            Text(
              _status == 'claimed' ? '设备正在执行，请正对摄像头…' : '等待香橙派接收任务…',
              style: const TextStyle(height: 1.5),
            ),
          ] else if (_status == 'completed') ...[
            const Icon(Icons.check_circle_rounded,
                color: AppColors.mintDeep, size: 42),
            const SizedBox(height: 10),
            Text(
              identity == null ? '操作完成' : '识别结果：$identity',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            if (result['score'] != null) ...[
              const SizedBox(height: 6),
              Text('置信度：${result['score']}'),
            ],
            if (result['sample_count'] != null) ...[
              const SizedBox(height: 6),
              Text('已采集：${result['sample_count']} 张'),
            ],
          ] else ...[
            const Icon(Icons.error_outline_rounded,
                color: AppColors.red, size: 42),
            const SizedBox(height: 10),
            Text(_error ?? '操作失败', style: const TextStyle(height: 1.5)),
          ],
        ],
      ),
      actions: [
        if (_done)
          FilledButton(
              onPressed: () => Navigator.pop(context), child: const Text('完成')),
      ],
    );
  }
}
