import 'dart:io';



class PushService {
  PushService._();
  static final instance = PushService._();
  bool _ready = false;

  Future<void> initialize() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    if (_ready) return;
    
    
    _ready = true;
  }

  Future<void> zhu_ce_dang_qian_she_bei() async {
    await initialize();
    if (!_ready) return;
    return;
  }
}
