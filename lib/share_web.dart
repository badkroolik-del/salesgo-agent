import 'dart:html' as html;
import 'dart:typed_data';

/// Web: baytlarni brauzer orqali yuklab olish (Share yo'q).
Future<void> saveShare(String fileName, List<int> bytes, String mime,
    String? subject, String? text) async {
  final blob = html.Blob([Uint8List.fromList(bytes)], mime);
  final url = html.Url.createObjectUrlFromBlob(blob);
  final a = html.AnchorElement(href: url)
    ..download = fileName
    ..style.display = 'none';
  html.document.body!.append(a);
  a.click();
  a.remove();
  html.Url.revokeObjectUrl(url);
}
