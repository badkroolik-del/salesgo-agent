import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

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
  final dir = await getTemporaryDirectory();
  final f = File('${dir.path}/$fileName');
  // UTF-8 BOM — Excel kirillcha/lotinchani to'g'ri ochishi uchun
  await f.writeAsString('﻿${buf.toString()}');
  await Share.shareXFiles([XFile(f.path, mimeType: 'text/csv')],
      subject: subject, text: text);
}

/// Oddiy matnni ulashish.
Future<void> shareText(String textBody, {String? subject}) =>
    Share.share(textBody, subject: subject);
