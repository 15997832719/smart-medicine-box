import 'package:flutter/material.dart';

import '../../core/design_system.dart';
import '../../services/api_service.dart';

class SmartBoxFaceIdentityScreen extends StatefulWidget {
  const SmartBoxFaceIdentityScreen({super.key, required this.device});

  final Map<String, dynamic> device;

  @override
  State<SmartBoxFaceIdentityScreen> createState() =>
      _SmartBoxFaceIdentityScreenState();
}

class _SmartBoxFaceIdentityScreenState
    extends State<SmartBoxFaceIdentityScreen> {
  bool _loading = true;
  int? _savingFaceId;
  String? _error;
  List<Map<String, dynamic>> _faces = <Map<String, dynamic>>[];
  Map<String, dynamic> _family = <String, dynamic>{};

  int? get _deviceId => int.tryParse('${widget.device['id']}');

  List<Map<String, dynamic>> get _members {
    final result = <Map<String, dynamic>>[];
    for (final key in ['elders', 'children']) {
      final rows = (_family[key] as List?) ?? const [];
      for (final item in rows.whereType<Map>()) {
        result.add(Map<String, dynamic>.from(item));
      }
    }
    return result;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final deviceId = _deviceId;
    if (deviceId == null) {
      setState(() {
        _loading = false;
        _error = '设备标识无效';
      });
      return;
    }
    setState(() => _error = null);
    try {
      final results = await Future.wait<Object>([
        ApiService.getHardwareDeviceFaces(deviceId),
        ApiService.getMyFamily(),
      ]);
      if (!mounted) return;
      setState(() {
        _faces = (results[0] as List).cast<Map<String, dynamic>>();
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

  Future<void> _editFace(Map<String, dynamic> face) async {
    final choice = await showDialog<_FaceIdentityChoice>(
      context: context,
      builder: (context) => _FaceIdentityDialog(face: face, members: _members),
    );
    if (choice == null) return;
    final deviceId = _deviceId;
    final faceId = int.tryParse('${face['id']}');
    if (deviceId == null || faceId == null) return;
    setState(() => _savingFaceId = faceId);
    try {
      final updated = await ApiService.updateHardwareFaceIdentity(
        deviceId: deviceId,
        faceId: faceId,
        role: choice.role,
        announceUserId: choice.memberId,
      );
      if (!mounted) return;
      setState(() {
        _faces = _faces
            .map((item) => '${item['id']}' == '$faceId' ? updated : item)
            .toList();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_savedMessage(choice.role))),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(error.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _savingFaceId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('人脸身份设置')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 30),
          children: [
            const Center(
              child: AppIconTile(
                icon: Icons.face_6_rounded,
                size: 82,
                iconSize: 42,
                background: AppColors.lavenderTint,
                color: AppColors.lavender,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              '设置每个家庭成员的人脸身份',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '老人会播报老人药箱，子女会播报对应子女药箱，陌生人只记录识别事件，不会播报个人用药。',
              textAlign: TextAlign.center,
              style:
                  TextStyle(fontSize: 13, color: AppColors.muted, height: 1.5),
            ),
            const SizedBox(height: 14),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              AppNotice(text: _error!, icon: Icons.error_outline_rounded)
            else if (_faces.isEmpty)
              const AppNotice(
                text: '还没有设备人脸。请先在“摄像头与服药记录”页面正对摄像头注册人脸，再回来设置身份。',
                icon: Icons.person_add_alt_1_rounded,
              )
            else ...[
              const AppSectionTitle(title: '已注册人脸'),
              for (final face in _faces) ...[
                _faceCard(face),
                const SizedBox(height: 10),
              ],
              const AppNotice(
                text: '修改身份不会重新采集人脸，只改变识别后的播报规则。每次修改会立即同步到后端。',
                icon: Icons.admin_panel_settings_outlined,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _faceCard(Map<String, dynamic> face) {
    final role = '${face['role'] ?? 'elder'}';
    final style = _roleStyle(role);
    final saving = _savingFaceId == int.tryParse('${face['id']}');
    final targetName = _targetName(face);
    return AppGlassCard(
      radius: 21,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          AppIconTile(
            icon: style.$4,
            size: 48,
            iconSize: 25,
            background: style.$2,
            color: style.$3,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${face['display_name'] ?? '家庭成员'}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: AppColors.ink2,
                  ),
                ),
                const SizedBox(height: 5),
                AppPill(
                    label: style.$1,
                    background: style.$2,
                    foreground: style.$3,
                    fontSize: 11),
                const SizedBox(height: 7),
                Text(
                  targetName,
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.muted, height: 1.4),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          saving
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                )
              : IconButton(
                  tooltip: '修改身份',
                  onPressed: () => _editFace(face),
                  icon: const Icon(Icons.tune_rounded, color: AppColors.blue),
                ),
        ],
      ),
    );
  }

  String _targetName(Map<String, dynamic> face) {
    final role = '${face['role']}';
    if (role == 'stranger') return '播报药箱：无，不播报个人用药';
    final targetId = int.tryParse('${face['announce_user_id']}');
    Map<String, dynamic>? member;
    for (final item in _members) {
      if (int.tryParse('${item['id']}') == targetId) {
        member = item;
        break;
      }
    }
    final name =
        member?['nickname'] ?? member?['phone'] ?? face['display_name'];
    return role == 'child' ? '播报药箱：$name 的子女药箱' : '播报药箱：$name 的老人药箱';
  }
}

class _FaceIdentityChoice {
  const _FaceIdentityChoice(this.role, this.memberId);

  final String role;
  final int? memberId;
}

class _FaceIdentityDialog extends StatefulWidget {
  const _FaceIdentityDialog({required this.face, required this.members});

  final Map<String, dynamic> face;
  final List<Map<String, dynamic>> members;

  @override
  State<_FaceIdentityDialog> createState() => _FaceIdentityDialogState();
}

class _FaceIdentityDialogState extends State<_FaceIdentityDialog> {
  late String _role;
  int? _memberId;

  List<Map<String, dynamic>> get _eligibleMembers =>
      widget.members.where((item) => '${item['role']}' == _role).toList();

  @override
  void initState() {
    super.initState();
    final rawRole = '${widget.face['role'] ?? 'elder'}';
    _role =
        ['elder', 'child', 'stranger'].contains(rawRole) ? rawRole : 'elder';
    final initialId = int.tryParse('${widget.face['announce_user_id']}');
    _memberId = _eligibleMembers
            .any((item) => int.tryParse('${item['id']}') == initialId)
        ? initialId
        : (_eligibleMembers.isEmpty
            ? null
            : int.tryParse('${_eligibleMembers.first['id']}'));
  }

  void _setRole(String role) {
    setState(() {
      _role = role;
      if (role == 'stranger') {
        _memberId = null;
      } else {
        final candidates =
            widget.members.where((item) => '${item['role']}' == role).toList();
        _memberId = candidates.isEmpty
            ? null
            : int.tryParse('${candidates.first['id']}');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final canSave = _role == 'stranger' || _memberId != null;
    return AlertDialog(
      title: const Text('设置人脸身份'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '人脸：${widget.face['display_name'] ?? '家庭成员'}',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 16),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                    value: 'elder',
                    label: Text('老人'),
                    icon: Icon(Icons.elderly_rounded)),
                ButtonSegment(
                    value: 'child',
                    label: Text('子女'),
                    icon: Icon(Icons.family_restroom_rounded)),
                ButtonSegment(
                    value: 'stranger',
                    label: Text('陌生人'),
                    icon: Icon(Icons.person_off_rounded)),
              ],
              selected: {_role},
              onSelectionChanged: (values) => _setRole(values.first),
              showSelectedIcon: false,
            ),
            const SizedBox(height: 16),
            if (_role != 'stranger') ...[
              const Text('播报谁的药箱',
                  style: TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              if (_eligibleMembers.isEmpty)
                Text(
                  _role == 'elder' ? '当前家庭没有老人成员' : '当前家庭还没有绑定子女',
                  style: const TextStyle(color: AppColors.red, fontSize: 13),
                )
              else
                DropdownButtonFormField<int>(
                  initialValue: _memberId,
                  decoration: const InputDecoration(labelText: '家庭成员'),
                  items: _eligibleMembers.map((item) {
                    return DropdownMenuItem<int>(
                      value: int.tryParse('${item['id']}'),
                      child: Text(
                          '${item['nickname'] ?? item['phone'] ?? '家庭成员'}'),
                    );
                  }).toList(),
                  onChanged: (value) => setState(() => _memberId = value),
                ),
            ] else
              const AppNotice(
                text: '陌生人不会播报任何个人药品信息。',
                icon: Icons.volume_off_rounded,
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(
          onPressed: canSave
              ? () =>
                  Navigator.pop(context, _FaceIdentityChoice(_role, _memberId))
              : null,
          child: const Text('保存'),
        ),
      ],
    );
  }
}

String _savedMessage(String role) {
  if (role == 'stranger') return '已设为陌生人，不播报个人用药';
  if (role == 'child') return '已设为子女，将播报对应的子女药箱';
  return '已设为老人，将播报对应的老人药箱';
}

(String, Color, Color, IconData) _roleStyle(String role) {
  if (role == 'child') {
    return (
      '子女',
      AppColors.blueTint,
      AppColors.blueDeep,
      Icons.family_restroom_rounded
    );
  }
  if (role == 'stranger') {
    return (
      '陌生人',
      const Color(0xFFF1F4F7),
      AppColors.muted,
      Icons.person_off_rounded
    );
  }
  return ('老人', AppColors.mintTint, AppColors.mintDeep, Icons.elderly_rounded);
}
