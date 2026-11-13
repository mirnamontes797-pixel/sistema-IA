import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Cliente de la API de Planeación Académica (producción en Vercel).
class Api {
  static const String baseUrl = 'https://sistema-ia-topaz.vercel.app';
  static const String _tokenKey = 'token';
  static const String _userKey = 'user';

  static String? _token;
  static Map<String, dynamic>? _user;

  static String? get token => _token;
  static Map<String, dynamic>? get user => _user;

  static Future<void> loadSession() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString(_tokenKey);
    final raw = prefs.getString(_userKey);
    if (raw != null) {
      try {
        _user = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      } catch (_) {}
    }
  }

  static Future<void> setSession(String token, Map<String, dynamic> user) async {
    _token = token;
    _user = user;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
    await prefs.setString(_userKey, jsonEncode(user));
  }

  static Future<void> clearSession() async {
    _token = null;
    _user = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userKey);
  }

  /// Lanza [ApiException] con el mensaje del servidor cuando la respuesta no es 2xx.
  static Future<dynamic> request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
    bool auth = true,
  }) async {
    final uri = Uri.parse('$baseUrl$path').replace(queryParameters: query);
    final headers = <String, String>{};
    if (body != null) headers['Content-Type'] = 'application/json';
    if (auth && _token != null) headers['Authorization'] = 'Bearer $_token';

    http.Response res;
    try {
      switch (method) {
        case 'POST':
          res = await http.post(uri, headers: headers, body: body == null ? null : jsonEncode(body));
        case 'PATCH':
          res = await http.patch(uri, headers: headers, body: body == null ? null : jsonEncode(body));
        case 'DELETE':
          res = await http.delete(uri, headers: headers);
        default:
          res = await http.get(uri, headers: headers);
      }
    } catch (_) {
      throw const ApiException('Sin conexión. Verifica tu red e inténtalo de nuevo.');
    }

    final data = res.body.isEmpty
        ? <String, dynamic>{}
        : (jsonDecode(utf8.decode(res.bodyBytes)) as dynamic);
    if (res.statusCode == 401 && auth) {
      await clearSession();
      throw const ApiException('Sesión expirada. Inicia sesión de nuevo.');
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      final msg = data is Map ? (data['error'] ?? 'Error ${res.statusCode}') : 'Error ${res.statusCode}';
      throw ApiException(msg.toString());
    }
    return data;
  }

  static Future<List<dynamic>> list(String path, {Map<String, String>? query}) async {
    final res = await request('GET', path, query: query);
    if (res is Map && res['data'] is List) return res['data'] as List<dynamic>;
    return const [];
  }
}

class ApiException implements Exception {
  final String message;
  const ApiException(this.message);

  @override
  String toString() => message;
}
