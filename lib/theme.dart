import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ============ SalesGO brend palitrasi (logo: navy ❯ + yashil ▶) ============
const brandNavy = Color(0xFF02255B); // logo «Sales» / chevron
const brandGreen = Color(0xFF21A94D); // logo «GO» / uchburchak
const brand = Color(0xFF0B3A74); // asosiy (tugma, tanlov)
const brand2 = Color(0xFF1D4A8F); // gradient ikkinchi rang
const brandDark = brandNavy;
const accent = brandGreen; // eski «GO» urg'usi o'rniga — brend yashil
const accent2 = Color(0xFF15803D);
const bg = Color(0xFFF1F5F9);
const ink = Color(0xFF0F172A);
const muted = Color(0xFF4E6470);
const line = Color(0xFFE2E8F0);
const danger = Color(0xFFDC2626);
const ok = Color(0xFF15803D);
const warn = Color(0xFFF59E0B);
const info = Color(0xFF1D4A8F);
const violet = Color(0xFF6D28D9);

const brandGradient = LinearGradient(
  colors: [brandNavy, brand2],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);
const goGradient = LinearGradient(
  colors: [brandGreen, accent2],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);
// Pastki menyu: navy gorizontal gradient
const navGradient = LinearGradient(
  colors: [brandNavy, brand2],
  begin: Alignment.centerLeft,
  end: Alignment.centerRight,
);

// ============ Til (UZ / RU) ============
final langVN = ValueNotifier<String>('uz');
String get lang => langVN.value;
String tr(String uz, String ru) => langVN.value == 'ru' ? ru : uz;

Future<void> loadLang() async {
  try {
    final p = await SharedPreferences.getInstance();
    langVN.value = p.getString('lang') ?? 'uz';
  } catch (_) {}
}

Future<void> setLang(String l) async {
  langVN.value = l;
  try {
    final p = await SharedPreferences.getInstance();
    await p.setString('lang', l);
  } catch (_) {}
}

const _wdUz = ['', 'Dushanba', 'Seshanba', 'Chorshanba', 'Payshanba', 'Juma', 'Shanba', 'Yakshanba'];
const _wdRu = ['', 'Понедельник', 'Вторник', 'Среда', 'Четверг', 'Пятница', 'Суббота', 'Воскресенье'];
const wdShortUz = ['', 'Du', 'Se', 'Ch', 'Pa', 'Ju', 'Sh', 'Ya'];
const wdShortRu = ['', 'Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];

String weekdayName(int wd) =>
    (lang == 'ru' ? _wdRu : _wdUz)[(wd >= 1 && wd <= 7) ? wd : 0];
String weekdayShort(int wd) =>
    (lang == 'ru' ? wdShortRu : wdShortUz)[(wd >= 1 && wd <= 7) ? wd : 0];
int todayWeekday() => DateTime.now().weekday; // 1=Mon..7=Sun

num asNum(dynamic x) => x is num ? x : (num.tryParse('$x') ?? 0);

String money(num n) {
  final s = n
      .round()
      .toString()
      .replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]} ');
  return '$s ${tr('so\'m', 'сум')}';
}

String shortMoney(num n) {
  final a = n.abs();
  if (a >= 1000000000) return '${(n / 1000000000).toStringAsFixed(1)} mlrd';
  if (a >= 1000000) return '${(n / 1000000).toStringAsFixed(1)} mln';
  if (a >= 1000) return '${(n / 1000).toStringAsFixed(0)} ${tr('ming', 'тыс')}';
  return n.round().toString();
}

String greeting() {
  final h = DateTime.now().hour;
  if (h < 6) return tr('Xayrli tun', 'Доброй ночи');
  if (h < 12) return tr('Xayrli tong', 'Доброе утро');
  if (h < 18) return tr('Xayrli kun', 'Добрый день');
  return tr('Xayrli kech', 'Добрый вечер');
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
