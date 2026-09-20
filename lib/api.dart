import 'dart:convert';
import 'package:cross_file/cross_file.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// SalesGO backend bilan aloqa.
class Api {
  static const base = 'https://salesgo.uz';
  static String? token;
  static Map<String, dynamic>? me;

  static Future<void> loadToken() async {
    final p = await SharedPreferences.getInstance();
    token = p.getString('token');
  }

  static Future<void> _saveToken(String t) async {
    token = t;
    final p = await SharedPreferences.getInstance();
    await p.setString('token', t);
  }

  static Future<void> logout() async {
    token = null;
    me = null;
    final p = await SharedPreferences.getInstance();
    await p.remove('token');
  }

  static Map<String, String> get _h => {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  /// Javobni xavfsiz JSON ga o'giradi. Server HTML xato sahifasi
  /// (<!DOCTYPE html>, 404/502 Apache/nginx) qaytarsa — FormatException
  /// o'rniga tushunarli xabar beradi.
  static dynamic _json(http.Response r) {
    final body = utf8.decode(r.bodyBytes);
    final t = body.trimLeft();
    // HTML yoki bo'sh javob -> JSON emas
    if (t.isEmpty) return <String, dynamic>{};
    if (t.startsWith('<')) {
      // Server xato sahifasi qaytardi (proksi/gateway/404)
      throw _statusMsg(r.statusCode);
    }
    try {
      return jsonDecode(t);
    } on FormatException {
      throw _statusMsg(r.statusCode);
    }
  }

  static String _statusMsg(int code) {
    if (code == 502 || code == 503 || code == 504) {
      return 'Server vaqtincha ishlamayapti ($code). Birozdan keyin urinib ko‘ring.';
    }
    if (code == 404) return 'Manzil topilmadi (404)';
    if (code >= 500) return 'Server xatosi ($code)';
    if (code >= 400) return 'So‘rov xato ($code)';
    return 'Serverdan noto‘g‘ri javob keldi';
  }

  static Future<Map<String, dynamic>> login(
      String slug, String login, String pass) async {
    final r = await http.post(Uri.parse('$base/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(
            {'company_slug': slug, 'login': login, 'password': pass}));
    final j = _json(r);
    if (r.statusCode != 200) throw (j['detail'] ?? 'Login xato');
    await _saveToken(j['token']);
    return j;
  }

  static Future<dynamic> get(String path) async {
    final r = await http.get(Uri.parse('$base$path'), headers: _h);
    if (r.statusCode == 401) throw 'auth';
    final j = _json(r);
    if (r.statusCode >= 400) {
      throw (j is Map ? (j['detail'] ?? _statusMsg(r.statusCode)) : _statusMsg(r.statusCode));
    }
    return j;
  }

  static Future<dynamic> post(String path, Map<String, dynamic> body,
      {bool put = false}) async {
    final uri = Uri.parse('$base$path');
    final enc = jsonEncode(body);
    final r = put
        ? await http.put(uri, headers: _h, body: enc)
        : await http.post(uri, headers: _h, body: enc);
    if (r.statusCode == 401) throw 'auth';
    final j = _json(r);
    if (r.statusCode >= 400) {
      throw (j is Map ? (j['detail'] ?? _statusMsg(r.statusCode)) : _statusMsg(r.statusCode));
    }
    return j;
  }

  static Future<dynamic> delete(String path) async {
    final r = await http.delete(Uri.parse('$base$path'), headers: _h);
    if (r.statusCode == 401) throw 'auth';
    final j = _json(r);
    if (r.statusCode >= 400) {
      throw (j is Map ? (j['detail'] ?? _statusMsg(r.statusCode)) : _statusMsg(r.statusCode));
    }
    return j;
  }

  /// Serverdan fayl baytlarini oladi (masalan .xlsx nakladnoy/akt-sverka).
  static Future<List<int>> getBytes(String path) async {
    final r = await http.get(Uri.parse('$base$path'), headers: _h);
    if (r.statusCode == 401) throw 'auth';
    if (r.statusCode >= 400) throw _statusMsg(r.statusCode);
    return r.bodyBytes;
  }

  /// Rasm yuklash -> URL qaytaradi.
  static Future<String> uploadPhoto(XFile file) async {
    final req = http.MultipartRequest('POST', Uri.parse('$base/api/upload'));
    req.headers['Authorization'] = 'Bearer $token';
    final bytes = await file.readAsBytes();
    req.files.add(http.MultipartFile.fromBytes('file', bytes,
        filename: file.name.isNotEmpty ? file.name : 'photo.jpg',
        contentType: MediaType('image', 'jpeg')));
    final resp = await req.send();
    final body = await resp.stream.bytesToString();
    final t = body.trimLeft();
    if (t.isEmpty || t.startsWith('<')) throw _statusMsg(resp.statusCode);
    dynamic j;
    try {
      j = jsonDecode(t);
    } on FormatException {
      throw _statusMsg(resp.statusCode);
    }
    if (resp.statusCode >= 400) throw (j['detail'] ?? 'Yuklash xato');
    return j['url'];
  }
}
