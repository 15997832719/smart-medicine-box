import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../core/design_system.dart';
import '../../services/api_service.dart';

class SmartBoxCameraScreen extends StatefulWidget {
  const SmartBoxCameraScreen({super.key, required this.device});

  final Map<String, dynamic> device;

  @override
  State<SmartBoxCameraScreen> createState() => _SmartBoxCameraScreenState();
}

class _SmartBoxCameraScreenState extends State<SmartBoxCameraScreen> {
  bool _loading = true;
  bool _busy = false;
  String? _error;
  List<Map<String, dynamic>> _assets = <Map<String, dynamic>>[];
  bool _previewActive = false;
  Timer? _previewTimer;
  int _previewTicks = 0;
  Map<String, dynamic> _runtime = <String, dynamic>{};
  List<Map<String, dynamic>> _recognitionEvents = <Map<String, dynamic>>[];

  Uint8List? _previewBytes;
  bool _previewFetching = false;
  WebSocket? _previewSocket;
  StreamSubscription<dynamic>? _previewSocketSubscription;
  bool _previewSocketConnecting = false;
  bool _previewSocketFallback = false;
  DateTime? _lastPreviewSocketAttempt;
  DateTime? _previewSocketConnectedAt;
  DateTime? _lastPreviewSocketFrameAt;
  int _previewSocketGeneration = 0;
  String? _previewError;
  int? get _deviceId => int.tryParse('${widget.device['id']}');

  Map<String, dynamic>? get _latestSnapshot {
    for (final asset in _assets) {
      if ('${asset['kind']}' == 'camera_snapshot') return asset;
    }
    return null;
  }

  List<Map<String, dynamic>> get _videos =>
      _assets.where((asset) => '${asset['kind']}' == 'intake_video').toList();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _previewTimer?.cancel();
    _previewSocketSubscription?.cancel();
    _previewSocket?.close();
    final deviceId = _deviceId;
    if (_previewActive && deviceId != null) {
      unawaited(ApiService.stopHardwareCameraPreview(deviceId));
    }
    super.dispose();
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
    try {
      final results = await Future.wait<Object>([
        ApiService.getHardwareCameraAssets(
          deviceId,
          kind: 'camera_snapshot',
          limit: 1,
        ),
        ApiService.getHardwareCameraAssets(
          deviceId,
          kind: 'intake_video',
          limit: 50,
        ),
        ApiService.getHardwareRecognitionEvents(deviceId),
        ApiService.getHardwareRuntime(deviceId),
      ]);
      final snapshots = (results[0] as List).cast<Map<String, dynamic>>();
      final videos = (results[1] as List).cast<Map<String, dynamic>>();
      final events = (results[2] as List).cast<Map<String, dynamic>>();
      if (!mounted) return;
      setState(() {
        _assets = [...snapshots, ...videos];
        _recognitionEvents = events;
        _runtime = Map<String, dynamic>.from(results[3] as Map);
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _captureSnapshot() async {
    await _runCommand(
      commandType: 'camera_snapshot',
      title: '远程抓拍',
      payload: const <String, dynamic>{},
    );
  }

  Future<void> _recordIntake() async {
    final ownerId = int.tryParse('${widget.device['owner_id']}');
    await _runCommand(
      commandType: 'intake_record',
      title: '录制服药视频',
      payload: {
        'duration': 20,
        if (ownerId != null) 'user_id': ownerId,
      },
    );
  }

  Future<void> _togglePreview() async {
    if (_previewActive) {
      await _stopPreview();
    } else {
      await _startPreview();
    }
  }

  Future<void> _startPreview() async {
    final deviceId = _deviceId;
    if (deviceId == null || _previewActive) return;
    try {
      await ApiService.startHardwareCameraPreview(deviceId);
      if (!mounted) return;
      setState(() {
        _previewActive = true;
        _previewTicks = 0;
        _previewError = null;
        _previewSocketFallback = true;
        _previewSocketConnectedAt = null;
        _lastPreviewSocketFrameAt = null;
      });
      _previewTimer?.cancel();
      _previewTimer =
          Timer.periodic(const Duration(milliseconds: 250), (timer) {
        if (!mounted || !_previewActive) return;
        _previewTicks++;
        if (_previewTicks % 40 == 0) {
          unawaited(ApiService.startHardwareCameraPreview(deviceId));
        }
        _checkPreviewSocketHealth();
        if (_previewSocket == null && !_previewSocketConnecting) {
          unawaited(_connectPreviewSocket(deviceId));
        }
        if (_previewSocketFallback) {
          unawaited(_refreshPreviewFrame(deviceId));
        }
      });
      // Show an HTTP frame immediately while the lower-latency socket connects.
      unawaited(_refreshPreviewFrame(deviceId));
      unawaited(_connectPreviewSocket(deviceId));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(error.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  Future<void> _stopPreview() async {
    final wasActive = _previewActive;
    _previewTimer?.cancel();
    _previewTimer = null;
    _previewFetching = false;
    _previewSocketConnecting = false;
    _previewSocketGeneration++;
    _previewSocketConnectedAt = null;
    _lastPreviewSocketFrameAt = null;
    await _previewSocketSubscription?.cancel();
    _previewSocketSubscription = null;
    await _previewSocket?.close();
    _previewSocket = null;
    if (mounted) {
      setState(() {
        _previewActive = false;
        _previewBytes = null;
        _previewError = null;
        _previewSocketFallback = false;
      });
    }
    if (!wasActive) return;
    final deviceId = _deviceId;
    if (deviceId == null) return;
    try {
      await ApiService.stopHardwareCameraPreview(deviceId);
    } catch (_) {}
  }

  Future<void> _connectPreviewSocket(int deviceId) async {
    if (!_previewActive || _previewSocket != null || _previewSocketConnecting) {
      return;
    }
    final now = DateTime.now();
    final lastAttempt = _lastPreviewSocketAttempt;
    if (lastAttempt != null &&
        now.difference(lastAttempt) < const Duration(seconds: 8)) {
      return;
    }
    _lastPreviewSocketAttempt = now;
    _previewSocketConnecting = true;
    final generation = ++_previewSocketGeneration;
    try {
      final socket =
          await ApiService.connectHardwareCameraPreviewSocket(deviceId);
      if (!mounted ||
          !_previewActive ||
          generation != _previewSocketGeneration) {
        await socket.close();
        return;
      }
      _previewSocket = socket;
      _previewSocketConnectedAt = DateTime.now();
      _lastPreviewSocketFrameAt = null;
      _previewSocketSubscription = socket.listen(
        (data) {
          if (!mounted ||
              !_previewActive ||
              generation != _previewSocketGeneration ||
              !identical(_previewSocket, socket) ||
              data is! List<int>) {
            return;
          }
          setState(() {
            _previewBytes = Uint8List.fromList(data);
            _previewError = null;
            _previewSocketFallback = false;
            _lastPreviewSocketFrameAt = DateTime.now();
          });
        },
        onError: (_) {
          unawaited(_handlePreviewSocketClosed(
              socket: socket, generation: generation));
        },
        onDone: () {
          unawaited(_handlePreviewSocketClosed(
              socket: socket, generation: generation));
        },
        cancelOnError: true,
      );
    } catch (error) {
      if (generation != _previewSocketGeneration) return;
      _previewSocketConnectedAt = null;
      _lastPreviewSocketFrameAt = null;
      _previewSocketFallback = true;
      if (mounted && _previewActive) {
        setState(() {
          _previewError = error.toString().replaceFirst('Exception: ', '');
        });
      }
    } finally {
      if (generation == _previewSocketGeneration) {
        _previewSocketConnecting = false;
      }
    }
  }

  void _checkPreviewSocketHealth() {
    final socket = _previewSocket;
    final connectedAt = _previewSocketConnectedAt;
    if (socket == null || connectedAt == null) return;
    final now = DateTime.now();
    final lastFrameAt = _lastPreviewSocketFrameAt;
    final stalled = lastFrameAt == null
        ? now.difference(connectedAt) >= const Duration(seconds: 3)
        : now.difference(lastFrameAt) >= const Duration(seconds: 3);
    if (stalled) {
      unawaited(_fallbackFromPreviewSocket(expectedSocket: socket));
    }
  }

  Future<void> _fallbackFromPreviewSocket({WebSocket? expectedSocket}) async {
    final socket = _previewSocket;
    if (expectedSocket != null && !identical(socket, expectedSocket)) return;
    _previewSocketGeneration++;
    _previewSocket = null;
    _previewSocketConnectedAt = null;
    _lastPreviewSocketFrameAt = null;
    final subscription = _previewSocketSubscription;
    _previewSocketSubscription = null;
    await subscription?.cancel();
    try {
      await socket?.close();
    } catch (_) {}
    if (!_previewActive) return;
    _previewSocketFallback = true;
    if (mounted) setState(() {});
  }

  Future<void> _handlePreviewSocketClosed({
    required WebSocket socket,
    required int generation,
  }) async {
    if (generation != _previewSocketGeneration ||
        !identical(_previewSocket, socket)) {
      return;
    }
    await _fallbackFromPreviewSocket(expectedSocket: socket);
  }

  Future<void> _refreshPreviewFrame(int deviceId) async {
    if (_previewFetching || !_previewActive || !_previewSocketFallback) return;
    _previewFetching = true;
    try {
      final bytes = await ApiService.getHardwareCameraPreviewFrame(deviceId);
      if (!mounted || !_previewActive) return;
      setState(() {
        _previewBytes = bytes;
        _previewError = null;
      });
    } catch (error) {
      if (!mounted || !_previewActive) return;
      setState(() {
        _previewError = error.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      _previewFetching = false;
    }
  }

  Future<void> _enrollOwnerFace() async {
    final deviceId = _deviceId;
    final ownerId = int.tryParse('${widget.device['owner_id']}');
    if (deviceId == null || ownerId == null) return;
    if (!_previewActive) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先开启实时预览，再注册人脸')),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('注册老人人脸'),
        content: const Text('请让老人正对摄像头，注册过程中会连续采集 5 张样本。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('开始注册')),
        ],
      ),
    );
    if (confirmed != true) return;
    await _runCommand(
      commandType: 'face_enroll',
      title: '老人人脸注册',
      payload: {'user_id': ownerId, 'samples': 5},
    );
  }

  Future<void> _runCommand({
    required String commandType,
    required String title,
    required Map<String, dynamic> payload,
  }) async {
    final deviceId = _deviceId;
    if (deviceId == null || _busy) return;
    setState(() => _busy = true);
    try {
      final command = await ApiService.createHardwareDeviceCommand(
        deviceId: deviceId,
        commandType: commandType,
        payload: payload,
      );
      final commandId = int.tryParse('${command['id']}');
      if (commandId == null) throw Exception('设备没有返回任务编号');
      if (!mounted) return;
      final result = await showDialog<Map<String, dynamic>>(
        context: context,
        barrierDismissible: false,
        builder: (context) => _CameraCommandProgressDialog(
          deviceId: deviceId,
          commandId: commandId,
          title: title,
        ),
      );
      if (!mounted) return;
      if (result != null && '${result['status']}' == 'completed') {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$title已完成')),
        );
      }
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(error.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openVideo(Map<String, dynamic> asset) async {
    final deviceId = _deviceId;
    final assetId = int.tryParse('${asset['id']}');
    if (deviceId == null || assetId == null) return;
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CameraVideoScreen(
          deviceId: deviceId,
          asset: asset,
        ),
      ),
    );
    if (changed == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final online = '${widget.device['status']}' == 'online';
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('摄像头与服药记录')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 30),
          children: [
            AppGlassCard(
              radius: 24,
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  AppIconTile(
                    icon: Icons.videocam_rounded,
                    size: 50,
                    iconSize: 27,
                    background:
                        online ? AppColors.mintTint : const Color(0xFFF1F4F7),
                    color: online ? AppColors.mintDeep : AppColors.muted,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${widget.device['name'] ?? '智能药箱'}',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: AppColors.ink,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          online ? '香橙派在线，可远程抓拍和上传服药录像' : '香橙派离线，请检查电源和网络',
                          style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.muted,
                              height: 1.4),
                        ),
                      ],
                    ),
                  ),
                  AppPill(
                    label: online ? '在线' : '离线',
                    background:
                        online ? AppColors.mintTint : const Color(0xFFF1F4F7),
                    foreground: online ? AppColors.mintDeep : AppColors.muted,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            _runtimePills(),
            const SizedBox(height: 14),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              AppNotice(text: _error!, icon: Icons.error_outline_rounded)
            else ...[
              _snapshotCard(),
              const SizedBox(height: 14),
              AppGradientButton(
                label: _previewActive ? '停止实时预览' : '开始实时预览',
                icon: _previewActive
                    ? Icons.stop_circle_outlined
                    : Icons.play_circle_outline_rounded,
                height: 52,
                fontSize: 17,
                onPressed: _busy ? null : _togglePreview,
              ),
              const SizedBox(height: 9),
              AppSecondaryButton(
                label: '抓拍一张画面',
                icon: Icons.camera_alt_rounded,
                height: 48,
                fontSize: 15,
                onPressed: _busy ? null : _captureSnapshot,
              ),
              const SizedBox(height: 8),
              AppSecondaryButton(
                label: '在实时画面中注册老人人脸',
                icon: Icons.face_retouching_natural_rounded,
                height: 48,
                fontSize: 15,
                onPressed: _busy ? null : _enrollOwnerFace,
              ),
              const SizedBox(height: 8),
              AppSecondaryButton(
                label: '录制 20 秒服药视频',
                icon: Icons.fiber_manual_record_rounded,
                height: 48,
                fontSize: 15,
                onPressed: _busy ? null : _recordIntake,
              ),
              const SizedBox(height: 8),
              Text(
                _previewActive
                    ? '实时预览已开启，画面约每 0.2 秒刷新一次；可让人正对摄像头进行注册。'
                    : '实时预览需要香橙派在线。开始后在当前页面保持打开，离开页面会自动关闭。',
                style: const TextStyle(
                    fontSize: 12, color: AppColors.muted, height: 1.5),
              ),
              const AppSectionTitle(title: '服药录像'),
              if (_videos.isEmpty)
                const AppNotice(
                  text: '暂无服药录像。点击上方按钮可录一段测试视频，录像默认不含声音。',
                  icon: Icons.video_library_outlined,
                )
              else
                for (final video in _videos) ...[
                  _videoCard(video),
                  const SizedBox(height: 10),
                ],
              const AppSectionTitle(title: '最近识别'),
              if (_recognitionEvents.isEmpty)
                const AppNotice(
                  text: '还没有识别事件。雷达触发并完成人脸识别后，这里会显示记录。',
                  icon: Icons.face_retouching_natural_rounded,
                )
              else
                for (final event in _recognitionEvents.take(5)) ...[
                  _recognitionRow(event),
                  const SizedBox(height: 8),
                ],
              const SizedBox(height: 8),
              const SizedBox(height: 8),
              const AppNotice(
                text:
                    '录像只作为“疑似服药”的证据，需要家属在 App 中确认，不会自动写成已服药记录。素材仅家庭账号和已绑定设备可访问。',
                icon: Icons.shield_outlined,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _runtimePills() {
    final radarPresent = _runtime['radar_present'] == true;
    final radarDistance = _runtime['radar_distance_cm'];
    final xiaozhi = '${_runtime['xiaozhi_state'] ?? 'idle'}';
    final syn = '${_runtime['syn6288_state'] ?? 'idle'}';
    String xiaozhiLabel() {
      if (xiaozhi == 'listening') return '小智聆听中';
      if (xiaozhi == 'speaking') return '小智播报中';
      return '小智空闲';
    }

    return Wrap(
      spacing: 7,
      runSpacing: 7,
      children: [
        AppPill(
          label: radarPresent
              ? '雷达有人${radarDistance == null ? '' : ' ${radarDistance}cm'}'
              : '雷达无人',
          icon: Icons.sensors_rounded,
          fontSize: 11,
        ),
        AppPill(
          label: xiaozhiLabel(),
          icon: Icons.record_voice_over_rounded,
          fontSize: 11,
        ),
        AppPill(
          label: syn == 'speaking' ? 'SYN6288 播报中' : 'SYN6288 空闲',
          icon: Icons.volume_up_rounded,
          fontSize: 11,
        ),
      ],
    );
  }

  Widget _recognitionRow(Map<String, dynamic> event) {
    final identityRole = '${event['identity_role']}';
    final eventType = '${event['event_type']}';
    final stranger = identityRole == 'stranger';
    final known = identityRole == 'elder' || identityRole == 'child';
    final label = stranger
        ? '陌生人'
        : (identityRole == 'elder'
            ? '老人'
            : (identityRole == 'child'
                ? '子女'
                : (eventType == 'unknown' || eventType == 'no_face'
                    ? '未识别人员'
                    : '已识别人员')));
    final subtitle = stranger ? '不播报个人用药' : (known ? '将按身份查询对应药箱' : '不会播报个人用药');
    final score = num.tryParse('${event['score']}');
    return AppGlassCard(
      radius: 18,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      shadow: false,
      child: Row(
        children: [
          Icon(
            stranger
                ? Icons.person_off_rounded
                : (known
                    ? Icons.verified_user_rounded
                    : Icons.help_outline_rounded),
            color: known ? AppColors.mintDeep : AppColors.muted,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, color: AppColors.ink2),
                ),
                Text(
                  '${_formatTime(event['occurred_at'])} · $subtitle',
                  style: const TextStyle(fontSize: 11, color: AppColors.muted),
                ),
              ],
            ),
          ),
          if (score != null)
            AppPill(
              label: '${(score * 100).round()}%',
              fontSize: 11,
            ),
        ],
      ),
    );
  }

  Widget _snapshotCard() {
    final snapshot = _latestSnapshot;
    final assetId = snapshot == null ? null : int.tryParse('${snapshot['id']}');
    final deviceId = _deviceId;
    Widget previewContent;
    if (_previewActive) {
      final bytes = _previewBytes;
      previewContent = bytes == null
          ? _snapshotPlaceholder(
              true,
              message: _previewError ?? '正在连接实时画面…',
            )
          : Image.memory(
              bytes,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              cacheWidth: 640,
              filterQuality: FilterQuality.low,
              errorBuilder: (_, __, ___) => _snapshotPlaceholder(
                true,
                message: _previewError ?? '画面解码失败，正在重试…',
              ),
            );
    } else {
      previewContent = snapshot != null && assetId != null && deviceId != null
          ? Image.network(
              ApiService.hardwareCameraAssetFileUri(deviceId, assetId)
                  .toString(),
              headers: ApiService.authenticatedMediaHeaders,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (_, __, ___) => _snapshotPlaceholder(false),
            )
          : _snapshotPlaceholder(true);
    }
    return AppGlassCard(
      radius: 24,
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          children: [
            AspectRatio(aspectRatio: 16 / 9, child: previewContent),
            Positioned(
              left: 12,
              bottom: 12,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xB30A2547),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _previewActive
                      ? (_previewBytes == null ? '正在连接…' : '实时预览中')
                      : snapshot == null
                          ? '还没有远程画面'
                          : _formatTime(snapshot['captured_at']),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700),
                ),
              ),
            ),
            Positioned(
              right: 8,
              top: 8,
              child: AppCircleButton(
                icon: Icons.refresh_rounded,
                tooltip: '刷新',
                onPressed: _loading ? null : _load,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _snapshotPlaceholder(bool noSnapshot, {String? message}) {
    return Container(
      color: const Color(0xFFEAF4FB),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.photo_camera_back_rounded,
                size: 44, color: AppColors.blue),
            const SizedBox(height: 8),
            Text(
              message ?? (noSnapshot ? '抓拍后会显示在这里' : '画面加载失败，请点抓拍重试'),
              style: const TextStyle(
                  color: AppColors.muted, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _videoCard(Map<String, dynamic> video) {
    final deviceId = _deviceId;
    final assetId = int.tryParse('${video['id']}');
    final hasThumb =
        video['thumbnail_url'] != null && deviceId != null && assetId != null;
    final review = _reviewStyle('${video['status']}');
    return AppGlassCard(
      radius: 20,
      padding: const EdgeInsets.all(10),
      onTap: () => _openVideo(video),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              width: 112,
              height: 72,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (hasThumb)
                    Image.network(
                      ApiService.hardwareCameraAssetThumbnailUri(
                              deviceId, assetId)
                          .toString(),
                      headers: ApiService.authenticatedMediaHeaders,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          const ColoredBox(color: Color(0xFFE8F3FA)),
                    )
                  else
                    const ColoredBox(color: Color(0xFFE8F3FA)),
                  const Center(
                    child: CircleAvatar(
                      radius: 20,
                      backgroundColor: Color(0xB30A2547),
                      child: Icon(Icons.play_arrow_rounded,
                          color: Colors.white, size: 28),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '服药录像 · ${_formatTime(video['captured_at'])}',
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink2),
                ),
                const SizedBox(height: 6),
                Text(
                  _durationText(video['duration_seconds']),
                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                ),
                const SizedBox(height: 8),
                AppPill(
                  label: review.$1,
                  background: review.$2,
                  foreground: review.$3,
                  fontSize: 11,
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
        ],
      ),
    );
  }
}

class CameraVideoScreen extends StatefulWidget {
  const CameraVideoScreen(
      {super.key, required this.deviceId, required this.asset});

  final int deviceId;
  final Map<String, dynamic> asset;

  @override
  State<CameraVideoScreen> createState() => _CameraVideoScreenState();
}

class _CameraVideoScreenState extends State<CameraVideoScreen> {
  VideoPlayerController? _controller;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    final assetId = int.tryParse('${widget.asset['id']}');
    if (assetId == null) {
      setState(() {
        _loading = false;
        _error = '录像编号无效';
      });
      return;
    }
    final controller = VideoPlayerController.networkUrl(
      ApiService.hardwareCameraAssetFileUri(widget.deviceId, assetId),
      httpHeaders: ApiService.authenticatedMediaHeaders,
    );
    _controller = controller;
    controller.addListener(_onPlayerChanged);
    try {
      await controller.initialize();
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '视频加载失败：$error';
      });
    }
  }

  void _onPlayerChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    final controller = _controller;
    controller?.removeListener(_onPlayerChanged);
    controller?.dispose();
    super.dispose();
  }

  Future<void> _review(String status) async {
    final assetId = int.tryParse('${widget.asset['id']}');
    if (assetId == null || _saving) return;
    setState(() => _saving = true);
    try {
      await ApiService.reviewHardwareCameraAsset(
        deviceId: widget.deviceId,
        assetId: assetId,
        status: status,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(error.toString().replaceFirst('Exception: ', ''))),
      );
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('服药录像')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 30),
        children: [
          AppGlassCard(
            radius: 22,
            padding: const EdgeInsets.all(12),
            child: _loading
                ? const AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Center(child: CircularProgressIndicator()),
                  )
                : _error != null
                    ? AspectRatio(
                        aspectRatio: 16 / 9,
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              _error!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  color: AppColors.red, height: 1.5),
                            ),
                          ),
                        ),
                      )
                    : _player(),
          ),
          const SizedBox(height: 14),
          const AppNotice(
            text: '这段录像没有录制声音。请结合老人实际情况确认，系统不会自动把“看到动作”当成已经服药。',
            icon: Icons.hearing_disabled_rounded,
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: AppSecondaryButton(
                  label: '不是服药',
                  icon: Icons.close_rounded,
                  height: 50,
                  fontSize: 15,
                  foreground: AppColors.red,
                  onPressed: _saving ? null : () => _review('not_taken'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: AppGradientButton(
                  label: '确认已服药',
                  icon: Icons.check_rounded,
                  height: 50,
                  fontSize: 15,
                  loading: _saving,
                  onPressed: _saving ? null : () => _review('confirmed_taken'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _player() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const SizedBox.shrink();
    }
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: AspectRatio(
            aspectRatio: controller.value.aspectRatio,
            child: VideoPlayer(controller),
          ),
        ),
        const SizedBox(height: 8),
        VideoProgressIndicator(
          controller,
          allowScrubbing: true,
          colors: const VideoProgressColors(
            playedColor: AppColors.blue,
            bufferedColor: Color(0x663A91F5),
            backgroundColor: Color(0x1A5B7692),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            IconButton(
              onPressed: () {
                if (controller.value.isPlaying) {
                  controller.pause();
                } else {
                  controller.play();
                }
              },
              icon: Icon(
                controller.value.isPlaying
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
                color: AppColors.blue,
                size: 30,
              ),
            ),
            Text(
              '${_formatDuration(controller.value.position)} / ${_formatDuration(controller.value.duration)}',
              style: const TextStyle(fontSize: 12, color: AppColors.muted),
            ),
            const Spacer(),
            const AppPill(
                label: '无声音', icon: Icons.volume_off_rounded, fontSize: 11),
          ],
        ),
      ],
    );
  }
}

class _CameraCommandProgressDialog extends StatefulWidget {
  const _CameraCommandProgressDialog({
    required this.deviceId,
    required this.commandId,
    required this.title,
  });

  final int deviceId;
  final int commandId;
  final String title;

  @override
  State<_CameraCommandProgressDialog> createState() =>
      _CameraCommandProgressDialogState();
}

class _CameraCommandProgressDialogState
    extends State<_CameraCommandProgressDialog> {
  String _status = 'pending';
  Map<String, dynamic>? _command;
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
    if (_polls++ > 120) {
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
        _command = command;
        _error = command['error']?.toString();
      });
      if (status == 'completed' || status == 'failed' || status == 'expired') {
        return;
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    }
  }

  bool get _done =>
      _status == 'completed' ||
      _status == 'failed' ||
      _status == 'expired' ||
      _error != null;

  @override
  Widget build(BuildContext context) {
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
              _status == 'claimed' ? '香橙派正在拍摄并上传，请不要关闭电源…' : '等待香橙派接收任务…',
              style: const TextStyle(height: 1.5),
            ),
          ] else if (_status == 'completed') ...[
            const Icon(Icons.check_circle_rounded,
                color: AppColors.mintDeep, size: 42),
            const SizedBox(height: 10),
            const Text('画面或录像已上传到 App',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          ] else ...[
            const Icon(Icons.error_outline_rounded,
                color: AppColors.red, size: 42),
            const SizedBox(height: 10),
            Text(_error ?? '设备执行失败', style: const TextStyle(height: 1.5)),
          ],
        ],
      ),
      actions: [
        if (_done)
          FilledButton(
            onPressed: () => Navigator.pop(context, _command),
            child: const Text('完成'),
          ),
      ],
    );
  }
}

String _formatTime(Object? raw) {
  final parsed = DateTime.tryParse('${raw ?? ''}')?.toLocal();
  if (parsed == null) return '时间未知';
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(parsed.month)}-${two(parsed.day)} ${two(parsed.hour)}:${two(parsed.minute)}';
}

String _durationText(Object? raw) {
  final seconds = num.tryParse('${raw ?? ''}');
  if (seconds == null || seconds <= 0) return '时长未知';
  return '约 ${seconds.round()} 秒 · 点击播放';
}

String _formatDuration(Duration duration) {
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

(String, Color, Color) _reviewStyle(String status) {
  if (status == 'confirmed_taken') {
    return ('已确认服药', AppColors.mintTint, AppColors.mintDeep);
  }
  if (status == 'not_taken') {
    return ('未确认服药', AppColors.redTint, AppColors.red);
  }
  return ('待家属确认', AppColors.peachTint, const Color(0xFFB65D18));
}
