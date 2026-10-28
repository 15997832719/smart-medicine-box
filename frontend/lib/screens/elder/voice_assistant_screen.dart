import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/design_system.dart';
import '../../services/api_service.dart';
import '../../services/tts_service.dart';
import '../../services/voice_capture_service.dart';

class VoiceAssistantScreen extends StatefulWidget {
  const VoiceAssistantScreen(
      {super.key, this.ji_hua_bian_hao, this.ownerId, this.ownerLabel});

  final int? ji_hua_bian_hao;
  final int? ownerId;
  final String? ownerLabel;

  @override
  State<VoiceAssistantScreen> createState() => _VoiceAssistantScreenState();
}

class _VoiceAssistantScreenState extends State<VoiceAssistantScreen> {
  final FlutterTts _tts = FlutterTts();
  final VoiceCaptureService _capture = VoiceCaptureService();
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  bool _initializing = true;
  bool _available = false;
  bool _jia_zai_zhong = false;
  bool _settingsRequired = false;
  bool _cloudRecording = false;
  bool _isSpeaking = false;
  String _question = '';
  String _reply = '你好，我是智能药箱语音助手。你可以直接问我今天的用药计划，也可以按住底部麦克风说话。';
  String _lastSpeakText = '';
  String? _systemMessage;
  late final String _hui_hua_bian_hao;
  late final String _traceId;
  bool _xu_yao_que_ren = false;

  @override
  void initState() {
    super.initState();
    _hui_hua_bian_hao = DateTime.now().microsecondsSinceEpoch.toString();
    _traceId =
        'voice-${DateTime.now().millisecondsSinceEpoch.toRadixString(16)}';
    _initVoice();
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    _tts.stop();
    _capture.dispose();
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
      final granted = await _capture
          .requestPermission()
          .timeout(const Duration(seconds: 12));
      if (!granted) {
        _setVoiceUnavailable('需要麦克风权限才能使用语音助手。请点击“重新授权”。');
        return;
      }
      await _configureTts();
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _available = true;
        _systemMessage = null;
      });
    } catch (_) {
      _setVoiceUnavailable('录音服务初始化失败。请重新检测，或使用下方文字输入。');
    }
  }

  Future<void> _configureTts() async {
    try {
      await _tts.setLanguage('zh-CN').timeout(const Duration(seconds: 3));
      await _tts.setSpeechRate(0.48).timeout(const Duration(seconds: 3));
      await _tts.setVolume(1.0).timeout(const Duration(seconds: 3));
      await _tts.setPitch(1.0).timeout(const Duration(seconds: 3));
      await _tts.awaitSpeakCompletion(true).timeout(const Duration(seconds: 3));
    } catch (_) {
      // The visual reply remains available when device TTS is unavailable.
    }
  }

  void _setVoiceUnavailable(String message, {bool settingsRequired = false}) {
    if (!mounted) return;
    setState(() {
      _initializing = false;
      _available = false;
      _settingsRequired = settingsRequired;
      _systemMessage = message;
    });
  }

  Future<void> _startCloudRecording() async {
    if (_cloudRecording || _jia_zai_zhong || _initializing) return;
    try {
      await _capture.start();
      if (!mounted) return;
      setState(() {
        _cloudRecording = true;
        _question = '正在录音…';
        _reply = '说完后点击麦克风结束';
        _systemMessage = null;
      });
    } on VoiceCaptureException catch (error) {
      _setVoiceUnavailable(error.message,
          settingsRequired: error.stage == 'permission');
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
    String? path;
    try {
      path = await _capture.stop();
      final text = await ApiService.transcribeVoice(
        File(path),
        ownerId: widget.ownerId,
        traceId: _traceId,
      );
      if (!mounted) return;
      setState(() => _question = text);
      await _send(text);
    } on VoiceCaptureException catch (error) {
      if (!mounted) return;
      setState(() => _systemMessage = '录音失败：${error.message}');
    } catch (error) {
      if (!mounted) return;
      setState(() =>
          _systemMessage = error.toString().replaceFirst('Exception: ', ''));
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
    } else {
      await _startCloudRecording();
    }
  }

  Future<void> _handleMicLongPressStart() async {
    if (!_cloudRecording) await _startCloudRecording();
  }

  Future<void> _handleMicLongPressEnd() async {
    if (_cloudRecording) await _stopCloudRecording();
  }

  Future<void> _submitTypedQuestion() async {
    final text = _textController.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请先输入问题')));
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
        hui_hua_bian_hao: _hui_hua_bian_hao,
        ownerId: widget.ownerId,
        traceId: _traceId,
      );
      final displayText = (response['display_text'] ??
              response['reply'] ??
              response['message'] ??
              '暂时没有找到相关用药信息')
          .toString();
      final speakText = (response['speak_text'] ?? displayText).toString();
      final needsConfirmation = response['needs_confirmation'] == true;
      if (!mounted) return;
      setState(() {
        _reply = displayText;
        _lastSpeakText = speakText;
        _xu_yao_que_ren = needsConfirmation;
      });
      unawaited(_speak(speakText));
    } catch (_) {
      if (!mounted) return;
      setState(() => _systemMessage = '连接服务失败，请检查网络后重试。');
    } finally {
      if (mounted) setState(() => _jia_zai_zhong = false);
    }
  }

  Future<void> _stopSpeaking() async {
    _isSpeaking = false;
    try {
      await TtsService.stop();
      await _tts.stop().timeout(const Duration(seconds: 3));
    } catch (_) {}
    if (mounted) setState(() {});
  }

  Future<void> _speak(String text) async {
    final normalized = text.trim();
    if (normalized.isEmpty) return;
    await _stopSpeaking();
    final segments = _splitSpeechText(normalized);
    if (!mounted) return;
    setState(() {
      _isSpeaking = true;
      _systemMessage = null;
    });
    var failed = false;
    String? failureDetail;
    final nativeTts = await TtsService.isNativeAvailable();
    for (final segment in segments) {
      if (!_isSpeaking) break;
      try {
        if (nativeTts) {
          final bytes = await ApiService.synthesizeSpeech(segment);
          final file = File(
            '${Directory.systemTemp.path}${Platform.pathSeparator}smb_tts_${DateTime.now().microsecondsSinceEpoch}.mp3',
          );
          await file.writeAsBytes(bytes, flush: true);
          try {
            await TtsService.playFile(file.path);
          } finally {
            if (await file.exists()) await file.delete();
          }
        } else {
          await _tts.speak(segment).timeout(const Duration(seconds: 12));
        }
      } catch (error) {
        failed = true;
        failureDetail ??= error.toString().replaceFirst('Exception: ', '');
      }
    }
    if (!mounted) return;
    setState(() {
      _isSpeaking = false;
      if (failed) {
        _systemMessage = failureDetail == null
            ? '??????????????????'
            : '???????$failureDetail';
      }
    });
  }

  List<String> _splitSpeechText(String text) {
    final segments = <String>[];
    final buffer = StringBuffer();
    const punctuation = '。！？!?；;\n';
    for (final rune in text.runes) {
      final character = String.fromCharCode(rune);
      buffer.write(character);
      if (punctuation.contains(character) || buffer.length >= 100) {
        final segment = buffer.toString().trim();
        if (segment.isNotEmpty) segments.add(segment);
        buffer.clear();
      }
    }
    final tail = buffer.toString().trim();
    if (tail.isNotEmpty) segments.add(tail);
    return segments.isEmpty ? <String>[text] : segments;
  }

  Future<void> _handleVoiceAction() async {
    if (_settingsRequired) {
      final opened = await openAppSettings();
      if (!opened && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(
            const SnackBar(content: Text('无法打开系统设置，请手动找到本应用的权限设置。')));
      }
      return;
    }
    await _initVoice();
  }

  @override
  Widget build(BuildContext context) {
    final canMic = _available && !_jia_zai_zhong && !_initializing;
    final hasUserQuestion =
        _question.trim().isNotEmpty && _question != '按住麦克风说话';
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        toolbarHeight: 76,
        leadingWidth: 66,
        leading: Padding(
          padding: const EdgeInsets.only(left: 14),
          child: AppCircleButton(
            icon: Icons.arrow_back_ios_new_rounded,
            onPressed: () => Navigator.pop(context),
          ),
        ),
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  '语音助手',
                  style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: AppColors.ink),
                ),
                const SizedBox(width: 2),
                Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 23,
                  color: AppColors.muted2.withValues(alpha: 0.9),
                ),
              ],
            ),
            const SizedBox(height: 2),
            const Text(
              'AI 生成可能有误，注意核实',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.muted2,
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: AppCircleButton(
              icon: _isSpeaking ? Icons.stop_rounded : Icons.volume_up_rounded,
              onPressed: _isSpeaking
                  ? _stopSpeaking
                  : (_lastSpeakText.isEmpty
                      ? null
                      : () => _speak(_lastSpeakText)),
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 2, 18, 0),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: AppGradients.glass,
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: Colors.white, width: 1.2),
                    boxShadow: AppShadows.card,
                  ),
                  child: ListView(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
                    children: [
                      const Text(
                        '今天 11:30',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14.5,
                          color: AppColors.muted2,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 14),
                      _aiBubble(
                        _reply,
                        onPlay: _lastSpeakText.isEmpty || _jia_zai_zhong
                            ? null
                            : (_isSpeaking
                                ? _stopSpeaking
                                : () => _speak(_lastSpeakText)),
                      ),
                      if (hasUserQuestion) ...[
                        const SizedBox(height: 14),
                        _userBubble(_question)
                      ],
                      if (_jia_zai_zhong) ...[
                        const SizedBox(height: 14),
                        _typingBubble()
                      ],
                      if (_systemMessage != null) ...[
                        const SizedBox(height: 12),
                        AppNotice(
                          text: _systemMessage!,
                          icon: Icons.info_outline_rounded,
                          background: const Color(0xFFFFF8ED),
                          foreground: const Color(0xFF8A6843),
                          iconColor: const Color(0xFFE39A3B),
                        ),
                      ],
                      if (!_available && !_initializing) ...[
                        const SizedBox(height: 12),
                        AppSecondaryButton(
                          label: _settingsRequired ? '打开系统设置' : '重新检测语音权限',
                          icon: _settingsRequired
                              ? Icons.settings_rounded
                              : Icons.refresh_rounded,
                          height: 50,
                          fontSize: 16,
                          onPressed: _handleVoiceAction,
                        ),
                      ],
                      const SizedBox(height: 8),
                      const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.info_outline_rounded,
                              size: 14, color: AppColors.muted2),
                          SizedBox(width: 5),
                          Text(
                            '回答仅供参考，具体用药请遵医嘱',
                            style: TextStyle(
                                fontSize: 14, color: AppColors.muted2),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            SizedBox(
              height: 46,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
                children: [
                  _quickAsk('今天该吃什么药？', () => _send('今天该吃什么药？')),
                  const SizedBox(width: 7),
                  _quickAsk('我的药还剩多少？', () => _send('我的药还剩多少？')),
                  const SizedBox(width: 7),
                  _quickAsk('确认服药', () => _send('确认服药')),
                  if (_xu_yao_que_ren) ...[
                    const SizedBox(width: 7),
                    _quickAsk('确认执行', () => _send('确认'), emphasized: true),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 6, 18, 12),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white),
                  boxShadow: const [
                    BoxShadow(
                        color: Color(0x24266AA6),
                        blurRadius: 26,
                        offset: Offset(0, 12)),
                  ],
                ),
                padding: const EdgeInsets.fromLTRB(8, 7, 8, 7),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    GestureDetector(
                      onTap: canMic ? _handleMicTap : _handleVoiceAction,
                      onLongPressStart:
                          canMic ? (_) => _handleMicLongPressStart() : null,
                      onLongPressEnd:
                          canMic ? (_) => _handleMicLongPressEnd() : null,
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          gradient: _cloudRecording
                              ? AppGradients.redButton
                              : AppGradients.primaryButton,
                          borderRadius: BorderRadius.circular(17),
                          boxShadow: AppShadows.soft,
                        ),
                        child: Icon(
                          _cloudRecording
                              ? Icons.stop_rounded
                              : Icons.mic_rounded,
                          color: Colors.white,
                          size: 25,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _textController,
                        enabled: !_jia_zai_zhong,
                        minLines: 1,
                        maxLines: 3,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _submitTypedQuestion(),
                        style: const TextStyle(fontSize: 18),
                        decoration: const InputDecoration(
                          hintText: '发消息，或按住说话…',
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          filled: false,
                          contentPadding: EdgeInsets.symmetric(vertical: 12),
                          hintStyle:
                              TextStyle(fontSize: 18, color: Color(0xFF8296A8)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 5),
                    SizedBox(
                      width: 45,
                      height: 45,
                      child: IconButton(
                        onPressed: _jia_zai_zhong ? null : _submitTypedQuestion,
                        style: IconButton.styleFrom(
                          backgroundColor: const Color(0xFFEAF7FF),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15)),
                        ),
                        icon: _jia_zai_zhong
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.blue,
                                ),
                              )
                            : const Icon(Icons.send_rounded,
                                color: AppColors.blue, size: 21),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _aiBubble(String text, {VoidCallback? onPlay}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AppIconTile(
          icon: Icons.auto_awesome_rounded,
          size: 38,
          iconSize: 20,
          gradient: AppGradients.primaryButton,
          color: Colors.white,
        ),
        const SizedBox(width: 9),
        Flexible(
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.94),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(7),
                topRight: Radius.circular(20),
                bottomLeft: Radius.circular(20),
                bottomRight: Radius.circular(20),
              ),
              border: Border.all(color: const Color(0xFFE3F1FA)),
              boxShadow: AppShadows.soft,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(
                  text,
                  style: const TextStyle(
                      fontSize: 19, height: 1.55, color: AppColors.ink2),
                ),
                if (onPlay != null)
                  TextButton.icon(
                    onPressed: onPlay,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 3, vertical: 4),
                      minimumSize: const Size(0, 32),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    icon: const Icon(Icons.volume_up_rounded, size: 18),
                    label: const Text('播放语音', style: TextStyle(fontSize: 14.5)),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _userBubble(String text) {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 300),
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
        decoration: BoxDecoration(
          gradient: AppGradients.primaryButton,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(7),
            bottomLeft: Radius.circular(20),
            bottomRight: Radius.circular(20),
          ),
          boxShadow: const [
            BoxShadow(
                color: Color(0x33368BEE), blurRadius: 18, offset: Offset(0, 9)),
          ],
        ),
        child: SelectableText(
          text,
          style: const TextStyle(
            fontSize: 19,
            height: 1.45,
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _typingBubble() {
    return Row(
      children: [
        const AppIconTile(
          icon: Icons.auto_awesome_rounded,
          size: 38,
          iconSize: 20,
          gradient: AppGradients.primaryButton,
          color: Colors.white,
        ),
        const SizedBox(width: 9),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE3F1FA)),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppColors.blue),
              ),
              SizedBox(width: 9),
              Text('正在查询用药计划…',
                  style: TextStyle(fontSize: 17, color: AppColors.muted)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _quickAsk(String label, VoidCallback onTap,
      {bool emphasized = false}) {
    return ActionChip(
      onPressed: onTap,
      label: Text(label),
      avatar:
          emphasized ? const Icon(Icons.check_circle_rounded, size: 18) : null,
      backgroundColor:
          emphasized ? AppColors.blue : Colors.white.withValues(alpha: 0.72),
      labelStyle: TextStyle(
        fontSize: 15.5,
        fontWeight: FontWeight.w700,
        color: emphasized ? Colors.white : const Color(0xFF44759B),
      ),
      side: BorderSide(color: emphasized ? AppColors.blue : Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    );
  }
}
