import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../../core/theme.dart';
import '../../services/api_service.dart';

class VoiceAssistantScreen extends StatefulWidget {
  const VoiceAssistantScreen({super.key, this.ji_hua_bian_hao});

  final int? ji_hua_bian_hao;

  @override
  State<VoiceAssistantScreen> createState() => _VoiceAssistantScreenState();
}

class _VoiceAssistantScreenState extends State<VoiceAssistantScreen> {
  final stt.SpeechToText _speech = stt.SpeechToText();
  final FlutterTts _tts = FlutterTts();
  final AudioRecorder _recorder = AudioRecorder();
  final TextEditingController _textController = TextEditingController();

  bool _initializing = true;
  bool _available = false;
  bool _listening = false;
  bool _jia_zai_zhong = false;
  bool _finishing = false;
  bool _settingsRequired = false;
  bool _cloudRecording = false;
  String? _recordingPath;
  String _voiceLocale = 'zh_CN';
  String _question = '按住麦克风说话';
  String _reply = '我会根据你的用药计划回答问题';
  String? _systemMessage;

  @override
  void initState() {
    super.initState();
    _initVoice();
  }

  @override
  void dispose() {
    _textController.dispose();
    _speech.stop();
    _tts.stop();
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _initVoice() async {
    if (mounted) {
      setState(() {
        _initializing = true;
        _available = false;
        _settingsRequired = false;
        _systemMessage = null;
      });
    }

    try {
      final permission = await _requestMicrophonePermission();
      if (permission != null && !permission.isGranted) {
        _setVoiceUnavailable(
          permission.isPermanentlyDenied
              ? '麦克风权限已被永久拒绝。请打开系统设置，允许“智能药箱”使用麦克风。'
              : '需要麦克风权限才能使用语音识别。请点击“重新授权”。',
          settingsRequired: permission.isPermanentlyDenied,
        );
        return;
      }

      final available = await _speech.initialize(
        onStatus: _onSpeechStatus,
        onError: (error) => _onSpeechError(error.toString()),
      );
      if (!available) {
        final permissionStatus = await Permission.microphone.status;
        final permissionBlocked = !kIsWeb &&
            (Platform.isAndroid || Platform.isIOS) &&
            !permissionStatus.isGranted;
        _setVoiceUnavailable(
          permissionBlocked
              ? '系统没有授予麦克风权限。请重新授权，或在系统设置中开启权限。'
              : '系统语音识别不可用，点击或按住麦克风将使用服务器录音识别。',
          settingsRequired: permissionBlocked && permissionStatus.isPermanentlyDenied,
        );
        return;
      }

      _voiceLocale = await _findChineseLocale();
      await _configureTts();
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _available = true;
        _systemMessage = null;
      });
    } catch (_) {
      _setVoiceUnavailable('语音服务初始化失败。请重新检测，或使用下方文字输入。');
    }
  }

  Future<PermissionStatus?> _requestMicrophonePermission() async {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) return null;
    var status = await Permission.microphone.status;
    if (!status.isGranted) {
      status = await Permission.microphone.request();
    }
    return status;
  }

  Future<String> _findChineseLocale() async {
    try {
      final locales = await _speech.locales();
      for (final locale in locales) {
        final id = locale.localeId.replaceAll('-', '_').toLowerCase();
        if (id.startsWith('zh')) return locale.localeId;
      }
    } catch (_) {
      
    }
    return 'zh_CN';
  }

  Future<void> _configureTts() async {
    try {
      await _tts.setLanguage('zh-CN');
      await _tts.setSpeechRate(0.48);
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);
    } catch (_) {
      
    }
  }

  void _onSpeechStatus(String status) {
    if (!mounted) return;
    if (status == 'notListening' || status == 'done') {
      setState(() => _listening = false);
    }
  }

  void _onSpeechError(String rawError) {
    if (!mounted) return;
    final message = rawError.contains('permission')
        ? '麦克风权限不可用，请检查系统设置。'
        : rawError.contains('timeout') || rawError.contains('no_match')
            ? '没有听清，请靠近麦克风再说一次。'
            : '语音识别出错，请重试或使用文字输入。';
    setState(() {
      _available = false;
      _listening = false;
      _systemMessage = message;
    });
  }

  void _setVoiceUnavailable(String message, {bool settingsRequired = false}) {
    if (!mounted) return;
    setState(() {
      _initializing = false;
      _available = false;
      _listening = false;
      _settingsRequired = settingsRequired;
      _systemMessage = message;
    });
  }

  Future<void> _startCloudRecording() async {
    if (_cloudRecording || _jia_zai_zhong) return;
    try {
      final granted = await _recorder.hasPermission();
      if (!granted) {
        _setVoiceUnavailable('麦克风权限不可用。请在系统设置中允许本应用录音。', settingsRequired: true);
        return;
      }
      final directory = await getTemporaryDirectory();
      final path = '${directory.path}${Platform.pathSeparator}voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
        ),
        path: path,
      );
      if (!mounted) return;
      setState(() {
        _cloudRecording = true;
        _recordingPath = path;
        _question = '正在录音…';
        _reply = '说完后点击麦克风结束';
        _systemMessage = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _cloudRecording = false;
        _systemMessage = '无法开始录音：$error';
      });
    }
  }

  Future<void> _stopCloudRecording() async {
    if (!_cloudRecording) return;
    setState(() {
      _cloudRecording = false;
      _jia_zai_zhong = true;
      _reply = '正在上传并识别录音…';
      _systemMessage = null;
    });
    String? path = _recordingPath;
    try {
      path = await _recorder.stop() ?? path;
      if (path == null || path.isEmpty) {
        throw Exception('没有生成录音文件');
      }
      final text = await ApiService.transcribeVoice(File(path));
      if (!mounted) return;
      setState(() => _question = text);
      await _send(text);
    } catch (error) {
      if (!mounted) return;
      setState(() => _systemMessage = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (path != null) {
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
        }
      }
      if (mounted) setState(() => _jia_zai_zhong = false);
    }
  }

  Future<void> _handleMicTap() async {
    if (_cloudRecording) {
      await _stopCloudRecording();
    } else if (_available) {
      if (_listening) {
        await _finishListening();
      } else {
        await _startListening();
      }
    } else {
      await _startCloudRecording();
    }
  }

  Future<void> _handleMicLongPressStart() async {
    if (_cloudRecording) return;
    if (_available) {
      await _startListening();
    } else {
      await _startCloudRecording();
    }
  }

  Future<void> _handleMicLongPressEnd() async {
    if (_cloudRecording) {
      await _stopCloudRecording();
    } else if (_available) {
      await _finishListening();
    }
  }
  Future<void> _startListening() async {
    if (_jia_zai_zhong || _listening || _initializing) return;
    if (!_available) {
      await _initVoice();
      if (!_available) return;
    }

    setState(() {
      _listening = true;
      _question = '正在聆听…';
      _reply = '请继续说话';
      _systemMessage = null;
    });

    try {
      await _speech.listen(
        listenOptions: stt.SpeechListenOptions(
          localeId: _voiceLocale,
          partialResults: true,
          listenMode: stt.ListenMode.dictation,
          listenFor: const Duration(seconds: 20),
          pauseFor: const Duration(seconds: 4),
        ),
        onResult: (result) {
          final text = result.recognizedWords.trim();
          if (!mounted || text.isEmpty) return;
          setState(() => _question = text);
          if (result.finalResult) {
            _finishListening(text);
          }
        },
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _available = false;
        _listening = false;
        _systemMessage = '系统语音识别不可用，将改用服务器录音识别。';
      });
    }
  }

  Future<void> _finishListening([String? value]) async {
    if (_finishing) return;
    _finishing = true;
    try {
      try {
        await _speech.stop();
      } catch (_) {
        
      }
      if (mounted) setState(() => _listening = false);
      final text = (value ?? _question).trim();
      if (text.isEmpty || text == '正在聆听…' || text == '按住麦克风说话') return;
      await _send(text);
    } finally {
      _finishing = false;
    }
  }

  Future<void> _submitTypedQuestion() async {
    final text = _textController.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先输入问题')),
      );
      return;
    }
    _textController.clear();
    await _send(text);
  }

  Future<void> _send(String text) async {
    setState(() {
      _jia_zai_zhong = true;
      _question = text;
      _reply = '正在查询你的用药计划…';
      _systemMessage = null;
    });

    try {
      final response = await ApiService.sendVoiceIntent(
        text,
        ji_hua_bian_hao: widget.ji_hua_bian_hao,
      );
      final reply = (response['reply'] ?? response['message'] ?? '暂时没有找到相关用药信息').toString();
      if (!mounted) return;
      setState(() => _reply = reply);
      await _speak(reply);
    } catch (_) {
      if (!mounted) return;
      setState(() => _systemMessage = '连接服务失败，请检查网络后重试。');
    } finally {
      if (mounted) setState(() => _jia_zai_zhong = false);
    }
  }

  Future<void> _speak(String text) async {
    try {
      await _tts.stop();
      await _tts.speak(text);
    } catch (_) {
      if (!mounted) return;
      setState(() => _systemMessage = '文字回复已显示，但当前设备的语音播报不可用。');
    }
  }

  Future<void> _handleVoiceAction() async {
    if (_settingsRequired) {
      final opened = await openAppSettings();
      if (!opened && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('无法打开系统设置，请手动找到本应用的权限设置。')),
        );
      }
      return;
    }
    await _initVoice();
  }

  @override
  Widget build(BuildContext context) {
    final canSystemListen = _available && !_jia_zai_zhong && !_initializing;
    final canCloudRecord = !_available && !_jia_zai_zhong && !_initializing;
    final canMic = canSystemListen || canCloudRecord;
    return Scaffold(
      backgroundColor: ElderTheme.bgColor,
      appBar: AppBar(
        title: const Text('语音助手'),
        backgroundColor: ElderTheme.elderAccent,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _bubble('我的问题', _question, Icons.person_rounded, ElderTheme.primaryColor),
            const SizedBox(height: 12),
            _bubble(
              '智能药箱',
              _reply,
              Icons.volume_up_rounded,
              ElderTheme.successColor,
              onPlay: _reply.isEmpty || _jia_zai_zhong ? null : () => _speak(_reply),
            ),
            if (_systemMessage != null) ...[
              const SizedBox(height: 12),
              _noticeCard(_systemMessage!),
            ],
            const SizedBox(height: 24),
            Text(
              _initializing
                  ? '正在检查语音权限…'
                  : _cloudRecording
                      ? '正在录音，点击结束'
                      : _listening
                          ? '点击结束并发送'
                          : _available
                              ? '点击或按住麦克风说话'
                              : '点击或按住进行服务器录音识别',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Center(
              child: GestureDetector(
                onTap: canMic ? _handleMicTap : null,
                onLongPressStart: canMic ? (_) => _handleMicLongPressStart() : null,
                onLongPressEnd: canMic ? (_) => _handleMicLongPressEnd() : null,
                child: Opacity(
                  opacity: canMic ? 1 : 0.45,
                  child: CircleAvatar(
                    radius: 44,
                    backgroundColor: (_listening || _cloudRecording) ? Colors.red : ElderTheme.elderAccent,
                    child: Icon(
                      (_listening || _cloudRecording) ? Icons.mic : Icons.mic_none,
                      size: 44,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
            if (!_available && !_initializing) ...[
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _handleVoiceAction,
                icon: Icon(_settingsRequired ? Icons.settings : Icons.refresh),
                label: Text(_settingsRequired ? '打开系统设置' : '重新检测语音权限'),
              ),
            ],
            const SizedBox(height: 22),
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '也可以输入文字提问',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _textController,
                      enabled: !_jia_zai_zhong,
                      minLines: 1,
                      maxLines: 3,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _submitTypedQuestion(),
                      decoration: const InputDecoration(
                        hintText: '例如：今天该吃什么药？',
                        prefixIcon: Icon(Icons.keyboard_rounded),
                      ),
                    ),
                    const SizedBox(height: 10),
                    ElevatedButton.icon(
                      onPressed: _jia_zai_zhong ? null : _submitTypedQuestion,
                      icon: _jia_zai_zhong
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.send_rounded),
                      label: const Text('发送问题'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              '可以说：“我今天该吃什么药？”、“我的药还剩多少？”或“确认服用阿司匹林”。',
              textAlign: TextAlign.center,
              style: TextStyle(color: ElderTheme.textSecondary, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }

  Widget _noticeCard(String text) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ElderTheme.warningColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ElderTheme.warningColor.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded, color: ElderTheme.warningColor),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 16, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bubble(String title, String text, IconData icon, Color color, {VoidCallback? onPlay}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
                const SizedBox(height: 5),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: SelectableText(
                        text,
                        style: const TextStyle(fontSize: 18, height: 1.35),
                      ),
                    ),
                    if (onPlay != null)
                      Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: IconButton(
                          tooltip: '播放语音',
                          onPressed: onPlay,
                          icon: const Icon(Icons.volume_up_rounded),
                          color: color,
                          style: IconButton.styleFrom(
                            backgroundColor: color.withValues(alpha: 0.14),
                            minimumSize: const Size(40, 40),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}