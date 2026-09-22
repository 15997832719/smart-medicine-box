import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'core/auth_service.dart';
import 'core/theme.dart';
import 'screens/auth/login_screen.dart';
import 'screens/child/child_home_screen.dart';
import 'screens/elder/elder_home_screen.dart';
import 'screens/elder/medication_confirm_screen.dart';
import 'services/api_service.dart';
import 'services/notification_service.dart';
import 'services/push_service.dart';

final _navigatorKey = GlobalKey<NavigatorState>();
AuthService? _authService;
MedicationReminderPayload? _pendingMedicationReminder;
bool _presentingMedicationReminder = false;
bool _presentCheckScheduled = false;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final auth = AuthService();
  _authService = auth;
  auth.addListener(_tryPresentMedicationReminder);
  NotificationService.instance.onMedicationReminderTap =
      _handleMedicationReminderTap;

  try {
    await NotificationService.instance.initialize();
    
    
    
    await NotificationService.instance.requestPermissions(
      requestExactAlarm: false,
    );
  } catch (_) {
    
    
  }

  try {
    await PushService.instance.initialize();
  } catch (_) {}

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );

  runApp(
    ChangeNotifierProvider.value(
      value: auth,
      child: const SmartMedicineApp(),
    ),
  );

  WidgetsBinding.instance.addPostFrameCallback(
    (_) => _tryPresentMedicationReminder(),
  );
}

void _handleMedicationReminderTap(MedicationReminderPayload reminder) {
  _pendingMedicationReminder = reminder;
  _tryPresentMedicationReminder();
}

void _tryPresentMedicationReminder() {
  if (_pendingMedicationReminder == null ||
      _presentingMedicationReminder ||
      _presentCheckScheduled) {
    return;
  }

  final auth = _authService;
  final navigator = _navigatorKey.currentState;
  if (auth == null || !auth.isLoggedIn || navigator == null) {
    _scheduleMedicationReminderCheck();
    return;
  }

  final reminder = _pendingMedicationReminder!;
  final dang_qian_yong_hu_bian_hao = auth.dang_qian_yong_hu?.id;
  if (reminder.yong_hu_bian_hao > 0 && dang_qian_yong_hu_bian_hao != reminder.yong_hu_bian_hao) {
    _pendingMedicationReminder = null;
    return;
  }

  _pendingMedicationReminder = null;
  _presentingMedicationReminder = true;
  navigator
      .push<void>(
    MaterialPageRoute(
      builder: (_) => MedicationConfirmScreen(
        ji_hua_bian_hao: reminder.ji_hua_bian_hao,
        yong_hu_bian_hao: reminder.yong_hu_bian_hao > 0 ? reminder.yong_hu_bian_hao : null,
        yao_pin_ming_cheng: reminder.yao_pin_ming_cheng,
        dosage: reminder.dose,
        ji_hua_shi_jian: reminder.ji_hua_shi_jian,
      ),
    ),
  )
      .whenComplete(() {
    _presentingMedicationReminder = false;
    _tryPresentMedicationReminder();
  });
}

void _scheduleMedicationReminderCheck() {
  if (_presentCheckScheduled) return;
  _presentCheckScheduled = true;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    _presentCheckScheduled = false;
    _tryPresentMedicationReminder();
  });
}

class SmartMedicineApp extends StatelessWidget {
  const SmartMedicineApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: '????',
      debugShowCheckedModeBanner: false,
      theme: ElderTheme.lightTheme,
      home: const AuthWrapper(),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthService>(context);
    ApiService.init(auth);

    if (auth.isLoading) {
      return const Scaffold(
        backgroundColor: ElderTheme.bgColor,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.medication_rounded,
                  size: 80, color: ElderTheme.primaryColor),
              SizedBox(height: 24),
              Text(
                '????',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: ElderTheme.textPrimary,
                ),
              ),
              SizedBox(height: 32),
              CircularProgressIndicator(
                valueColor:
                    AlwaysStoppedAnimation<Color>(ElderTheme.primaryColor),
              ),
            ],
          ),
        ),
      );
    }

    if (auth.isLoggedIn) {
      final role = auth.dang_qian_yong_hu?.role ?? 'elder';
      return role == 'child' ? const ChildHomeScreen() : const ElderHomeScreen();
    }

    return const LoginScreen();
  }
}
