import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';

/// Palette Reem, tirée du logo : violet profond + orange vif, sur un fond nuit légèrement violacé.
class ReemColors {
  ReemColors._();

  static const Color background = Color(0xFF0B0714);
  static const Color sidebar = Color(0xFF0F0A1C);
  static const Color surface = Color(0xFF161026);
  static const Color surfaceHigh = Color(0xFF221838);

  static const Color primary = Color(0xFF8F55FF); // violet du logo
  static const Color accent = Color(0xFFFF8A2B); // orange du logo
  static const Color like = Color(0xFFFF3B5C);
  static const Color gold = Color(0xFFFFC83D);
  static const Color violetDeep = Color(0xFF2A1166); // indigo profond du « R »

  static const Color textSecondary = Color(0xB3FFFFFF);
  static const Color textMuted = Color(0x80FFFFFF);
  static const Color border = Color(0x14FFFFFF);

  static const LinearGradient gradient = LinearGradient(
    colors: [primary, accent],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}


/// Couleurs qui changent selon le mode clair / sombre.
/// À utiliser dans les écrans : `context.reem.text`, `context.reem.surface`...
/// (les couleurs de marque, comme `ReemColors.primary`, ne changent pas).
@immutable
class ReemPalette extends ThemeExtension<ReemPalette> {
  const ReemPalette({
    required this.background,
    required this.sidebar,
    required this.surface,
    required this.surfaceHigh,
    required this.text,
    required this.textSecondary,
    required this.textMuted,
    required this.border,
  });

  final Color background;
  final Color sidebar;
  final Color surface;
  final Color surfaceHigh;
  final Color text;
  final Color textSecondary;
  final Color textMuted;
  final Color border;

  static const ReemPalette dark = ReemPalette(
    background: Color(0xFF0B0714),
    sidebar: Color(0xFF0F0A1C),
    surface: Color(0xFF161026),
    surfaceHigh: Color(0xFF221838),
    text: Colors.white,
    textSecondary: Color(0xB3FFFFFF),
    textMuted: Color(0x80FFFFFF),
    border: Color(0x14FFFFFF),
  );

  static const ReemPalette light = ReemPalette(
    background: Color(0xFFF6F2FD),
    sidebar: Color(0xFFFFFFFF),
    surface: Color(0xFFFFFFFF),
    surfaceHigh: Color(0xFFECE4FA),
    text: Color(0xFF150F26),
    textSecondary: Color(0xFF50466B),
    textMuted: Color(0xFF82789C),
    border: Color(0x1F150F26),
  );

  @override
  ReemPalette copyWith({
    Color? background,
    Color? sidebar,
    Color? surface,
    Color? surfaceHigh,
    Color? text,
    Color? textSecondary,
    Color? textMuted,
    Color? border,
  }) {
    return ReemPalette(
      background: background ?? this.background,
      sidebar: sidebar ?? this.sidebar,
      surface: surface ?? this.surface,
      surfaceHigh: surfaceHigh ?? this.surfaceHigh,
      text: text ?? this.text,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      border: border ?? this.border,
    );
  }

  @override
  ReemPalette lerp(ThemeExtension<ReemPalette>? other, double t) {
    if (other is! ReemPalette) return this;
    return ReemPalette(
      background: Color.lerp(background, other.background, t)!,
      sidebar: Color.lerp(sidebar, other.sidebar, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceHigh: Color.lerp(surfaceHigh, other.surfaceHigh, t)!,
      text: Color.lerp(text, other.text, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      border: Color.lerp(border, other.border, t)!,
    );
  }
}

extension ReemContext on BuildContext {
  /// Palette du mode actuel (clair ou sombre).
  ReemPalette get reem => Theme.of(this).extension<ReemPalette>() ?? ReemPalette.dark;

  bool get isDarkMode => Theme.of(this).brightness == Brightness.dark;
}

/// Ombre douce pour les textes posés sur une vidéo.
const List<Shadow> reemTextShadow = [
  Shadow(color: Color(0x99000000), blurRadius: 6, offset: Offset(0, 1)),
];

/// Permet aussi de faire défiler / glisser à la souris (ordinateur).
class ReemScrollBehavior extends MaterialScrollBehavior {
  const ReemScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.stylus,
        PointerDeviceKind.trackpad,
      };
}

class ReemTheme {
  ReemTheme._();

  static ThemeData dark() => _build(Brightness.dark, ReemPalette.dark);

  static ThemeData light() => _build(Brightness.light, ReemPalette.light);

  static ThemeData _build(Brightness brightness, ReemPalette palette) {
    final isDark = brightness == Brightness.dark;

    final scheme = ColorScheme.fromSeed(
      seedColor: ReemColors.primary,
      brightness: brightness,
    ).copyWith(
      primary: isDark ? ReemColors.primary : const Color(0xFF6A2FE0),
      secondary: ReemColors.accent,
      surface: palette.surface,
      onSurface: palette.text,
      error: ReemColors.like,
    );

    final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide.none,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      extensions: [palette],
      scaffoldBackgroundColor: palette.background,
      canvasColor: palette.background,
      splashFactory: InkSparkle.splashFactory,
      textTheme: ThemeData(brightness: brightness).textTheme.apply(
            bodyColor: palette.text,
            displayColor: palette.text,
          ),
      iconTheme: IconThemeData(color: palette.text),
      listTileTheme: ListTileThemeData(
        iconColor: palette.text,
        textColor: palette.text,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: palette.surfaceHigh,
        textStyle: TextStyle(color: palette.text),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: palette.text,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: palette.text),
        titleTextStyle: TextStyle(
          color: palette.text,
          fontSize: 17,
          fontWeight: FontWeight.w700,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: palette.surfaceHigh,
          disabledForegroundColor: palette.textMuted,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: palette.text,
          side: BorderSide(color: palette.border, width: 1.2),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? palette.surface : palette.surfaceHigh,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        hintStyle: TextStyle(color: palette.textMuted),
        prefixIconColor: palette.textMuted,
        suffixIconColor: palette.textMuted,
        border: inputBorder,
        enabledBorder: inputBorder,
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.primary, width: 1.4),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? Colors.white : palette.textMuted,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? scheme.primary : palette.surfaceHigh,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark ? palette.surfaceHigh : const Color(0xFF241A3D),
        contentTextStyle: const TextStyle(color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: palette.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: palette.border,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: palette.surface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(color: palette.text, fontSize: 19, fontWeight: FontWeight.w800),
        contentTextStyle: TextStyle(color: palette.textSecondary, fontSize: 14.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      ),
      dividerTheme: DividerThemeData(color: palette.border, space: 1),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: scheme.primary),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: ZoomPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: ZoomPageTransitionsBuilder(),
          TargetPlatform.linux: ZoomPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }
}
