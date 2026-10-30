import 'package:flutter/material.dart';

abstract final class DriveFlowTheme {
  static const background = Color(0xFF0A0D12);
  static const panel = Color(0xFF111720);
  static const panelRaised = Color(0xFF171F2A);
  static const line = Color(0xFF26303C);
  static const muted = Color(0xFF8C98A8);
  static const accent = Color(0xFF71E0BE);
  static const blue = Color(0xFF8AB4FF);

  static ThemeData get dark => ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: background,
        colorScheme: const ColorScheme.dark(
          primary: accent,
          secondary: blue,
          surface: panel,
          error: Color(0xFFFF7385),
        ),
        useMaterial3: true,
        fontFamily: 'Arial',
        textTheme: const TextTheme(
          headlineLarge: TextStyle(fontSize: 32, fontWeight: FontWeight.w700, letterSpacing: -1.1),
          headlineMedium: TextStyle(fontSize: 24, fontWeight: FontWeight.w600, letterSpacing: -.5),
          titleLarge: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          bodyMedium: TextStyle(fontSize: 13, color: muted, height: 1.45),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: panelRaised,
          hintStyle: const TextStyle(color: muted),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: line)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: accent)),
        ),
      );
}
