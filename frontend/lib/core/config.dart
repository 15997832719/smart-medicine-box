class ApiConfig {
  ApiConfig._();

  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://smart-medicine-box.124.156.137.131.nip.io',
  );

  static const String apiPrefix = '/api/v1';

  static final Uri baseUri = Uri.parse(baseUrl);

  static String resolveMediaUrl(String? path) {
    if (path == null || path.trim().isEmpty) return '';
    final uri = Uri.tryParse(path);
    if (uri != null && uri.hasScheme) return path;
    return baseUri.resolve(path).toString();
  }

  static Uri endpoint(String path, {Map<String, String>? query}) {
    final uri = baseUri.replace(path: path);
    if (query == null || query.isEmpty) return uri;
    return uri.replace(queryParameters: {...uri.queryParameters, ...query});
  }

  static const String login = '$apiPrefix/auth/login';
  static const String profile = '$apiPrefix/auth/profile';
  static const String profileAvatar = '$apiPrefix/auth/profile/avatar';
  static const String register = '$apiPrefix/auth/register';
  static const String bindFamily = '$apiPrefix/auth/bind-family';
  static const String generateBindCode = '$apiPrefix/auth/generate-bind-code';
  static const String myFamily = '$apiPrefix/auth/my-family';
  static const String activationStart = '$apiPrefix/auth/activation/start';
  static const String activationClaim = '$apiPrefix/auth/activation/claim';
  static const String activationExchange = '$apiPrefix/auth/activation/exchange';
  static const String faceLogin = '$apiPrefix/face/login';
  static const String faceEnroll = '$apiPrefix/face/enroll';
  static const String faceConsent = '$apiPrefix/face/consent';
  static const String faceStatus = '$apiPrefix/face/status';
  static const String smsSend = '$apiPrefix/auth/sms/send';
  static const String smsLogin = '$apiPrefix/auth/sms/login';
  static const String deviceEnable = '$apiPrefix/auth/device/enable';
  static const String deviceLogin = '$apiPrefix/auth/device/login';
  static const String authDevices = '$apiPrefix/auth/devices';
  static const String pushToken = '$apiPrefix/devices/push-token';
  static const String hardwareDevices = '$apiPrefix/hardware-devices';
  static String hardwareDeviceCommands(int deviceId) =>
      '$apiPrefix/hardware-devices/$deviceId/commands';
  static String hardwareDeviceCommand(int deviceId, int commandId) =>
      '$apiPrefix/hardware-devices/$deviceId/commands/$commandId';
  static String hardwareDeviceFaces(int deviceId) => '$apiPrefix/hardware-devices/$deviceId/faces';
  static String hardwareDeviceFace(int deviceId, int faceId) =>
      '$apiPrefix/hardware-devices/$deviceId/faces/$faceId';
  static String hardwareDeviceCameraAssets(int deviceId) =>
      '$apiPrefix/hardware-devices/$deviceId/camera/assets';
  static String hardwareDeviceCameraAssetFile(int deviceId, int assetId) =>
      '$apiPrefix/hardware-devices/$deviceId/camera/assets/$assetId/file';
  static String hardwareDeviceCameraAssetThumbnail(int deviceId, int assetId) =>
      '$apiPrefix/hardware-devices/$deviceId/camera/assets/$assetId/thumbnail';
  static String hardwareDeviceCameraAssetReview(int deviceId, int assetId) =>
      '$apiPrefix/hardware-devices/$deviceId/camera/assets/$assetId/review';
  static String hardwareDeviceCameraPreviewStart(int deviceId) =>
      '$apiPrefix/hardware-devices/$deviceId/camera/preview/start';
  static String hardwareDeviceCameraPreviewStop(int deviceId) =>
      '$apiPrefix/hardware-devices/$deviceId/camera/preview/stop';
  static String hardwareDeviceCameraPreviewStatus(int deviceId) =>
      '$apiPrefix/hardware-devices/$deviceId/camera/preview/status';
  static String hardwareDeviceCameraPreviewFrame(int deviceId) =>
      '$apiPrefix/hardware-devices/$deviceId/camera/preview/frame';
  static String hardwareDeviceCameraPreviewWs(int deviceId) =>
      '$apiPrefix/hardware-devices/$deviceId/camera/preview/ws';
  static String hardwareDeviceRecognitionEvents(int deviceId) =>
      '$apiPrefix/hardware-devices/$deviceId/recognition-events';
  static String hardwareDeviceRuntime(int deviceId) =>
      '$apiPrefix/hardware-devices/$deviceId/runtime';

  static const String medicines = '$apiPrefix/medicines';
  static const String aiRecognize = '$apiPrefix/ai/recognize-medicine';
  static const String aiStatus = '$apiPrefix/ai/status';
  static const String parseInstruction = '$apiPrefix/ai/parse-instruction';
  static const String expiring = '$apiPrefix/medicines/expiring/list';
  static const String alerts = '$apiPrefix/alerts';

  static const String schedules = '$apiPrefix/schedules';

  static const String logsToday = '$apiPrefix/logs/today';
  static const String logsWeek = '$apiPrefix/logs/week';
  static const String logsConfirm = '$apiPrefix/logs/confirm';
  static const String voiceTranscribe = '$apiPrefix/voice/transcribe';
  static const String logsVoiceIntent = '$apiPrefix/logs/voice-intent';
  static String logsHistory(int yong_hu_bian_hao) => '$apiPrefix/logs/history/$yong_hu_bian_hao';
}
