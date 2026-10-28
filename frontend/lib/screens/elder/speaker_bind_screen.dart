import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/design_system.dart';
import '../../models/speaker_binding.dart';
import '../../services/api_service.dart';

class SpeakerBindScreen extends StatefulWidget {
  const SpeakerBindScreen({super.key});

  @override
  State<SpeakerBindScreen> createState() => _SpeakerBindScreenState();
}

class _SpeakerBindScreenState extends State<SpeakerBindScreen> {
  bool _loading = true;
  bool _generating = false;
  String? _code;
  int _secondsLeft = 0;
  Timer? _timer;
  List<SpeakerBindingInfo> _bindings = <SpeakerBindingInfo>[];
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final bindings = await ApiService.getSpeakerBindings();
      if (!mounted) return;
      setState(() {
        _bindings = bindings;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = '没能读到音箱列表，请检查网络后重试。';
        _loading = false;
      });
    }
  }

  Future<void> _generateCode() async {
    setState(() => _generating = true);
    try {
      final data = await ApiService.createSpeakerPairingCode();
      final code = (data['code'] ?? '').toString();
      final expires = int.tryParse((data['expires_in'] ?? 600).toString()) ?? 600;
      if (!mounted) return;
      _timer?.cancel();
      setState(() {
        _code = code;
        _secondsLeft = expires;
        _generating = false;
      });
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        setState(() => _secondsLeft -= 1);
        if (_secondsLeft <= 0) {
          timer.cancel();
          setState(() => _code = null);
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _generating = false);
      _snack('生成绑定码失败，请稍后再试');
    }
  }

  Future<void> _unbind(SpeakerBindingInfo binding) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('解绑这台音箱？', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        content: Text('解绑以后，${binding.displayName} 就不能再查询这个账号的用药信息了。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消', style: TextStyle(fontSize: 18)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('解绑', style: TextStyle(fontSize: 18)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ApiService.unbindSpeaker(binding.id);
      if (!mounted) return;
      await _load();
      _snack('已经解绑');
    } catch (_) {
      _snack('解绑失败，请稍后再试');
    }
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  String get _countdownText {
    final minutes = _secondsLeft ~/ 60;
    final seconds = _secondsLeft % 60;
    return '还剩 $minutes 分 ${seconds.toString().padLeft(2, '0')} 秒';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.blueTint,
      appBar: AppBar(
        title: const Text('音箱接入'),
        backgroundColor: AppColors.blue,
        foregroundColor: AppColors.white,
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildHero(),
            const SizedBox(height: 14),
            _buildCodeCard(),
            const SizedBox(height: 14),
            _buildSteps(),
            const SizedBox(height: 14),
            _buildBindings(),
            const SizedBox(height: 14),
            _buildNote(),
          ],
        ),
      ),
    );
  }

  Widget _card({required Widget child, Color color = AppColors.white, EdgeInsets padding = const EdgeInsets.all(18)}) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(color: AppColors.ink.withOpacity(0.06), blurRadius: 14, offset: const Offset(0, 6)),
        ],
      ),
      child: child,
    );
  }

  Widget _buildHero() {
    return _card(
      color: AppColors.blue,
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(color: AppColors.white.withOpacity(0.18), borderRadius: BorderRadius.circular(16)),
            child: const Icon(Icons.speaker_rounded, color: AppColors.white, size: 34),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('连接智能音箱', style: TextStyle(color: AppColors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                SizedBox(height: 4),
                Text('绑定后，老人可以直接问“今天吃什么药”', style: TextStyle(color: AppColors.white, fontSize: 14)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCodeCard() {
    final hasCode = _code != null && _secondsLeft > 0;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('绑定码', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.ink)),
          const SizedBox(height: 10),
          if (hasCode)
            Column(
              children: [
                Text(
                  _code!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 44, letterSpacing: 8, fontWeight: FontWeight.bold, color: AppColors.blueDeep),
                ),
                const SizedBox(height: 4),
                Text(_countdownText, style: const TextStyle(fontSize: 14, color: AppColors.muted)),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _generating ? null : _generateCode,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('重新生成'),
                ),
              ],
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('点击生成一个 6 位数字，10 分钟内有效。', style: TextStyle(fontSize: 15, color: AppColors.muted)),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: _generating ? null : _generateCode,
                  icon: _generating
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.white))
                      : const Icon(Icons.numbers_rounded),
                  label: Text(_generating ? '正在生成…' : '生成绑定码'),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildSteps() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Text('怎么绑定', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.ink)),
          SizedBox(height: 12),
          _StepRow(index: '1', text: '在 App 里点“生成绑定码”。'),
          _StepRow(index: '2', text: '对音箱说：绑定码 加上那 6 个数字。'),
          _StepRow(index: '3', text: '听到“绑定成功”就完成了。'),
        ],
      ),
    );
  }

  Widget _buildBindings() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('已连接的音箱', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.ink)),
          const SizedBox(height: 10),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            Text(_error!, style: const TextStyle(color: AppColors.red, fontSize: 15))
          else if (_bindings.isEmpty)
            const Text('还没有连接音箱。', style: TextStyle(fontSize: 15, color: AppColors.muted))
          else
            ..._bindings.map(
              (binding) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.speaker_rounded, color: AppColors.blueDeep),
                title: Text(binding.displayName, style: const TextStyle(fontWeight: FontWeight.w600)),
                trailing: TextButton(onPressed: () => _unbind(binding), child: const Text('解绑')),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildNote() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.peachTint, borderRadius: BorderRadius.circular(14)),
      child: const Text(
        '· 一台音箱只能绑定一个账号，换人使用请先在这里解绑。\n'
        '· 没绑定的音箱不能查询用药信息，也不会读取任何账号的数据。',
        style: TextStyle(fontSize: 14, height: 1.5, color: AppColors.ink2),
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.index, required this.text});

  final String index;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: const BoxDecoration(color: AppColors.blueTint, shape: BoxShape.circle),
            child: Text(index, style: const TextStyle(color: AppColors.blueDeep, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 15, height: 1.4, color: AppColors.ink2))),
        ],
      ),
    );
  }
}
