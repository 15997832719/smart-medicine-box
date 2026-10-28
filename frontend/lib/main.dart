import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/auth_service.dart';
import 'core/design_system.dart';
import 'core/theme.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/privacy_consent_screen.dart';
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

    await NotificationService.instance
        .requestPermissions(requestExactAlarm: false);
  } catch (_) {}

  try {
    await PushService.instance.initialize();
  } catch (_) {}

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );

  runApp(ChangeNotifierProvider.value(
      value: auth, child: const SmartMedicineApp()));

  WidgetsBinding.instance
      .addPostFrameCallback((_) => _tryPresentMedicationReminder());
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
  if (reminder.yong_hu_bian_hao > 0 &&
      dang_qian_yong_hu_bian_hao != reminder.yong_hu_bian_hao) {
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
        yong_hu_bian_hao:
            reminder.yong_hu_bian_hao > 0 ? reminder.yong_hu_bian_hao : null,
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
      title: '智能药箱',
      debugShowCheckedModeBanner: false,
      theme: ElderTheme.lightTheme,
      builder: (context, child) {
        final media = MediaQuery.of(context);
        final currentScale = media.textScaler.scale(1);
        final accessibleMedia = currentScale < 1.1
            ? media.copyWith(textScaler: const TextScaler.linear(1.1))
            : media;
        return MediaQuery(
          data: accessibleMedia,
          child: DecoratedBox(
            decoration: const BoxDecoration(gradient: AppGradients.background),
            child: child ?? const SizedBox.shrink(),
          ),
        );
      },
      home: const PrivacyGate(),
    );
  }
}

class PrivacyGate extends StatefulWidget {
  const PrivacyGate({super.key});

  @override
  State<PrivacyGate> createState() => _PrivacyGateState();
}

class _PrivacyGateState extends State<PrivacyGate> {
  bool _loading = true;
  bool _accepted = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _accepted = prefs.getBool('privacy_consent_v1') ?? false;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const _AppSplash();
    }
    if (!_accepted) {
      return PrivacyConsentScreen(
          onAccepted: () => setState(() => _accepted = true));
    }
    return const AuthWrapper();
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthService>(context);
    ApiService.init(auth);

    if (auth.isLoading) {
      return const _AppSplash();
    }

    if (auth.isLoggedIn) {
      final role = auth.dang_qian_yong_hu?.role ?? 'elder';
      return role == 'child'
          ? const ChildHomeScreen()
          : const ElderHomeScreen();
    }

    return const LoginScreen();
  }
}

class _AppSplash extends StatelessWidget {
  const _AppSplash();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 116,
              height: 116,
              decoration: BoxDecoration(
                gradient: AppGradients.glass,
                borderRadius: BorderRadius.circular(38),
                border: Border.all(color: Colors.white, width: 1.3),
                boxShadow: AppShadows.card,
              ),
              child: const Icon(Icons.medication_rounded,
                  size: 62, color: AppColors.blue),
            ),
            const SizedBox(height: 24),
            const Text(
              '智能药箱',
              style: TextStyle(
                  fontSize: 38,
                  fontWeight: FontWeight.w900,
                  color: AppColors.ink),
            ),
            const SizedBox(height: 8),
            const Text(
              '让每一次服药，都被温柔守护',
              style: TextStyle(
                  fontSize: 17,
                  color: AppColors.muted,
                  fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 30),
            const SizedBox(
              width: 30,
              height: 30,
              child: CircularProgressIndicator(
                  strokeWidth: 3, color: AppColors.blue),
            ),
          ],
        ),
      ),
    );
  }
}
