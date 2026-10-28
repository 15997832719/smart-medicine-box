import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:huiyao_app/core/auth_service.dart';
import 'package:huiyao_app/main.dart';

void main() {
  testWidgets('智能药箱应用可以启动隐私授权页', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AuthService(),
        child: const SmartMedicineApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('隐私保护与授权'), findsOneWidget);
    expect(find.text('同意并继续'), findsOneWidget);
  });
}
