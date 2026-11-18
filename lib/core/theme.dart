import 'package:material_ui/material_ui.dart';

ThemeData buildTheme(Brightness brightness) {
  return ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: Colors.deepPurple,
      brightness: brightness,
    ),
    cardTheme: CardThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
  );
}

final lightTheme = buildTheme(Brightness.light);
final darkTheme = buildTheme(Brightness.dark);
