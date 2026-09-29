import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'api.dart';

/// Paneldagi «Настройки → Мобильное приложение» konfiguratsiyasi (rol + xodim).
/// Server: GET /api/mobile/config/me → {config:{...}} (yoki to'g'ridan-to'g'ri {...}).
/// Server hali bermasa — ilova yumshoq standartlar bilan ishlaydi (majburiyatlar o'chiq, trek yoqilgan).
class MobileCfg {
  static const _k = 'mobile_cfg';
  static Map<String, dynamic> v = {};

  static Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final s = p.getString(_k);
      if (s != null) v = Map<String, dynamic>.from(jsonDecode(s));
    } catch (_) {}
  }

  /// Serverdan yangilaydi; o'zgargan bo'lsa true.
  static Future<bool> refresh() async {
    try {
      final j = await Api.get('/api/mobile/config/me');
      if (j is Map) {
        final m = Map<String, dynamic>.from(j['config'] is Map ? j['config'] : j);
        final changed = jsonEncode(m) != jsonEncode(v);
        v = m;
        final p = await SharedPreferences.getInstance();
        await p.setString(_k, jsonEncode(v));
        return changed;
      }
    } catch (_) {}
    return false;
  }

  static bool b(String k, [bool d = false]) => v[k] is bool ? v[k] as bool : d;
  static num n(String k, [num d = 0]) =>
      v[k] is num ? v[k] as num : (num.tryParse('${v[k]}') ?? d);
  static String s(String k, [String d = '']) => v[k] == null ? d : '${v[k]}';
  static List l(String k, [List d = const []]) => v[k] is List ? v[k] as List : d;

  // ---- qulay nomlar (rol bo'yicha) ----
  static bool get radiusReq => b('radius_req');
  static num get radius => n('radius', 150);
  static int get minVisitMin => n('min_visit', 0).toInt();
  static bool get photoBeforeOrder => b('photo_order');
  static bool get refusalReasonReq => b('refusal_reason');
  static bool get blockOrderNoGps => b('block_order_nogps');
  static int get photoMin => n('photo_min', 0).toInt();
  static String get workFrom => s('work_from', '07:00');
  static String get workTo => s('work_to', '21:00');
}
