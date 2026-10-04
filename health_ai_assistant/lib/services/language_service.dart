import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:health_core/health_core.dart';

class LanguageService {
  static const String _languageKey = 'selected_language';

  /// Language packs bundled with the app (see utils/strings.dart).
  /// Keep packs as small JSON so new languages can later be downloaded once
  /// and then used offline.
  static const Map<String, String> supportedLanguages = {
    'hi': 'हिन्दी (Hindi)',
    'en': 'English',
  };

  /// Currently active language; widgets listening to it rebuild on change.
  static final ValueNotifier<String> current = ValueNotifier('hi');

  /// Translate [key] into the current language.
  static String t(String key) => Strings.of(current.value, key);

  static Future<String?> getSavedLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_languageKey);
  }

  static Future<void> saveLanguage(String code) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_languageKey, code);
    current.value = code;
  }
}
