import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'api.dart';

/// Offline navbat: internet yo'q bo'lsa zakaz/rasmlar shu yerda saqlanadi,
/// "Sinxron" tugmasi bosilganda serverga yuboriladi.
class SyncStore {
  static const _kOrders = 'q_orders';
  static const _kPhotos = 'q_photos';
  static const _kVisits = 'q_visits';

  static Future<void> _add(String key, Map<String, dynamic> data) async {
    final sp = await SharedPreferences.getInstance();
    final list = sp.getStringList(key) ?? [];
    list.add(jsonEncode(data));
    await sp.setStringList(key, list);
  }

  static Future<void> queueOrder(Map<String, dynamic> body) =>
      _add(_kOrders, body);
  static Future<void> queuePhoto(Map<String, dynamic> meta) =>
      _add(_kPhotos, meta);
  static Future<void> queueVisit(Map<String, dynamic> body) =>
      _add(_kVisits, body);

  static Future<int> pendingOrders() async {
    final sp = await SharedPreferences.getInstance();
    return (sp.getStringList(_kOrders) ?? []).length;
  }

  static Future<int> pendingPhotos() async {
    final sp = await SharedPreferences.getInstance();
    return (sp.getStringList(_kPhotos) ?? []).length;
  }

  static Future<int> pendingVisits() async {
    final sp = await SharedPreferences.getInstance();
    return (sp.getStringList(_kVisits) ?? []).length;
  }

  static Future<int> pendingTotal() async =>
      (await pendingOrders()) + (await pendingPhotos()) + (await pendingVisits());

  /// Vizit checkin: onlayn bo'lsa yuboradi (server id qaytaradi),
  /// aks holda navbatga qo'yadi. null = oflayn navbatga tushdi.
  static Future<int?> sendOrQueueVisit(Map<String, dynamic> body) async {
    try {
      final d = await Api.post('/api/visits/checkin', body);
      return d['id'] as int?;
    } catch (_) {
      await queueVisit(body);
      return null;
    }
  }

  /// Navbatdagi (yuborilmagan) zakazlar ro'yxati — tahrir/ko'rish uchun.
  static Future<List<Map<String, dynamic>>> listOrders() async {
    final sp = await SharedPreferences.getInstance();
    final out = <Map<String, dynamic>>[];
    for (final s in sp.getStringList(_kOrders) ?? []) {
      try {
        out.add(Map<String, dynamic>.from(jsonDecode(s)));
      } catch (_) {}
    }
    return out;
  }

  /// client_uuid bo'yicha navbatdan o'chiradi.
  static Future<void> removeOrder(String clientUuid) async {
    final sp = await SharedPreferences.getInstance();
    final list = sp.getStringList(_kOrders) ?? [];
    list.removeWhere((s) {
      try {
        return '${jsonDecode(s)['client_uuid']}' == clientUuid;
      } catch (_) {
        return false;
      }
    });
    await sp.setStringList(_kOrders, list);
  }

  /// client_uuid bo'yicha navbatdagi zakazni yangilaydi (to'lov turi, izoh...).
  static Future<void> updateOrder(
      String clientUuid, Map<String, dynamic> body) async {
    final sp = await SharedPreferences.getInstance();
    final list = sp.getStringList(_kOrders) ?? [];
    for (int i = 0; i < list.length; i++) {
      try {
        if ('${jsonDecode(list[i])['client_uuid']}' == clientUuid) {
          list[i] = jsonEncode(body);
          break;
        }
      } catch (_) {}
    }
    await sp.setStringList(_kOrders, list);
  }

  /// Zakazni yuborishga urinadi. Muvaffaqiyatli bo'lmasa navbatga qo'yadi.
  /// true = darhol yuborildi, false = navbatga tushdi.
  static Future<bool> sendOrQueueOrder(Map<String, dynamic> body) async {
    try {
      await Api.post('/api/orders', body);
      return true;
    } catch (_) {
      await queueOrder(body);
      return false;
    }
  }

  /// Rasmni yuborishga urinadi. Bo'lmasa navbatga (fayl yo'li bilan) qo'yadi.
  static Future<bool> sendOrQueuePhoto(
      {required int? visitId, required String path, String type = 'shelf'}) async {
    try {
      final url = await Api.uploadPhoto(File(path));
      await Api.post('/api/photos',
          {'visit_id': visitId, 'type': type, 'file_path': url});
      return true;
    } catch (_) {
      await queuePhoto({'visit_id': visitId, 'path': path, 'type': type});
      return false;
    }
  }

  /// Navbatni serverga yuboradi (avval vizit, keyin zakaz, keyin rasm).
  /// onProgress(done, total, yuborilganZakaz, yuborilganRasm) chaqiriladi.
  /// Natija: {'orders','photos','visits','left', 'warnings': [String]}.
  /// warnings = tovar qoldig'i yetmagan zakazlar haqida ogohlantirish.
  static Future<Map<String, dynamic>> flush(
      void Function(int done, int total, int orders, int photos)?
          onProgress) async {
    final sp = await SharedPreferences.getInstance();
    final visits = List<String>.from(sp.getStringList(_kVisits) ?? []);
    final orders = List<String>.from(sp.getStringList(_kOrders) ?? []);
    final photos = List<String>.from(sp.getStringList(_kPhotos) ?? []);
    final total = visits.length + orders.length + photos.length;
    int done = 0, sentO = 0, sentP = 0, sentV = 0;
    final warnings = <String>[];

    // 1) Vizitlar (avval — zakazlar shu do'konga tegishli)
    final remainV = <String>[];
    for (final s in visits) {
      try {
        await Api.post('/api/visits/checkin',
            Map<String, dynamic>.from(jsonDecode(s)));
        sentV++;
      } catch (_) {
        remainV.add(s);
      }
      done++;
      onProgress?.call(done, total, sentO, sentP);
    }
    await sp.setStringList(_kVisits, remainV);

    // 2) Zakazlar — javobda tovar qoldiq ogohlantirishi bo'lsa yig'amiz
    final remainO = <String>[];
    for (final s in orders) {
      try {
        final body = Map<String, dynamic>.from(jsonDecode(s));
        final resp = await Api.post('/api/orders', body);
        if (resp is Map && resp['warnings'] is List) {
          final cn = body['client_name'] ?? '';
          for (final w in resp['warnings']) {
            warnings.add(cn.toString().isEmpty ? '$w' : '$cn: $w');
          }
        }
        sentO++;
      } catch (_) {
        remainO.add(s);
      }
      done++;
      onProgress?.call(done, total, sentO, sentP);
    }
    await sp.setStringList(_kOrders, remainO);

    // 3) Rasmlar
    final remainP = <String>[];
    for (final s in photos) {
      try {
        final m = Map<String, dynamic>.from(jsonDecode(s));
        final path = '${m['path']}';
        String? url = m['url'];
        if (url == null && path.isNotEmpty && File(path).existsSync()) {
          url = await Api.uploadPhoto(File(path));
        }
        await Api.post('/api/photos', {
          'visit_id': m['visit_id'],
          'type': m['type'] ?? 'shelf',
          'file_path': url,
        });
        sentP++;
      } catch (_) {
        remainP.add(s);
      }
      done++;
      onProgress?.call(done, total, sentO, sentP);
    }
    await sp.setStringList(_kPhotos, remainP);

    return {
      'orders': sentO,
      'photos': sentP,
      'visits': sentV,
      'left': remainV.length + remainO.length + remainP.length,
      'warnings': warnings,
    };
  }
}
