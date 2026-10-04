import 'package:speech_to_text/speech_to_text.dart';

import 'package:health_core/health_core.dart';

/// Speech-to-text using the phone's built-in recogniser. On Android it works
/// offline once the language's offline speech pack is installed
/// (Settings → Google → Voice → Offline speech recognition).
class SttService {
  final SpeechToText _speech = SpeechToText();
  bool _ready = false;

  bool get isListening => _speech.isListening;

  Future<bool> init() async {
    _ready = _ready || await _speech.initialize();
    return _ready;
  }

  Future<void> listen(String languageCode, void Function(String text) onText) async {
    if (!await init()) return;
    await _speech.listen(
      onResult: (r) => onText(r.recognizedWords),
      listenOptions: SpeechListenOptions(
        localeId: Strings.speechLocales[languageCode],
        partialResults: true,
      ),
    );
  }

  Future<void> stop() => _speech.stop();
}
