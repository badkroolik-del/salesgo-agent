import 'package:flutter/material.dart';

// ============ SalesGO brend palitrasi ============
const brand = Color(0xFF10B981); // emerald
const brand2 = Color(0xFF06B6D4); // cyan
const brandDark = Color(0xFF0F766E);
const accent = Color(0xFFF97316); // orange (GO)
const accent2 = Color(0xFFEF4444); // red (GO)
const bg = Color(0xFFF1F5F9);
const ink = Color(0xFF0F172A);
const muted = Color(0xFF64748B);
const line = Color(0xFFE2E8F0);
const danger = Color(0xFFEF4444);
const ok = Color(0xFF22C55E);
const warn = Color(0xFFF59E0B);
const info = Color(0xFF3B82F6);
const violet = Color(0xFF8B5CF6);

const brandGradient = LinearGradient(
  colors: [brand, brand2],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);
const goGradient = LinearGradient(
  colors: [accent, accent2],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

num asNum(dynamic x) => x is num ? x : (num.tryParse('$x') ?? 0);

String money(num n) {
  final s = n
      .round()
      .toString()
      .replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]} ');
  return '$s so\'m';
}

String shortMoney(num n) {
  final a = n.abs();
  if (a >= 1000000000) return '${(n / 1000000000).toStringAsFixed(1)} mlrd';
  if (a >= 1000000) return '${(n / 1000000).toStringAsFixed(1)} mln';
  if (a >= 1000) return '${(n / 1000).toStringAsFixed(0)} ming';
  return n.round().toString();
}

String greeting() {
  final h = DateTime.now().hour;
  if (h < 6) return 'Xayrli tun';
  if (h < 12) return 'Xayrli tong';
  if (h < 18) return 'Xayrli kun';
  return 'Xayrli kech';
}

ThemeData buildTheme() {
  return ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: brand, primary: brand),
    scaffoldBackgroundColor: bg,
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: brand,
        foregroundColor: Colors.white,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: brand, width: 1.6),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      indicatorColor: brand.withOpacity(0.14),
      labelTextStyle: WidgetStateProperty.all(
        const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
    ),
  );
}
