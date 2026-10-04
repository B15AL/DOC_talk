import 'dart:convert';
import 'dart:io';

import 'package:health_core/health_core.dart';
import 'package:llamadart/llamadart.dart';

/// dart run bin/eval.dart <hf://owner/repo/file.gguf | /path/model.gguf> [form|questions|finetuned] [heldout]
/// Scores a model on realistic notes: exact-match on the allowed keys.
const cases = <String, Map<String, String>>{
  // A duration before "A aur B" applies to both symptoms.
  '3 din se bukhar aur khansi hai': {'fever': 'yes', 'fever_days': 'd_3_6', 'cough': 'yes', 'cough_days': 'c_lt_14'},
  'मुझे तीन दिन से बुखार है': {'fever': 'yes', 'fever_days': 'd_3_6'},
  'बच्चे को दस्त हो रहे हैं और मल में खून आ रहा है': {'diarrhea': 'yes', 'blood_in_stool': 'yes'},
  'patient has had a cough for a month': {'cough': 'yes', 'cough_days': 'c_14_plus'},
  'bukhar nahi hai, bas khansi hai 2 hafte se': {'cough': 'yes', 'cough_days': 'c_14_plus'},
  'child is hot since yesterday and has loose motions': {'fever': 'yes', 'fever_days': 'd_1_2', 'diarrhea': 'yes'},
  'pichle hafte se tez bukhar': {'fever': 'yes', 'fever_days': 'd_7_plus'},
  'बच्चा ठीक है, बस टीका लगवाना है': {},
  'khansi aur saans phool rahi hai': {'cough': 'yes'},
  'टट्टी पतली हो रही है कल से': {'diarrhea': 'yes'},
  'fever 10 days, no cough': {'fever': 'yes', 'fever_days': 'd_7_plus'},
  'badan garam hai aur sar dard': {'fever': 'yes'},
};

/// Dev set: used to find error patterns for training round 2 (so no longer
/// a fair test).
const heldOut = <String, Map<String, String>>{
  'do hafte se khaansi ho rahi hai, raat ko zyada': {'cough': 'yes', 'cough_days': 'c_14_plus'},
  'my son has been feverish for four days': {'fever': 'yes', 'fever_days': 'd_3_6'},
  'बच्ची को पाँच दिन से तेज़ बुखार और खाँसी है': {'fever': 'yes', 'fever_days': 'd_3_6', 'cough': 'yes', 'cough_days': 'c_lt_14'},
  'pet kharab hai, baar baar paani jaisa latrine': {'diarrhea': 'yes'},
  'temperature since morning, otherwise fine': {'fever': 'yes', 'fever_days': 'd_1_2'},
  'khansi nahi, dast nahi, sirf kamzori': {},
  'teen hafte se bukhar aa jata hai shaam ko': {'fever': 'yes', 'fever_days': 'd_7_plus'},
  'उल्टी दस्त दोनों हो रहे हैं, खून नहीं है': {'diarrhea': 'yes'},
  'coughing up phlegm for 20 days': {'cough': 'yes', 'cough_days': 'c_14_plus'},
  'baccha garam hai aur khaana nahi kha raha': {'fever': 'yes'},
};

/// Fresh test set: written before training round 2, never used for tuning.
const fresh = <String, Map<String, String>>{
  'chhote bachche ko kal raat se bukhar hai': {'fever': 'yes', 'fever_days': 'd_1_2'},
  'mahine bhar se khaans raha hai, wajan bhi kam hua': {'cough': 'yes', 'cough_days': 'c_14_plus'},
  'मरीज़ को चार दिन से दस्त लगे हैं': {'diarrhea': 'yes'},
  'no fever, no loose motions, only a runny nose': {},
  'she had fever on and off for 2 weeks and now cough too': {'fever': 'yes', 'fever_days': 'd_7_plus', 'cough': 'yes'},
  'latrine mein khoon aa raha hai aur pet mein marod': {'blood_in_stool': 'yes', 'diarrhea': 'yes'},
  'खाँसी पिछले 10 दिन से है, बुखार नहीं': {'cough': 'yes', 'cough_days': 'c_lt_14'},
  'bacche ka sharir tap raha hai subah se': {'fever': 'yes', 'fever_days': 'd_1_2'},
  'loose motions since 3 days, child very thirsty': {'diarrhea': 'yes'},
  'sirf thoda zukaam hai, aur kuch nahi': {},
  'बुखार 6 दिन से और सूखी खाँसी': {'fever': 'yes', 'fever_days': 'd_3_6', 'cough': 'yes'},
  'cough with blood in sputum for 3 weeks': {'cough': 'yes', 'cough_days': 'c_14_plus'},
};

Future<void> main(List<String> args) async {
  final engine = LlamaEngine(LlamaBackend());
  final schema = LlmExtraction.jsonSchema();
  try {
    final sw = Stopwatch()..start();
    final perQuestion = args.length > 1 && args[1] == 'questions';
    final finetuned = args.length > 1 && args[1] == 'finetuned';
    await engine.loadModelSource(ModelSource.parse(args.first),
        modelParams: ModelParams(contextSize: finetuned ? 512 : 2048, gpuLayers: 0));
    stdout.writeln('loaded in ${sw.elapsedMilliseconds} ms (${engine.getBackendName()})');
    var exact = 0;
    var kwExact = 0;
    var mergedExact = 0;
    var aiAddedRight = 0;
    var aiAddedWrong = 0;
    var totalMs = 0;
    final set = args.contains('fresh') ? fresh : (args.contains('heldout') ? heldOut : cases);
    for (final c in set.entries) {
      sw.reset();
      final Map<String, String> got;
      if (finetuned) {
        // Exactly what the app does (AiModelService.extract).
        final raw = await engine.createStructuredJson(
          [LlamaChatMessage.fromText(role: LlamaChatRole.user, text: LlmExtraction.finetunedPrompt(c.key))],
          output: LlamaStructuredOutput<Map<String, dynamic>>.jsonSchema(
              schema: LlmExtraction.compactSchema(), decoder: (j) => j),
          params: const GenerationParams(maxTokens: 64, temp: 0),
        );
        got = LlmExtraction.parse(jsonEncode(raw));
      } else if (perQuestion) {
        got = await LlmExtraction.extractByQuestions(c.key, (prompt, options) async {
          final raw = await engine.createStructuredJson(
            [LlamaChatMessage.fromText(role: LlamaChatRole.user, text: prompt)],
            output: LlamaStructuredOutput<Map<String, dynamic>>.jsonSchema(
                schema: LlmExtraction.answerSchema(options), decoder: (j) => j),
            params: const GenerationParams(maxTokens: 16, temp: 0),
            enableThinking: false,
          );
          return raw['answer'] as String;
        });
      } else {
        final raw = await engine.createStructuredJson(
          [LlamaChatMessage.fromText(role: LlamaChatRole.user, text: LlmExtraction.buildPrompt(c.key))],
          output: LlamaStructuredOutput<Map<String, dynamic>>.jsonSchema(schema: schema, decoder: (j) => j),
          params: const GenerationParams(maxTokens: 96, temp: 0),
          enableThinking: false,
        );
        got = LlmExtraction.parse(jsonEncode(raw));
      }
      final ms = sw.elapsedMilliseconds;
      totalMs += ms;
      final kw = SymptomExtractor.extract(c.key);
      final ok = _same(got, c.value);
      if (ok) exact++;
      if (_same(kw, c.value)) kwExact++;
      // What the app does: AI ∪ keywords (keywords win on conflict).
      final merged = {...got, ...kw};
      if (_same(merged, c.value)) mergedExact++;
      for (final e in got.entries.where((e) => !kw.containsKey(e.key))) {
        c.value[e.key] == e.value ? aiAddedRight++ : aiAddedWrong++;
      }
      stdout.writeln('${ok ? 'OK ' : 'BAD'} ${ms}ms  ${c.key}\n     llm=$got\n     kw =$kw');
    }
    stdout.writeln('\nLLM exact: $exact/${set.length}   keywords exact: $kwExact/${set.length}'
        '   avg ${totalMs ~/ set.length} ms/note');
    stdout.writeln('merged exact: $mergedExact/${set.length}   '
        'AI additions beyond keywords: $aiAddedRight right, $aiAddedWrong wrong');
  } finally {
    await engine.dispose();
  }
}

bool _same(Map<String, String> a, Map<String, String> b) =>
    a.length == b.length && a.entries.every((e) => b[e.key] == e.value);
