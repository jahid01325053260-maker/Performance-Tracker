import 'package:flutter/material.dart';

class Palette {
  static const primary = Color(0xff1E5A44);
  static const dark = Color(0xff154333);
  static const pale = Color(0xffD5E9DE);
  static const background = Color(0xffF3F4F1);
  static const muted = Color(0xff6E7571);
  static const outline = Color(0xffE3E6E2);
  static const red = Color(0xffD32F2F);
}

ThemeData buildTheme() {
  final colorScheme = ColorScheme.fromSeed(seedColor: Palette.primary, brightness: Brightness.light);
  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: Palette.background,
    appBarTheme: const AppBarTheme(backgroundColor: Colors.white, foregroundColor: Palette.dark, centerTitle: false),
    cardTheme: CardThemeData(color: Colors.white, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Palette.outline))),
    inputDecorationTheme: InputDecorationTheme(
      filled: true, fillColor: const Color(0xffF7FAF8), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15)),
    filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(minimumSize: const Size(0, 48), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)))),
  );
}

class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.child, this.padding = const EdgeInsets.all(16)});
  final Widget child;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) => Card(child: Padding(padding: padding, child: child));
}

class LoadError extends StatelessWidget {
  const LoadError({super.key, required this.message, required this.retry});
  final String message;
  final VoidCallback retry;
  @override
  Widget build(BuildContext context) => Center(child: Padding(padding: const EdgeInsets.all(28), child: Column(mainAxisSize: MainAxisSize.min, children: [
    const Icon(Icons.error_outline, size: 40, color: Palette.red), const SizedBox(height: 12),
    Text(message, textAlign: TextAlign.center), const SizedBox(height: 12), OutlinedButton(onPressed: retry, child: const Text('Retry')),
  ])));
}
