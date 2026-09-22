import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:huiyao_app/core/auth_service.dart';
import 'package:huiyao_app/main.dart';

void main() {
  testWidgets('智能药箱应用可以启动登录页', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AuthService(),
        child: const SmartMedicineApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('智能药箱'), findsOneWidget);
    expect(find.text('登录'), findsOneWidget);
  });
}