import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/auth_service.dart';
import '../../core/config.dart';
import '../../core/design_system.dart';
import '../../services/api_service.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nicknameController = TextEditingController();
  final _emergencyNameController = TextEditingController();
  final _emergencyPhoneController = TextEditingController();
  final _allergyController = TextEditingController();
  final _picker = ImagePicker();

  String? _gender;
  DateTime? _birthDate;
  String? _avatarUrl;
  bool _saving = false;
  bool _uploadingAvatar = false;

  @override
  void initState() {
    super.initState();
    _fillFromUser(context.read<AuthService>().dang_qian_yong_hu);
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshFromServer());
  }

  void _fillFromUser(User? user) {
    if (user == null) return;
    _nicknameController.text = user.nickname ?? '';
    _gender = user.gender;
    _birthDate = user.birthDate;
    _emergencyNameController.text = user.emergencyContactName ?? '';
    _emergencyPhoneController.text = user.emergencyContactPhone ?? '';
    _allergyController.text = user.allergyNotes ?? '';
    _avatarUrl = user.avatarUrl;
  }

  Future<void> _refreshFromServer() async {
    try {
      final profile = await ApiService.getProfile();
      if (!mounted) return;
      await context.read<AuthService>().applyProfile(profile);
      if (!mounted) return;
      final user = context.read<AuthService>().dang_qian_yong_hu;
      setState(() => _fillFromUser(user));
    } catch (_) {
      // Local session data remains usable when the network is temporarily unavailable.
    }
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    _emergencyNameController.dispose();
    _emergencyPhoneController.dispose();
    _allergyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthService>().dang_qian_yong_hu;
    final roleLabel = user?.role == 'child' ? '家属端' : '老人端';
    final fallbackIcon = user?.role == 'child'
        ? Icons.volunteer_activism_rounded
        : Icons.elderly_rounded;
    final avatarImage = ApiConfig.resolveMediaUrl(_avatarUrl);
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('我的资料')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
            children: [
              const SizedBox(height: 8),
              Center(
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    AppAvatar(
                      imageUrl: avatarImage.isEmpty ? null : avatarImage,
                      size: 118,
                      icon: fallbackIcon,
                      tint: user?.role == 'child'
                          ? const Color(0xFFE8F8F4)
                          : const Color(0xFFE3F8FF),
                    ),
                    Positioned(
                      right: -2,
                      bottom: 2,
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: _uploadingAvatar ? null : _showAvatarOptions,
                          borderRadius: BorderRadius.circular(18),
                          child: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              gradient: AppGradients.primaryButton,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2.5),
                              boxShadow: AppShadows.soft,
                            ),
                            child: _uploadingAvatar
                                ? const Padding(
                                    padding: EdgeInsets.all(10),
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(
                                    Icons.camera_alt_rounded,
                                    size: 20,
                                    color: Colors.white,
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 7),
              Center(
                child: TextButton.icon(
                  onPressed: _uploadingAvatar ? null : _showAvatarOptions,
                  icon: const Icon(Icons.photo_camera_rounded, size: 19),
                  label: const Text('更换头像'),
                ),
              ),
              const SizedBox(height: 7),
              AppGlassCard(
                radius: 26,
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextFormField(
                      controller: _nicknameController,
                      maxLength: 20,
                      style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
                      decoration: const InputDecoration(
                        labelText: '昵称',
                        prefixIcon: Icon(Icons.person_outline_rounded),
                        hintText: '请输入昵称',
                      ),
                      validator: (value) => value == null || value.trim().isEmpty ? '请输入昵称' : null,
                    ),
                    const SizedBox(height: 8),
                    _ReadOnlyInfo(
                      icon: Icons.phone_android_rounded,
                      label: '手机号',
                      value: user?.phone ?? '',
                    ),
                    const SizedBox(height: 8),
                    _ReadOnlyInfo(
                      icon: user?.role == 'child'
                          ? Icons.volunteer_activism_rounded
                          : Icons.elderly_rounded,
                      label: '账号身份',
                      value: roleLabel,
                    ),
                    const SizedBox(height: 15),
                    const Text(
                      '性别',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        _genderChip('male', '男'),
                        _genderChip('female', '女'),
                        _genderChip('other', '不填写'),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _DateField(
                      value: _birthDate,
                      onTap: _selectBirthDate,
                      onClear: _birthDate == null ? null : () => setState(() => _birthDate = null),
                    ),
                    const SizedBox(height: 17),
                    const Text(
                      '紧急联系人',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _emergencyNameController,
                      style: const TextStyle(fontSize: 17),
                      decoration: const InputDecoration(
                        labelText: '联系人姓名',
                        prefixIcon: Icon(Icons.contact_emergency_outlined),
                        hintText: '例如：女儿、儿子',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _emergencyPhoneController,
                      keyboardType: TextInputType.phone,
                      style: const TextStyle(fontSize: 17),
                      decoration: const InputDecoration(
                        labelText: '联系人电话',
                        prefixIcon: Icon(Icons.phone_in_talk_outlined),
                        hintText: '请输入联系电话',
                      ),
                    ),
                    const SizedBox(height: 17),
                    TextFormField(
                      controller: _allergyController,
                      minLines: 2,
                      maxLines: 4,
                      maxLength: 200,
                      style: const TextStyle(fontSize: 17, height: 1.45),
                      decoration: const InputDecoration(
                        labelText: '用药过敏史',
                        prefixIcon: Padding(
                          padding: EdgeInsets.only(bottom: 42),
                          child: Icon(Icons.warning_amber_rounded),
                        ),
                        hintText: '例如：青霉素过敏；没有可留空',
                        alignLabelWithHint: true,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const AppNotice(
                text: '头像、昵称及个人资料仅用于账号识别和用药安全提醒。手机号与账号身份不可修改。',
                icon: Icons.shield_outlined,
              ),
              const SizedBox(height: 18),
              AppGradientButton(
                label: '保存资料',
                icon: Icons.check_circle_rounded,
                loading: _saving,
                onPressed: _saving ? null : _save,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _genderChip(String value, String label) {
    final selected = _gender == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => setState(() => _gender = selected ? null : value),
      selectedColor: AppColors.blue,
      labelStyle: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        color: selected ? Colors.white : AppColors.muted,
      ),
      side: BorderSide(color: selected ? AppColors.blue : Colors.white),
    );
  }

  Future<void> _selectBirthDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthDate ?? DateTime(now.year - 60, now.month, now.day),
      firstDate: DateTime(1900),
      lastDate: now,
      helpText: '选择出生日期',
      cancelText: '取消',
      confirmText: '确定',
    );
    if (picked != null) setState(() => _birthDate = picked);
  }

  Future<void> _showAvatarOptions() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '更换头像',
                style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900, color: AppColors.ink),
              ),
              const SizedBox(height: 10),
              ListTile(
                leading: const AppIconTile(
                  icon: Icons.photo_camera_rounded,
                  size: 44,
                  iconSize: 23,
                  background: AppColors.blueTint,
                ),
                title: const Text(
                  '拍照',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                onTap: () => Navigator.pop(context, 'camera'),
              ),
              ListTile(
                leading: const AppIconTile(
                  icon: Icons.photo_library_rounded,
                  size: 44,
                  iconSize: 23,
                  background: AppColors.mintTint,
                  color: AppColors.mintDeep,
                ),
                title: const Text(
                  '从相册选择',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                onTap: () => Navigator.pop(context, 'gallery'),
              ),
              if ((_avatarUrl ?? '').isNotEmpty)
                ListTile(
                  leading: const AppIconTile(
                    icon: Icons.person_rounded,
                    size: 44,
                    iconSize: 23,
                    background: AppColors.redTint,
                    color: AppColors.red,
                  ),
                  title: const Text(
                    '恢复默认头像',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  onTap: () => Navigator.pop(context, 'remove'),
                ),
            ],
          ),
        ),
      ),
    );
    if (action == null) return;
    if (action == 'remove') {
      await _removeAvatar();
      return;
    }
    await _pickAndUploadAvatar(action == 'camera' ? ImageSource.camera : ImageSource.gallery);
  }

  Future<void> _pickAndUploadAvatar(ImageSource source) async {
    try {
      final image = await _picker.pickImage(source: source, maxWidth: 1200, imageQuality: 82);
      if (image == null) return;
      final bytes = await image.readAsBytes();
      if (!mounted) return;
      setState(() => _uploadingAvatar = true);
      final profile = await ApiService.uploadProfileAvatar(bytes, filename: 'avatar.jpg');
      if (!mounted) return;
      await context.read<AuthService>().applyProfile(profile);
      if (!mounted) return;
      setState(() {
        _avatarUrl = context.read<AuthService>().dang_qian_yong_hu?.avatarUrl;
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('头像已更新')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('头像更新失败：$error')));
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  Future<void> _removeAvatar() async {
    setState(() => _uploadingAvatar = true);
    try {
      final profile = await ApiService.deleteProfileAvatar();
      if (!mounted) return;
      await context.read<AuthService>().applyProfile(profile);
      if (!mounted) return;
      setState(() {
        _avatarUrl = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已恢复默认头像')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('恢复默认头像失败：$error')));
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final profile = await ApiService.updateProfile({
        'nickname': _nicknameController.text.trim(),
        'gender': _gender,
        'birth_date': _birthDate == null
            ? null
            : '${_birthDate!.year.toString().padLeft(4, '0')}-${_birthDate!.month.toString().padLeft(2, '0')}-${_birthDate!.day.toString().padLeft(2, '0')}',
        'emergency_contact_name': _emergencyNameController.text.trim().isEmpty
            ? null
            : _emergencyNameController.text.trim(),
        'emergency_contact_phone': _emergencyPhoneController.text.trim().isEmpty
            ? null
            : _emergencyPhoneController.text.trim(),
        'allergy_notes': _allergyController.text.trim().isEmpty
            ? null
            : _allergyController.text.trim(),
      });
      if (!mounted) return;
      await context.read<AuthService>().applyProfile(profile);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('资料已保存')));
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('保存失败：$error')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _ReadOnlyInfo extends StatelessWidget {
  const _ReadOnlyInfo({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 13),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.68),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: Colors.white.withValues(alpha: 0.92)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 22, color: AppColors.muted2),
          const SizedBox(width: 11),
          Text(label, style: const TextStyle(fontSize: 14, color: AppColors.muted2)),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(
              fontSize: 16,
              color: AppColors.ink2,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({required this.value, required this.onTap, this.onClear});

  final DateTime? value;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final text = value == null ? '请选择' : '${value!.year}年${value!.month}月${value!.day}日';
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(17),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 13),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(17),
          border: Border.all(color: Colors.white.withValues(alpha: 0.92)),
        ),
        child: Row(
          children: [
            const Icon(Icons.cake_outlined, size: 22, color: AppColors.muted2),
            const SizedBox(width: 11),
            const Text('出生日期', style: TextStyle(fontSize: 14, color: AppColors.muted2)),
            const Spacer(),
            Text(
              text,
              style: TextStyle(
                fontSize: 16,
                color: value == null ? AppColors.muted2 : AppColors.ink2,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right_rounded, color: Color(0xFF9BAEBD), size: 21),
            if (onClear != null)
              GestureDetector(
                onTap: onClear,
                child: const Padding(
                  padding: EdgeInsets.all(5),
                  child: Icon(Icons.close_rounded, size: 17, color: AppColors.muted2),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
