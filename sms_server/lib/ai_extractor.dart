import 'dart:async';
import 'dart:convert';

import 'package:health_core/health_core.dart';
import 'package:llamadart/llamadart.dart';

/// The fine-tuned symptom extractor (tools/finetune), running on the server
/// with the same prompt, grammar and validation as the Android app.
class ModelExtractor implements AnswerExtractor {
  final LlamaEngine _engine;

  /// One engine runs one generation at a time; requests queue here.
  Future<void> _queue = Future.value();

  ModelExtractor._(this._engine);

  static Future<ModelExtractor> load(String ggufPath) async {
    final engine = LlamaEngine(LlamaBackend());
    await engine.loadModel(
      ggufPath,
      modelParams: const ModelParams(contextSize: 512, gpuLayers: 0),
    );
    return ModelExtractor._(engine);
  }

  static final Map<String, dynamic> _schema = LlmExtraction.compactSchema();

  /// Returns {} (never throws) on any model failure or timeout.
  @override
  Future<Map<String, String>> extract(String text) {
    if (text.trim().isEmpty) return Future.value(const {});
    final result = _queue.then((_) => _run(text.trim()));
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<Map<String, String>> _run(String text) async {
    try {
      final raw = await _engine
          .createStructuredJson(
            [
              LlamaChatMessage.fromText(
                role: LlamaChatRole.user,
                text: LlmExtraction.finetunedPrompt(text),
              ),
            ],
            output: LlamaStructuredOutput<Map<String, dynamic>>.jsonSchema(
              schema: _schema,
              decoder: (j) => j,
            ),
            params: const GenerationParams(maxTokens: 64, temp: 0),
          )
          .timeout(const Duration(seconds: 15));
      return LlmExtraction.parse(jsonEncode(raw));
    } on Object {
      _engine.cancelGeneration();
      return const {};
    }
  }

  Future<void> dispose() => _engine.dispose();
}

/// What was understood from a message, and which parts only the AI found.
typedef Understanding = ({Map<String, String> findings, Set<String> aiOnly});

/// AI model (optional) + keywords; keywords win on conflict, same as the app.
class CombinedExtractor implements AnswerExtractor {
  final AnswerExtractor? model;

  const CombinedExtractor({this.model});

  bool get hasModel => model != null;

  Future<Understanding> understand(String text) async {
    final fromAi = model == null ? const <String, String>{} : await model!.extract(text);
    final fromKeywords = SymptomExtractor.extract(text);
    return (
      findings: {...fromAi, ...fromKeywords},
      aiOnly: fromAi.keys.where((k) => !fromKeywords.containsKey(k)).toSet(),
    );
  }

  @override
  Future<Map<String, String>> extract(String text) async =>
      (await understand(text)).findings;
}
