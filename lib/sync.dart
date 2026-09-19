import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'api.dart';

/// Offline navbat: internet yo'q bo'lsa zakaz/rasmlar shu yerda saqlanadi,
/// "Sinxron" tugmasi bosilganda serverga yuboriladi.
class SyncStore {
  static const _kOrders = 'q_orders';
  static const _kPhotos = 'q_photos';

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

  static Future<int> pendingOrders() async {
    final sp = await SharedPreferences.getInstance();
    return (sp.getStringList(_kOrders) ?? []).length;
  }

  static Future<int> pendingPhotos() async {
    final sp = await SharedPreferences.getInstance();
    return (sp.getStringList(_kPhotos) ?? []).length;
  }

  static Future<int> pendingTotal() async =>
      (await pendingOrders()) + (await pendingPhotos());

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

  /// Navbatni serverga yuboradi.
  /// onProgress(done, total, yuborilganZakaz, yuborilganRasm) chaqiriladi.
  /// Natija: {'orders': n, 'photos': m, 'left': k}.
  static Future<Map<String, int>> flush(
      void Function(int done, int total, int orders, int photos)?
          onProgress) async {
    final sp = await SharedPreferences.getInstance();
    final orders = List<String>.from(sp.getStringList(_kOrders) ?? []);
    final photos = List<String>.from(sp.getStringList(_kPhotos) ?? []);
    final total = orders.length + photos.length;
    int done = 0, sentO = 0, sentP = 0;

    final remainO = <String>[];
    for (final s in orders) {
      try {
        await Api.post('/api/orders', Map<String, dynamic>.from(jsonDecode(s)));
        sentO++;
      } catch (_) {
        remainO.add(s);
      }
      done++;
      onProgress?.call(done, total, sentO, sentP);
    }
    await sp.setStringList(_kOrders, remainO);

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
      'left': remainO.length + remainP.length,
    };
  }
}
