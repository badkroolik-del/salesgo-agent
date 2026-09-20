import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Mobil/desktop: baytlarni vaqtinchalik faylga yozib, Share orqali ulashadi.
Future<void> saveShare(String fileName, List<int> bytes, String mime,
    String? subject, String? text) async {
  final dir = await getTemporaryDirectory();
  final f = File('${dir.path}/$fileName');
  await f.writeAsBytes(bytes, flush: true);
  await Share.shareXFiles([XFile(f.path, mimeType: mime)],
      subject: subject, text: text);
}
