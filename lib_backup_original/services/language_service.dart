import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

class LanguageService {
  static const String _languageKey = 'selected_language';

  // Supported languages for now
  static const Map<String, String> supportedLanguages = {
    'hi': 'हिन्दी (Hindi)',
    // 'en': 'English',
    // Add more later
  };

  // Check if language is already selected
  static Future<String?> getSavedLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_languageKey);
  }

  // Save selected language
  static Future<void> saveLanguage(String code) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_languageKey, code);
  }

  // Get local path where model will be stored
  static Future<String> getModelPath(String languageCode) async {
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/models/$languageCode';
  }

  // Check if model is already downloaded
  static Future<bool> isModelDownloaded(String languageCode) async {
    final path = await getModelPath(languageCode);
    final dir = Directory(path);
    return await dir.exists();
  }
}
