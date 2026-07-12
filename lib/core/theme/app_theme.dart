import 'package:flutter/material.dart';

class AppTheme {
  static ThemeData get light {
    final base = ThemeData.light(useMaterial3: true);
    return base.copyWith(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0B7A75)),
      scaffoldBackgroundColor: const Color(0xFFF7F7F2),
      appBarTheme: const AppBarTheme(backgroundColor: Colors.transparent),
    );
  }
}
