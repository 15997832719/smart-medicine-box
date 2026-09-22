import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

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
      backgroundColor: ElderTheme.bgColor,
      appBar: AppBar(
        title: Text(widget.elderId == null ? '拍照识药' : '帮老人识药'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildPreviewCard(),
            const SizedBox(height: 16),
            if (_message != null) _buildMessage(),
            if (_result != null) ...[
              const SizedBox(height: 16),
              _buildResultCard(),
            ],
            const SizedBox(height: 18),
            _buildActions(),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewCard() {
    return Container(
      height: 260,
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: ElderTheme.primaryColor, width: 2),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (_previewBytes != null)
            Image.memory(_previewBytes!, fit: BoxFit.cover)
          else
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.camera_alt_rounded, size: 72, color: Colors.white.withOpacity(0.8)),
                const SizedBox(height: 14),
                const Text('拍摄药盒正面', style: TextStyle(fontSize: 22, color: Colors.white, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text('尽量让药品名称和规格清晰可见', style: TextStyle(fontSize: 15, color: Colors.white.withOpacity(0.72))),
              ],
            ),
          if (_isRecognizing)
            Container(
              color: Colors.black.withOpacity(0.55),
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Colors.white),
                    SizedBox(height: 16),
                    Text('正在识别药品...', style: TextStyle(color: Colors.white, fontSize: 18)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMessage() {
    final color = _result != null && !_manualMode ? ElderTheme.infoColor : (_manualMode ? ElderTheme.warningColor : ElderTheme.errorColor);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Row(
        children: [
          Icon(_manualMode ? Icons.edit_note_rounded : Icons.info_outline_rounded, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _message!,
              style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultCard() {
    final result = _result!;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: ElderTheme.cardColor,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 14, offset: const Offset(0, 6))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_manualMode ? Icons.edit_note_rounded : Icons.check_circle_rounded,
                  color: _manualMode ? ElderTheme.warningColor : ElderTheme.successColor, size: 30),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _manualMode ? '请人工确认药品信息' : '识别结果',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: ElderTheme.textPrimary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            _text(result['name'], fallback: '未知药品'),
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: ElderTheme.textPrimary),
          ),
          const SizedBox(height: 8),
          _sourceBadge(result),
          const SizedBox(height: 12),
          _infoRow('规格/分类', result['spec'] ?? result['category']),
          _infoRow('用法用量', result['dosage']),
          _infoRow('频次', result['frequency']),
          _infoRow('厂家', result['manufacturer']),
          _infoRow('有效期', result['valid_date'] ?? result['expire_date']),
            _infoRow('注意事项', result['precautions']),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _parsingInstruction ? null : _parseInstruction,
              icon: _parsingInstruction
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.description_outlined),
              label: const Text('粘贴说明书文字并解析'),
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
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 82, child: Text(label, style: const TextStyle(fontSize: 15, color: ElderTheme.textSecondary))),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 16, color: ElderTheme.textPrimary, height: 1.35))),
        ],
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

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(isRealAi ? Icons.verified_rounded : Icons.report_problem_outlined, color: color, size: 18),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              '$label$confidenceText',
              style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActions() {
    if (_result == null) {
      return Column(
        children: [
          ElevatedButton.icon(
            onPressed: _isRecognizing ? null : () => _pickAndRecognize(ImageSource.camera),
            icon: const Icon(Icons.camera_alt_rounded),
            label: const Text('拍照识别'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _isRecognizing ? null : () => _pickAndRecognize(ImageSource.gallery),
            icon: const Icon(Icons.photo_library_rounded),
            label: const Text('从相册选择'),
          ),
          const SizedBox(height: 12),
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
          child: OutlinedButton.icon(
            onPressed: _isSaving ? null : _reset,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('重新识别'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _isSaving ? null : _handleConfirm,
            icon: _isSaving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save_rounded),
            label: const Text('确认保存'),
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
      final result = await ApiService.aiRecognizeMedicineBytes(bytes, filename: image.name.isNotEmpty ? image.name : 'medicine.jpg');
      final resultSource = _text(result['source']);
      final fallbackResult =
          resultSource.contains('fallback') || resultSource.contains('demo') || _text(result['name']) == '无法确认药品';
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
          ElevatedButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('开始解析')),
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
    final validDateController = TextEditingController(text: _text(result['valid_date'] ?? result['expire_date']));
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
                field: TextField(controller: nameController, decoration: const InputDecoration(labelText: '药品名称')),
                help: '照着药盒上的名字填，例如「阿司匹林肠溶片」',
              ),
              const SizedBox(height: 10),
              _helpField(
                field: TextField(controller: specController, decoration: const InputDecoration(labelText: '规格/分类')),
                help: '看包装上「规格」那一行，例如 100mg×30片；看不出来可以不填',
              ),
              const SizedBox(height: 10),
              _helpField(
                field: TextField(controller: dosageController, decoration: const InputDecoration(labelText: '用法用量')),
                help: '一次吃多少，例如「每次 1 片」',
              ),
              const SizedBox(height: 10),
              _helpField(
                field: TextField(controller: frequencyController, decoration: const InputDecoration(labelText: '服用频次')),
                help: '一天吃几次，例如「每天 1 次，早餐后」',
              ),
              const SizedBox(height: 10),
              _helpField(
                field: TextField(controller: validDateController, decoration: const InputDecoration(labelText: '有效期')),
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
              edited['name'] = nameController.text.trim().isEmpty ? '未知药品' : nameController.text.trim();
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
