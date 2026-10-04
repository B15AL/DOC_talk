import 'package:flutter_tts/flutter_tts.dart';

import 'package:health_core/health_core.dart';

/// Reads questions aloud, which helps low-literacy users and lets the
/// health worker keep eyes on the patient. Uses the phone's offline TTS voice.
class TtsService {
  final FlutterTts _tts = FlutterTts();

  Future<void> speak(String languageCode, String text) async {
    final locale = Strings.speechLocales[languageCode]?.replaceAll('_', '-');
    if (locale != null) await _tts.setLanguage(locale);
    await _tts.stop();
    await _tts.speak(text);
  }

  Future<void> stop() => _tts.stop();
}
