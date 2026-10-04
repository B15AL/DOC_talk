import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:health_core/health_core.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Optional online server (the same one that serves SMS / feature phones).
///
/// Used only when the phone has internet:
///  * AI understanding when the model isn't on this phone (32-bit, low
///    memory, not imported yet),
///  * uploading saved consultations (instead of / as well as SMS).
/// Everything keeps working offline without it.
class ServerService extends ChangeNotifier {
  ServerService._();
  static final ServerService instance = ServerService._();

  static const _prefUrl = 'server_url';
  static const _prefKey = 'server_api_key';

  String url = '';
  String apiKey = '';

  /// Result of the last connection test: null = not tested / unreachable.
  bool? serverHasAi;
  bool reachable = false;

  bool get configured => url.isNotEmpty;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    url = prefs.getString(_prefUrl) ?? '';
    apiKey = prefs.getString(_prefKey) ?? '';
  }

  Future<void> save(String newUrl, String newKey) async {
    url = newUrl.trim().replaceAll(RegExp(r'/+$'), '');
    apiKey = newKey.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefUrl, url);
    await prefs.setString(_prefKey, apiKey);
    notifyListeners();
  }

  Map<String, String> get _headers =>
      {'content-type': 'application/json', if (apiKey.isNotEmpty) 'x-api-key': apiKey};

  Future<bool> test() async {
    reachable = false;
    serverHasAi = null;
    try {
      final res = await http
          .get(Uri.parse('$url/api/status'), headers: _headers)
          .timeout(const Duration(seconds: 6));
      if (res.statusCode == 200) {
        reachable = true;
        serverHasAi = (jsonDecode(res.body) as Map)['ai'] == true;
      }
    } on Object catch (e) {
      debugPrint('server test failed: $e');
    }
    notifyListeners();
    return reachable;
  }

  /// Server-side AI understanding. Returns {} if offline / slow / error.
  /// The reply is re-validated like local model output.
  Future<Map<String, String>> understand(String text) async {
    if (!configured || text.trim().isEmpty) return {};
    try {
      final res = await http
          .post(Uri.parse('$url/api/understand'),
              headers: _headers, body: jsonEncode({'text': text}))
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return {};
      final findings = (jsonDecode(res.body) as Map)['findings'];
      return LlmExtraction.parse(jsonEncode(findings));
    } on Object catch (e) {
      debugPrint('server understand failed: $e');
      return {};
    }
  }

  Future<bool> upload(Consultation c) async {
    if (!configured) return false;
    try {
      final res = await http
          .post(Uri.parse('$url/api/consultations'),
              headers: _headers, body: jsonEncode(c.toJson()))
          .timeout(const Duration(seconds: 10));
      return res.statusCode == 200;
    } on Object catch (e) {
      debugPrint('upload failed: $e');
      return false;
    }
  }
}
