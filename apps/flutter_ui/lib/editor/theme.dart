import 'package:flutter/material.dart';

const ink = Color(0xFF30323B);
const muted = Color(0xFF686D76);
const paper = Color(0xFFF4F4F1);
const panel = Color(0xFFECEDE9);
const line = Color(0xFFD7D9D3);
const violet = Color(0xFF725895);
const moss = Color(0xFF467460);
const lavender = Color(0xFFEAE4F2);

class EditorColors {
  const EditorColors(this.dark);
  final bool dark;
  Color get ink => dark ? const Color(0xFFE4E4E7) : const Color(0xFF30323B);
  Color get muted => dark ? const Color(0xFFACADB5) : const Color(0xFF686D76);
  Color get paper => dark ? const Color(0xFF252527) : const Color(0xFFF4F4F1);
  Color get panel => dark ? const Color(0xFF1C1C1E) : const Color(0xFFECEDE9);
  Color get line => dark ? const Color(0xFF414145) : const Color(0xFFD7D9D3);
  Color get violet => dark ? const Color(0xFFB49ACF) : const Color(0xFF725895);
  Color get moss => dark ? const Color(0xFF91BBA0) : const Color(0xFF467460);
  Color get lavender =>
      dark ? const Color(0xFF3B3348) : const Color(0xFFEAE4F2);
  Color get canvas => dark ? const Color(0xFF202022) : const Color(0xFFF0F1ED);
  Color get field => dark ? const Color(0xFF303033) : const Color(0xFFFAFAF8);
  static EditorColors of(BuildContext context) =>
      EditorColors(Theme.of(context).brightness == Brightness.dark);
}

ThemeData editorTheme({bool dark = false}) {
  final c = EditorColors(dark);
  final ink = c.ink,
      muted = c.muted,
      paper = c.paper,
      line = c.line,
      violet = c.violet,
      moss = c.moss;
  return ThemeData(
    useMaterial3: true,
    brightness: dark ? Brightness.dark : Brightness.light,
    scaffoldBackgroundColor: paper,
    colorScheme: ColorScheme.fromSeed(
      seedColor: violet,
      brightness: dark ? Brightness.dark : Brightness.light,
      primary: violet,
      secondary: moss,
      surface: paper,
      onSurface: ink,
      error: dark ? Color(0xFFF0A3A3) : Color(0xFFA44242),
    ),
    fontFamily: 'Segoe UI',
    fontFamilyFallback: const ['NotoSansSymbols2'],
    visualDensity: VisualDensity.compact,
    textTheme: TextTheme(
      bodyMedium: TextStyle(fontSize: 13, color: ink),
      bodySmall: TextStyle(fontSize: 11, color: muted),
      titleSmall: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: ink,
      ),
    ),
    dividerTheme: DividerThemeData(color: line, space: 1, thickness: 1),
    iconTheme: IconThemeData(size: 18, color: muted),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: ink,
        borderRadius: BorderRadius.circular(3),
      ),
      textStyle: TextStyle(color: dark ? c.panel : Colors.white, fontSize: 12),
      waitDuration: Duration(milliseconds: 500),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: violet,
        foregroundColor: dark ? Color(0xFF1C1C1E) : Colors.white,
        minimumSize: Size(0, 34),
        padding: EdgeInsets.symmetric(horizontal: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        textStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: ink,
        minimumSize: Size(0, 32),
        side: BorderSide(color: line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        textStyle: TextStyle(fontSize: 12),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: ink,
        minimumSize: Size(0, 32),
        padding: EdgeInsets.symmetric(horizontal: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: c.field,
      contentPadding: EdgeInsets.symmetric(horizontal: 9, vertical: 11),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(3),
        borderSide: BorderSide(color: line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(3),
        borderSide: BorderSide(color: line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(3),
        borderSide: BorderSide(color: violet, width: 1.5),
      ),
      errorMaxLines: 3,
    ),
  );
}
