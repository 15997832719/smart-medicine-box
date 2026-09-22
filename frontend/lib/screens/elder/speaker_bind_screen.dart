import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../models/speaker_binding.dart';
import '../../services/api_service.dart';


class SpeakerBindScreen extends StatefulWidget {
  const SpeakerBindScreen({super.key});

  @override
  State<SpeakerBindScreen> createState() => _SpeakerBindScreenState();
}

class _SpeakerBindScreenState extends State<SpeakerBindScreen> {
  bool _jia_zai_zhong = true;
  bool _generating = false;
  String? _code;
  int _secondsLeft = 0;
  Timer? _timer;
  List<SpeakerBindingInfo> _bindings = <SpeakerBindingInfo>[];
  String? _cuo_wu;

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
      _jia_zai_zhong = true;
      _cuo_wu = null;
    });
    try {
      final bindings = await ApiService.getSpeakerBindings();
      if (!mounted) return;
      setState(() {
        _bindings = bindings;
        _jia_zai_zhong = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _cuo_wu = '没能读到音箱列表，请检查网络后下拉重试。';
        _jia_zai_zhong = false;
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
      _snack('生成配对码失败，请稍后再试');
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

  String get _codeText {
    final code = _code ?? '';
    if (code.length != 6) return code;
    return '${code.substring(0, 3)} ${code.substring(3)}';
  }

  String get _countdownText {
    final minutes = _secondsLeft ~/ 60;
    final seconds = _secondsLeft % 60;
    return '还剩 $minutes 分 ${seconds.toString().padLeft(2, '0')} 秒';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('音箱接入')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildStepsCard(),
            const SizedBox(height: 12),
            _buildCodeCard(),
            const SizedBox(height: 12),
            _buildBindingsCard(),
            const SizedBox(height: 12),
            _buildHelpCard(),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildStepsCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: ElderTheme.primaryColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Row(
            children: [
              Icon(Icons.speaker_rounded, color: Colors.white, size: 32),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  '怎么连接小度音箱？',
                  style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          _StepLine(index: '1', text: '在手机上打开「小度」App，找到你创建的技能「智能药箱」。'),
          _StepLine(index: '2', text: '对小度说：「小度小度，打开智能药箱」。'),
          _StepLine(index: '3', text: '等它问配对码时，把下面这 6 个数字一个一个读给它听。'),
        ],
      ),
    );
  }

  Widget _buildCodeCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            const Text('配对码', style: TextStyle(fontSize: 18, color: ElderTheme.textSecondary)),
            const SizedBox(height: 8),
            Text(
              _code == null ? '— — —' : _codeText,
              style: TextStyle(
                fontSize: 46,
                fontWeight: FontWeight.bold,
                letterSpacing: 4,
                color: _code == null ? ElderTheme.textSecondary : ElderTheme.primaryColor,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _code == null ? '点下面的按钮生成一个配对码' : _countdownText,
              style: const TextStyle(fontSize: 16, color: ElderTheme.textSecondary),
            ),
            const SizedBox(height: 14),
            ElevatedButton.icon(
              onPressed: _generating ? null : _generateCode,
              icon: _generating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.refresh_rounded),
              label: Text(
                _code == null ? '生成配对码' : '重新生成',
                style: const TextStyle(fontSize: 18),
              ),
              style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(56)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBindingsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('已连接的音箱', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (_jia_zai_zhong)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 18),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_cuo_wu != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(_cuo_wu!, style: const TextStyle(fontSize: 16)),
              )
            else if (_bindings.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  '还没有连接音箱。',
                  style: TextStyle(fontSize: 16, color: ElderTheme.textSecondary),
                ),
              )
            else
              for (final binding in _bindings)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      const Icon(Icons.speaker_rounded, color: ElderTheme.primaryColor),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(binding.displayName, style: const TextStyle(fontSize: 17)),
                      ),
                      TextButton(
                        onPressed: () => _unbind(binding),
                        child: const Text('解绑', style: TextStyle(fontSize: 16)),
                      ),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }

  Widget _buildHelpCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text('说明', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            Text(
              '· 配对码 10 分钟内有效，过期就重新生成一个。\n'
              '· 一台音箱只能绑定一个账号，换人使用时先在这里解绑。\n'
              '· 绑定成功后，可以对小度说「今天要吃什么药」「确认吃过药了」。',
              style: TextStyle(fontSize: 16, color: ElderTheme.textSecondary, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}


class _StepLine extends StatelessWidget {
  const _StepLine({required this.index, required this.text});

  final String index;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(13)),
            child: Text(
              index,
              style: const TextStyle(color: ElderTheme.primaryColor, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 17, height: 1.4)),
          ),
        ],
      ),
    );
  }
}