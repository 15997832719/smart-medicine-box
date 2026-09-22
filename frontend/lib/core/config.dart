class ApiConfig {
  ApiConfig._();

  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://smart-medicine-box.124.156.137.131.nip.io',
  );

  static const String apiPrefix = '/api/v1';

  static final Uri baseUri = Uri.parse(baseUrl);

  static Uri endpoint(String path, {Map<String, String>? query}) {
    final uri = baseUri.replace(path: path);
    if (query == null || query.isEmpty) return uri;
    return uri.replace(queryParameters: {...uri.queryParameters, ...query});
  }

  static const String login = '$apiPrefix/auth/login';
  static const String register = '$apiPrefix/auth/register';
  static const String bindFamily = '$apiPrefix/auth/bind-family';
  static const String generateBindCode = '$apiPrefix/auth/generate-bind-code';
  static const String myFamily = '$apiPrefix/auth/my-family';
  static const String pushToken = '$apiPrefix/devices/push-token';

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
