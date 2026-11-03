import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  AppColors._();

  static const background = Color(0xFF070B14);
  static const surface = Color(0xFF111827);
  static const primary = Color(0xFF00E5FF); // cyan
  static const green = Color(0xFF2FE68B); // safe
  static const orange = Color(0xFFFFB84D); // warning
  static const red = Color(0xFFFF4D67); // danger
  static const text = Color(0xFFF8FAFC);
  static const muted = Color(0xFF94A3B8);

  // Aurora accents
  static const blue = Color(0xFF4C7DFF);
  static const violet = Color(0xFF8B7CFF);
  static const lime = Color(0xFFB8F56B);

  static Color white(double opacity) => Color.fromRGBO(255, 255, 255, opacity);
}

class AppGradients {
  AppGradients._();

  /// Signature cyan → blue → violet gradient (shield, gauge, active states).
  static const aurora = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [AppColors.primary, AppColors.blue, AppColors.violet],
  );

  /// Cyan → green gradient (safe / protected highlights).
  static const safe = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [AppColors.primary, AppColors.green],
  );
}

class AppRadius {
  AppRadius._();
  static const double card = 28; // large feature cards
  static const double tile = 22; // compact tiles, rows and quick actions
  static const double pill = 999;
}

/// Shared layout constants so every screen uses the same rhythm.
class AppSpacing {
  AppSpacing._();
  static const double screen = 20; // horizontal screen padding
  static const double gap = 12; // between neighbouring cards
  static const double gapLg = 16;
  static const double touch = 48; // minimum touch target
}

class AppTheme {
  AppTheme._();

  static ThemeData dark() {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        brightness: Brightness.dark,
        surface: AppColors.surface,
      ),
    );
    return base.copyWith(
      scaffoldBackgroundColor: AppColors.background,
      textTheme: GoogleFonts.plusJakartaSansTextTheme(base.textTheme)
          .apply(bodyColor: AppColors.text, displayColor: AppColors.text),
    );
  }

  /// Default text style for the whole app (used by the shell).
  static TextStyle get baseText => GoogleFonts.plusJakartaSans(
    color: AppColors.text,
    fontSize: 15,
    height: 1.4,
  );
}
