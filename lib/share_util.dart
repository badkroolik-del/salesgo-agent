import 'dart:convert';
import 'package:share_plus/share_plus.dart';
// Platformaga bog'liq saqlash/ulashish: mobil = vaqtinchalik fayl + Share,
// web = brauzer orqali yuklab olish. dart:io / dart:html shu fayllarda izolyatsiya.
import 'share_io.dart' if (dart.library.html) 'share_web.dart' as platform;

/// CSV yasab ulashish (Excel ochadi). rows — qatorlar ro'yxati.
Future<void> shareCsv(String fileName, List<List<dynamic>> rows,
    {String? subject, String? text}) async {
  final buf = StringBuffer();
  for (final r in rows) {
    buf.writeln(r.map((c) {
      final s = '$c'.replaceAll('"', '""');
      return '"$s"';
    }).join(','));
  }
  // UTF-8 BOM — Excel kirillcha/lotinchani to'g'ri ochishi uchun
  final bytes = utf8.encode('﻿${buf.toString()}');
  await platform.saveShare(fileName, bytes, 'text/csv', subject, text);
}

/// Serverdan olingan fayl baytlarini (masalan .xlsx) saqlab ulashish.
Future<void> shareBytes(String fileName, List<int> bytes,
    {String mime =
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    String? subject,
    String? text}) async {
  await platform.saveShare(fileName, bytes, mime, subject, text);
}

/// Oddiy matnni ulashish.
Future<void> shareText(String textBody, {String? subject}) =>
    Share.share(textBody, subject: subject);
