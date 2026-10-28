import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/design_system.dart';
import '../../core/theme.dart';
import '../../models/medicine.dart';
import '../../services/api_service.dart';

class AIRecognizeScreen extends StatefulWidget {
  final int? elderId;
  final VoidCallback? onSuccess;

  const AIRecognizeScreen({super.key, this.elderId, this.onSuccess});

  @override
  State<AIRecognizeScreen> createState() => _AIRecognizeScreenState();
}

class _AIRecognizeScreenState extends State<AIRecognizeScreen> {
  final ImagePicker _picker = ImagePicker();

  bool _isRecognizing = false;
  bool _isSaving = false;
  bool _manualMode = false;
  bool _parsingInstruction = false;
  Uint8List? _previewBytes;
  Map<String, dynamic>? _result;
  String? _message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: Text(widget.elderId == null ? '拍照识药' : '帮老人识药')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 6, 18, 28),
          children: [
            _buildPreviewCard(),
            const SizedBox(height: 12),
            _buildActions(),
            if (_message != null) ...[const SizedBox(height: 12), _buildMessage()],
            if (_result != null) ...[const SizedBox(height: 12), _buildResultCard()],
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewCard() {
    return Container(
      height: 300,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xF2FFFFFF), Color(0xCCE3F6FF)],
        ),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white, width: 1.2),
        boxShadow: AppShadows.card,
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (_previewBytes != null)
            Image.memory(_previewBytes!, fit: BoxFit.cover)
          else
            Padding(
              padding: const EdgeInsets.all(18),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: const Color(0x5742A6E8), width: 1.2),
                ),
                child: Center(
                  child: Container(
                    width: 176,
                    height: 150,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.86),
                      borderRadius: BorderRadius.circular(26),
                      border: Border.all(color: Colors.white),
                      boxShadow: AppShadows.soft,
                    ),
                    child: const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.view_in_ar_rounded, size: 48, color: AppColors.blue),
                        SizedBox(height: 10),
                        Text(
                          '拍摄药盒正面',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            color: AppColors.ink2,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text('让药品名称清晰可见', style: TextStyle(fontSize: 13, color: AppColors.muted2)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          if (_previewBytes == null)
            const Positioned(
              left: 0,
              right: 0,
              bottom: 22,
              child: Text(
                '光线充足，避免反光和遮挡',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF457298),
                ),
              ),
            ),
          if (_isRecognizing)
            Container(
              color: const Color(0x990A2547),
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Colors.white),
                    SizedBox(height: 16),
                    Text('正在识别药品…', style: TextStyle(color: Colors.white, fontSize: 18)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMessage() {
    final isError = _message!.contains('失败') || _message!.contains('低');
    return AppNotice(
      text: _message!,
      icon: _manualMode
          ? Icons.edit_note_rounded
          : (isError ? Icons.error_outline_rounded : Icons.info_outline_rounded),
      background: isError ? AppColors.redTint : const Color(0xCCEBF9FF),
      foreground: isError ? const Color(0xFF95606A) : const Color(0xFF537594),
      iconColor: isError ? AppColors.red : AppColors.blue,
    );
  }

  Widget _buildResultCard() {
    final result = _result!;
    return AppGlassCard(
      radius: 26,
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AppIconTile(
                icon: _manualMode ? Icons.edit_note_rounded : Icons.check_circle_rounded,
                size: 44,
                iconSize: 23,
                background: _manualMode ? AppColors.peachTint : AppColors.mintTint,
                color: _manualMode ? AppColors.peach : AppColors.mintDeep,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _manualMode ? '请人工确认药品信息' : '识别结果',
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                    color: AppColors.ink2,
                  ),
                ),
              ),
              _sourceBadge(result),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            _text(result['name'], fallback: '未知药品'),
            style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w900, color: AppColors.ink),
          ),
          const SizedBox(height: 10),
          _infoRow('规格/分类', result['spec'] ?? result['category']),
          _infoRow('用法用量', result['dosage']),
          _infoRow('频次', result['frequency']),
          _infoRow('厂家', result['manufacturer']),
          _infoRow('有效期', result['valid_date'] ?? result['expire_date']),
          _infoRow('注意事项', result['precautions']),
          const SizedBox(height: 4),
          AppSecondaryButton(
            label: '粘贴说明书文字并解析',
            icon: Icons.description_outlined,
            height: 52,
            fontSize: 16,
            onPressed: _parsingInstruction ? null : _parseInstruction,
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, dynamic value) {
    final text = _text(value);
    if (text.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFF4FAFF),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 78,
              child: Text(label, style: const TextStyle(fontSize: 14, color: AppColors.muted2)),
            ),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(
                  fontSize: 15,
                  color: AppColors.ink2,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sourceBadge(Map<String, dynamic> result) {
    final source = _text(result['source']);
    final confidence = double.tryParse(_text(result['confidence']));
    final isRealAi = source.contains('zhipu') || source.contains('glm');
    final label = isRealAi ? '真实 AI 识别' : '本地保底结果，需人工复核';
    final color = isRealAi ? ElderTheme.successColor : ElderTheme.warningColor;
    final confidenceText = confidence == null ? '' : ' ${(confidence * 100).round()}%';

    return AppPill(
      label: '$label$confidenceText',
      icon: isRealAi ? Icons.verified_rounded : Icons.report_problem_outlined,
      background: color.withValues(alpha: 0.12),
      foreground: color,
      borderColor: color.withValues(alpha: 0.28),
      fontSize: 11,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    );
  }

  Widget _buildActions() {
    if (_result == null) {
      return Column(
        children: [
          Row(
            children: [
              Expanded(
                child: AppGradientButton(
                  label: '拍照识别',
                  icon: Icons.camera_alt_rounded,
                  height: 56,
                  fontSize: 18,
                  onPressed: _isRecognizing ? null : () => _pickAndRecognize(ImageSource.camera),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: AppSecondaryButton(
                  label: '从相册选择',
                  icon: Icons.photo_library_rounded,
                  height: 56,
                  fontSize: 16,
                  onPressed: _isRecognizing ? null : () => _pickAndRecognize(ImageSource.gallery),
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          TextButton.icon(
            onPressed: _isRecognizing ? null : _createManualResult,
            icon: const Icon(Icons.edit_note_rounded),
            label: const Text('识别失败时手动录入'),
          ),
        ],
      );
    }

    return Row(
      children: [
        Expanded(
          child: AppSecondaryButton(
            label: '重新识别',
            icon: Icons.refresh_rounded,
            height: 54,
            fontSize: 16,
            onPressed: _isSaving ? null : _reset,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: AppGradientButton(
            label: '确认保存',
            icon: Icons.save_rounded,
            height: 54,
            fontSize: 18,
            loading: _isSaving,
            onPressed: _isSaving ? null : _handleConfirm,
          ),
        ),
      ],
    );
  }

  Future<void> _pickAndRecognize(ImageSource source) async {
    setState(() {
      _isRecognizing = true;
      _message = null;
      _manualMode = false;
    });

    try {
      final image = await _picker.pickImage(source: source, imageQuality: 82);
      if (image == null) {
        if (mounted) setState(() => _isRecognizing = false);
        return;
      }
      final bytes = await image.readAsBytes();
      final result = await ApiService.aiRecognizeMedicineBytes(
        bytes,
        filename: image.name.isNotEmpty ? image.name : 'medicine.jpg',
      );
      final resultSource = _text(result['source']);
      final fallbackResult =
          resultSource.contains('fallback') ||
          resultSource.contains('demo') ||
          _text(result['name']) == '无法确认药品';
      if (!mounted) return;
      setState(() {
        _previewBytes = bytes;
        _result = result;
        _manualMode = fallbackResult;
        _isRecognizing = false;
        _message = fallbackResult ? '当前不是可靠的真实 AI 结果，请人工核对后再保存。' : '智谱视觉已返回识别结果，请核对后保存。';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isRecognizing = false;
        _manualMode = true;
        _result = {'name': '未知药品', 'raw_response': e.toString()};
        _message = '自动识别失败，请手动补全药品信息后保存。';
      });
    }
  }

  void _createManualResult() {
    setState(() {
      _manualMode = true;
      _result = {'name': '未知药品'};
      _message = '请手动填写药品名称、用法和有效期。';
    });
  }

  Future<void> _handleConfirm() async {
    if (_result == null) return;
    final confidence = double.tryParse(_text(_result!['confidence']));
    if (!_manualMode && (confidence == null || confidence < 0.65)) {
      setState(() => _message = '识别置信度较低，不能直接保存。请改用手动录入并核对药品包装或说明书。');
      return;
    }
    final edited = await _showEditResultDialog(_result!);
    if (edited == null) return;

    setState(() {
      _result = edited;
      _isSaving = true;
      _message = null;
    });

    try {
      final med = Medicine(
        id: 0,
        yong_hu_bian_hao: 0,
        name: _text(edited['name'], fallback: '未知药品'),
        spec: _textOrNull(edited['spec']),
        category: _textOrNull(edited['category']),
        manufacturer: _textOrNull(edited['manufacturer']),
        description: _textOrNull(edited['description']),
        dosage: _textOrNull(edited['dosage']),
        frequency: _textOrNull(edited['frequency']),
        precautions: _textOrNull(edited['precautions']),
        you_xiao_ri_qi: _parseDate(edited['valid_date'] ?? edited['expire_date']),
        aiResult: _textOrNull(edited['raw_response']),
        stockCount: 1,
        createdAt: DateTime.now(),
      );
      await ApiService.addMedicine(med, elderId: widget.elderId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('药品已保存'), backgroundColor: ElderTheme.successColor),
      );
      widget.onSuccess?.call();
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _message = '保存失败：$e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _parseInstruction() async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('解析药品说明书'),
        content: TextField(
          controller: controller,
          maxLines: 8,
          autofocus: true,
          decoration: const InputDecoration(hintText: '粘贴说明书中的用法、禁忌和注意事项'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('开始解析'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (text == null || text.isEmpty || !mounted) return;
    setState(() => _parsingInstruction = true);
    try {
      final parsed = await ApiService.parseInstruction(text);
      if (!mounted) return;
      setState(() {
        _result = {
          ...?_result,
          ...parsed,
          if (parsed['summary'] != null && parsed['summary'].toString().isNotEmpty)
            'description': parsed['summary'],
          'raw_instruction': text,
        };
        _manualMode = true;
        _message = '说明书解析完成，请人工核对后再保存。';
      });
    } catch (e) {
      if (mounted) setState(() => _message = '说明书解析失败：$e');
    } finally {
      if (mounted) setState(() => _parsingInstruction = false);
    }
  }

  void _reset() {
    setState(() {
      _previewBytes = null;
      _result = null;
      _message = null;
      _manualMode = false;
    });
  }

  DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }

  Widget _helpField({required Widget field, required String help}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        field,
        Padding(
          padding: const EdgeInsets.only(left: 4, top: 4),
          child: Text(
            help,
            style: const TextStyle(fontSize: 13, color: ElderTheme.textSecondary, height: 1.35),
          ),
        ),
      ],
    );
  }

  Future<Map<String, dynamic>?> _showEditResultDialog(Map<String, dynamic> result) {
    final nameController = TextEditingController(text: _text(result['name']));
    final specController = TextEditingController(text: _text(result['spec'] ?? result['category']));
    final dosageController = TextEditingController(text: _text(result['dosage']));
    final frequencyController = TextEditingController(text: _text(result['frequency']));
    final validDateController = TextEditingController(
      text: _text(result['valid_date'] ?? result['expire_date']),
    );
    final precautionsController = TextEditingController(text: _text(result['precautions']));

    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认药品信息'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '下面是 AI 从照片里认出来的信息，请对着药盒核对，不对的地方直接改。',
                style: TextStyle(fontSize: 14, color: ElderTheme.textSecondary, height: 1.4),
              ),
              const SizedBox(height: 12),
              _helpField(
                field: TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: '药品名称'),
                ),
                help: '照着药盒上的名字填，例如「阿司匹林肠溶片」',
              ),
              const SizedBox(height: 10),
              _helpField(
                field: TextField(
                  controller: specController,
                  decoration: const InputDecoration(labelText: '规格/分类'),
                ),
                help: '看包装上「规格」那一行，例如 100mg×30片；看不出来可以不填',
              ),
              const SizedBox(height: 10),
              _helpField(
                field: TextField(
                  controller: dosageController,
                  decoration: const InputDecoration(labelText: '用法用量'),
                ),
                help: '一次吃多少，例如「每次 1 片」',
              ),
              const SizedBox(height: 10),
              _helpField(
                field: TextField(
                  controller: frequencyController,
                  decoration: const InputDecoration(labelText: '服用频次'),
                ),
                help: '一天吃几次，例如「每天 1 次，早餐后」',
              ),
              const SizedBox(height: 10),
              _helpField(
                field: TextField(
                  controller: validDateController,
                  decoration: const InputDecoration(labelText: '有效期'),
                ),
                help: '看药盒上的「有效期至」或「失效日期」，按 2026-12-31 这种格式填；看不清就先空着',
              ),
              const SizedBox(height: 10),
              _helpField(
                field: TextField(
                  controller: precautionsController,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: '注意事项'),
                ),
                help: '照抄说明书里「禁用」「注意」的内容，例如「胃溃疡患者慎用」；没有可以不填',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () {
              final edited = Map<String, dynamic>.from(result);
              edited['name'] = nameController.text.trim().isEmpty
                  ? '未知药品'
                  : nameController.text.trim();
              edited['spec'] = _emptyToNull(specController.text);
              edited['dosage'] = _emptyToNull(dosageController.text);
              edited['frequency'] = _emptyToNull(frequencyController.text);
              edited['valid_date'] = _emptyToNull(validDateController.text);
              edited['precautions'] = _emptyToNull(precautionsController.text);
              Navigator.pop(ctx, edited);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  String _text(dynamic value, {String fallback = ''}) {
    if (value == null) return fallback;
    final text = value.toString();
    return text.isEmpty ? fallback : text;
  }

  String? _textOrNull(dynamic value) {
    final text = _text(value);
    return text.isEmpty ? null : text;
  }

  String? _emptyToNull(String value) {
    final text = value.trim();
    return text.isEmpty ? null : text;
  }
}
