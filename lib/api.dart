import 'dart:convert';
import 'dart:io';
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

  static Future<Map<String, dynamic>> login(
      String slug, String login, String pass) async {
    final r = await http.post(Uri.parse('$base/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(
            {'company_slug': slug, 'login': login, 'password': pass}));
    final j = jsonDecode(utf8.decode(r.bodyBytes));
    if (r.statusCode != 200) throw (j['detail'] ?? 'Login xato');
    await _saveToken(j['token']);
    return j;
  }

  static Future<dynamic> get(String path) async {
    final r = await http.get(Uri.parse('$base$path'), headers: _h);
    if (r.statusCode == 401) throw 'auth';
    return jsonDecode(utf8.decode(r.bodyBytes));
  }

  static Future<dynamic> post(String path, Map<String, dynamic> body) async {
    final r = await http.post(Uri.parse('$base$path'),
        headers: _h, body: jsonEncode(body));
    final j = r.body.isNotEmpty ? jsonDecode(utf8.decode(r.bodyBytes)) : {};
    if (r.statusCode == 401) throw 'auth';
    if (r.statusCode >= 400) throw (j['detail'] ?? 'Xato');
    return j;
  }

  /// Rasm yuklash -> URL qaytaradi.
  static Future<String> uploadPhoto(File file) async {
    final req = http.MultipartRequest('POST', Uri.parse('$base/api/upload'));
    req.headers['Authorization'] = 'Bearer $token';
    req.files.add(await http.MultipartFile.fromPath('file', file.path,
        contentType: MediaType('image', 'jpeg')));
    final resp = await req.send();
    final body = await resp.stream.bytesToString();
    final j = jsonDecode(body);
    if (resp.statusCode >= 400) throw (j['detail'] ?? 'Yuklash xato');
    return j['url'];
  }
}
