import 'package:flutter/material.dart';

/// Palet warna aplikasi. Ganti di Setelan > Tampilan.
class Palette {
  final String name;
  final Color seed;
  const Palette(this.name, this.seed);
}

const palettes = [
  Palette('Daun', Color(0xFF2E8B57)),
  Palette('Embun', Color(0xFF1C7C9C)),
  Palette('Tanah', Color(0xFFB5532A)),
  Palette('Senja', Color(0xFF6B4FBB)),
];

ThemeData buildTheme(Palette p, Brightness b) {
  final cs = ColorScheme.fromSeed(seedColor: p.seed, brightness: b);
  final dark = b == Brightness.dark;
  return ThemeData(
    useMaterial3: true,
    colorScheme: cs,
    // Latar sedikit berwarna + kartu putih (terang) / gelap bertingkat (gelap): kartu terasa "mengambang".
    scaffoldBackgroundColor: dark ? cs.surface : cs.surfaceContainer,
    navigationBarTheme: NavigationBarThemeData(
      height: 68,
      backgroundColor: dark ? cs.surfaceContainerHigh : cs.surfaceContainerLowest,
      indicatorColor: cs.primaryContainer,
      labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
      ),
    ),
  );
}
