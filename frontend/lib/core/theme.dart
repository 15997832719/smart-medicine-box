import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'design_system.dart';

class ElderTheme {
  ElderTheme._();

  static const Color primaryColor = AppColors.blue;
  static const Color elderAccent = AppColors.coral;
  static const Color successColor = AppColors.mintDeep;
  static const Color warningColor = Color(0xFFF0A34A);
  static const Color errorColor = AppColors.red;
  static const Color infoColor = AppColors.blue;

  static const Color bgColor = Color(0xFFF2FAFF);
  static const Color cardColor = Colors.white;
  static const Color textPrimary = AppColors.ink;
  static const Color textSecondary = AppColors.muted;
  static const Color dividerColor = Color(0x1F73A1CE);

  static const double bodyFontSize = 17.0;
  static const double baseFontSize = 18.0;
  static const double titleFontSize = 24.0;
  static const double headlineFontSize = 30.0;
  static const double buttonHeight = 58.0;
  static const double bigButtonHeight = 66.0;
  static const double iconSize = 27.0;
  static const double largeIconSize = 44.0;
  static const double cardRadius = 24.0;

  static ThemeData get lightTheme {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: primaryColor,
      brightness: Brightness.light,
      primary: primaryColor,
      secondary: const Color(0xFF51CDB5),
      surface: Colors.white,
      error: errorColor,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: Colors.transparent,
      canvasColor: Colors.transparent,
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        toolbarHeight: 64,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
        ),
        titleTextStyle: TextStyle(
          fontSize: titleFontSize,
          fontWeight: FontWeight.w800,
          color: textPrimary,
          letterSpacing: -0.2,
        ),
        iconTheme: IconThemeData(color: textPrimary, size: 26),
      ),
      textTheme: const TextTheme(
        displayLarge: TextStyle(
          fontSize: 38,
          fontWeight: FontWeight.w900,
          color: textPrimary,
          height: 1.12,
        ),
        displayMedium: TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.w900,
          color: textPrimary,
          height: 1.16,
        ),
        displaySmall: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w800,
          color: textPrimary,
          height: 1.2,
        ),
        headlineLarge: TextStyle(
          fontSize: 30,
          fontWeight: FontWeight.w900,
          color: textPrimary,
          height: 1.2,
        ),
        headlineMedium: TextStyle(
          fontSize: titleFontSize,
          fontWeight: FontWeight.w800,
          color: textPrimary,
          height: 1.25,
        ),
        headlineSmall: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w800,
          color: textPrimary,
          height: 1.28,
        ),
        titleLarge: TextStyle(
          fontSize: 21,
          fontWeight: FontWeight.w800,
          color: textPrimary,
          height: 1.3,
        ),
        titleMedium: TextStyle(
          fontSize: 19,
          fontWeight: FontWeight.w700,
          color: textPrimary,
          height: 1.35,
        ),
        bodyLarge:
            TextStyle(fontSize: baseFontSize, color: textPrimary, height: 1.5),
        bodyMedium: TextStyle(
            fontSize: bodyFontSize, color: textSecondary, height: 1.5),
        bodySmall: TextStyle(fontSize: 16, color: textSecondary, height: 1.45),
        labelLarge: TextStyle(
            fontSize: 20, fontWeight: FontWeight.w800, color: textPrimary),
        labelMedium: TextStyle(
            fontSize: 16, fontWeight: FontWeight.w700, color: textSecondary),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(double.infinity, buttonHeight),
          elevation: 0,
          shadowColor: Colors.transparent,
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          textStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(double.infinity, buttonHeight),
          elevation: 0,
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          textStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(double.infinity, buttonHeight),
          foregroundColor: const Color(0xFF2869B3),
          backgroundColor: Colors.white.withValues(alpha: 0.62),
          textStyle: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
          side: const BorderSide(color: Color(0x6684B7E4), width: 1.2),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(19)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: const Color(0xFF2676CE),
          textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      cardTheme: CardThemeData(
        color: Colors.white.withValues(alpha: 0.86),
        surfaceTintColor: Colors.transparent,
        shadowColor: const Color(0x24215E96),
        elevation: 2,
        margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cardRadius),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.92)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.86),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        prefixIconColor: const Color(0xFF3E6589),
        suffixIconColor: const Color(0xFF6885A0),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: const BorderSide(color: Color(0x99FFFFFF), width: 1.1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: const BorderSide(color: Color(0x99FFFFFF), width: 1.1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: const BorderSide(color: Color(0xFF84C9FF), width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: const BorderSide(color: errorColor, width: 1.4),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: const BorderSide(color: errorColor, width: 1.8),
        ),
        labelStyle: const TextStyle(
          fontSize: 18,
          color: textSecondary,
          fontWeight: FontWeight.w600,
        ),
        hintStyle: const TextStyle(
          fontSize: 19,
          color: Color(0xFF8297A9),
          fontWeight: FontWeight.w500,
        ),
        counterStyle: const TextStyle(fontSize: 14, color: textSecondary),
      ),
      iconTheme: const IconThemeData(size: iconSize, color: textPrimary),
      dividerTheme:
          const DividerThemeData(color: dividerColor, thickness: 1, space: 1),
      chipTheme: ChipThemeData(
        backgroundColor: Colors.white.withValues(alpha: 0.68),
        selectedColor: AppColors.blueTint,
        side: BorderSide(color: Colors.white.withValues(alpha: 0.9)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        labelStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: AppColors.muted,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white.withValues(alpha: 0.9),
        surfaceTintColor: Colors.transparent,
        indicatorColor: AppColors.blueTint,
        elevation: 0,
        height: 76,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: selected ? const Color(0xFF176AC5) : const Color(0xFF788EA5),
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 28,
            color: selected ? const Color(0xFF176AC5) : const Color(0xFF788EA5),
          );
        }),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white.withValues(alpha: 0.96),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        titleTextStyle: const TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w800,
          color: textPrimary,
        ),
        contentTextStyle:
            const TextStyle(fontSize: 19, height: 1.5, color: textPrimary),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Color(0xFFF7FCFF),
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: Color(0xFFF7FCFF),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
        showDragHandle: true,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.ink,
        contentTextStyle: const TextStyle(fontSize: 18, color: Colors.white),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        insetPadding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
      ),
    );
  }
}

class ElderPageRoute<T> extends PageRouteBuilder<T> {
  final Widget page;

  ElderPageRoute({required this.page})
      : super(
          pageBuilder: (context, animation, secondaryAnimation) => page,
          transitionDuration: const Duration(milliseconds: 260),
          reverseTransitionDuration: const Duration(milliseconds: 220),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final curved =
                CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
            return FadeTransition(
              opacity: curved,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0.035, 0),
                  end: Offset.zero,
                ).animate(curved),
                child: child,
              ),
            );
          },
        );
}
