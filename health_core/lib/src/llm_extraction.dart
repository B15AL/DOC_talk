import 'dart:convert';

import 'consultation_model.dart';
import 'local_ai_service.dart';
import 'symptom_extractor.dart';

/// Anything that turns a free-text description into pre-filled answers.
/// The app can swap the keyword version for an on-device LLM without
/// touching the triage rules.
abstract class AnswerExtractor {
  Future<Map<String, String>> extract(String text);
}

class KeywordAnswerExtractor implements AnswerExtractor {
  const KeywordAnswerExtractor();

  @override
  Future<Map<String, String>> extract(String text) async =>
      SymptomExtractor.extract(text);
}

/// Prompt building and *strict* validation of LLM output.
///
/// The model is treated as untrusted: anything outside the allowed keys and
/// values is dropped, danger signs are never accepted (they must be asked),
/// and only positive findings are kept — same rules as [SymptomExtractor].
class LlmExtraction {
  /// question id -> values the model may set.
  /// Only the fields the fine-tuned model was trained on. Danger signs and
  /// added checks (dehydration, breathing...) are always asked.
  static const extractable = [
    'fever', 'fever_days', 'cough', 'cough_days', 'diarrhea', 'blood_in_stool',
  ];

  static final Map<String, List<String>> allowed = {
    for (final q in LocalAIService.questionBank)
      if (extractable.contains(q.id))
        q.id: q.type == QuestionType.choice ? q.options : const ['yes'],
  };

  /// Follow-up question -> the parent it implies (fever_days => fever=yes).
  static final Map<String, String> _parents = {
    for (final q in LocalAIService.questionBank)
      for (final key in q.showIf.keys) q.id: key,
  };

  /// Filler value the model must use for anything not stated. Every key is
  /// required in [jsonSchema]: with all-optional keys, small models take the
  /// easy path and always answer `{}`.
  static const notSaid = 'not_said';

  /// JSON schema for grammar-constrained decoding (llama.cpp GBNF).
  static Map<String, dynamic> jsonSchema() => {
        'type': 'object',
        'additionalProperties': false,
        'required': allowed.keys.toList(),
        'properties': {
          for (final e in allowed.entries)
            e.key: {
              'type': 'string',
              'enum': [...e.value, notSaid],
            },
        },
      };

  static String _example(Map<String, String> found) => jsonEncode({
        for (final key in allowed.keys) key: found[key] ?? notSaid,
      });

  static String buildPrompt(String description) {
    final schema = allowed.entries
        .map((e) => '- ${e.key}: ${[...e.value, notSaid].join(' | ')}')
        .join('\n');
    return '''
Fill a symptom form from a health worker's note (Hindi, Hinglish or English).
For each key, answer "yes" (or the matching duration) only if the note says the symptom is PRESENT.
Use "$notSaid" if the symptom is not mentioned or is denied (e.g. "bukhar nahi hai").
Keys:
$schema
Durations: d_1_2 = 1-2 days, d_3_6 = 3-6 days, d_7_plus = 7+ days (a week or more).
Cough: c_lt_14 = under 2 weeks, c_14_plus = 2 weeks or more.
Hints: bukhar/बुखार/garam/hot body = fever; khansi/खाँसी = cough; dast/दस्त/loose motion/patli tatti = diarrhea; khoon/खून in stool = blood_in_stool.

Note: "3 din se bukhar aur khansi"
${_example({'fever': 'yes', 'fever_days': 'd_3_6', 'cough': 'yes'})}
Note: "बुखार नहीं है, पर दस्त में खून आ रहा है"
${_example({'diarrhea': 'yes', 'blood_in_stool': 'yes'})}
Note: "child is fine, came for vaccination"
${_example({})}
Note: "${description.replaceAll('"', "'")}"
''';
  }

  // ---- Fine-tuned model -------------------------------------------------
  // tools/finetune trains Gemma 3 270M on exactly this prompt and on compact
  // JSON targets (present findings only). Keep FINETUNED_PROMPT in
  // tools/finetune/train.py identical — a test pins the text.

  static String finetunedPrompt(String note) =>
      'Extract symptoms from this health worker note as JSON.\nNote: $note';

  /// Schema for the fine-tuned model: keys optional, values restricted.
  static Map<String, dynamic> compactSchema() => {
        'type': 'object',
        'additionalProperties': false,
        'properties': {
          for (final e in allowed.entries)
            e.key: {'type': 'string', 'enum': e.value},
        },
      };

  // ---- Per-question strategy -------------------------------------------
  // One short multiple-choice question per symptom. Small (<1B) models are
  // far more reliable at this than at filling a whole JSON form at once.

  static const _questions = <_LlmQuestion>[
    _LlmQuestion('fever', 'Does the note say the patient has fever? '
        '(fever = bukhar, बुखार, ज्वर, tez garam, hot body, temperature)',
        {'yes': 'yes', 'no': null}),
    _LlmQuestion('fever_days', 'For how long has the fever been there?',
        {'1-2 days': 'd_1_2', '3-6 days': 'd_3_6', '7 or more days': 'd_7_plus', 'not stated': null},
        parent: 'fever'),
    _LlmQuestion('cough', 'Does the note say the patient has a cough? (cough = khansi, खांसी, खाँसी)',
        {'yes': 'yes', 'no': null}),
    _LlmQuestion('cough_days', 'For how long has the cough been there?',
        {'less than 2 weeks': 'c_lt_14', '2 weeks or more': 'c_14_plus', 'not stated': null},
        parent: 'cough'),
    _LlmQuestion('diarrhea', 'Does the note say the patient has diarrhoea / loose motions? '
        '(dast, दस्त, loose motion, patli tatti, पतली टट्टी)',
        {'yes': 'yes', 'no': null}),
    _LlmQuestion('blood_in_stool', 'Does the note say there is blood in the stool? (khoon, खून)',
        {'yes': 'yes', 'no': null},
        parent: 'diarrhea'),
  ];

  /// Schema for one answer: {"answer": one of [options]}.
  static Map<String, dynamic> answerSchema(List<String> options) => {
        'type': 'object',
        'additionalProperties': false,
        'required': ['answer'],
        'properties': {
          'answer': {'type': 'string', 'enum': options},
        },
      };

  /// Few-shot prompt. Examples use a symptom we never ask about
  /// (headache) so the model learns the task without copying answers.
  static String questionPrompt(String note, String question, List<String> options) {
    final isDuration = options.length > 2;
    final examples = isDuration
        ? '''
Note: "sir mein dard 10 din se hai"
Question: For how long has the headache been there?
Options: 1-2 days, 3-6 days, 7 or more days, not stated
Answer: {"answer": "7 or more days"}

Note: "she has had a headache since yesterday"
Question: For how long has the headache been there?
Options: 1-2 days, 3-6 days, 7 or more days, not stated
Answer: {"answer": "1-2 days"}

Note: "सिर दर्द है और उल्टी"
Question: For how long has the headache been there?
Options: 1-2 days, 3-6 days, 7 or more days, not stated
Answer: {"answer": "not stated"}
'''
        : '''
Note: "do din se sir mein dard hai"
Question: Does the patient have a headache?
Options: yes, no
Answer: {"answer": "yes"}

Note: "sir dard nahi hai, pet kharab hai"
Question: Does the patient have a headache?
Options: yes, no
Answer: {"answer": "no"}

Note: "बच्चे को सिर दर्द और बुखार है"
Question: Does the patient have a headache?
Options: yes, no
Answer: {"answer": "yes"}

Note: "child has a rash on the arm"
Question: Does the patient have a headache?
Options: yes, no
Answer: {"answer": "no"}
''';
    return '''
Read the health worker's note (Hindi, Hinglish or English) and answer the question.

$examples
Note: "${note.replaceAll('"', "'")}"
Question: $question
Options: ${options.join(', ')}
Answer:''';
  }

  /// Runs the per-question strategy. [ask] sends one prompt to the model
  /// (constrained to [answerSchema]) and returns the chosen option label.
  static Future<Map<String, String>> extractByQuestions(
    String note,
    Future<String> Function(String prompt, List<String> options) ask,
  ) async {
    final found = <String, String>{};
    for (final q in _questions) {
      if (q.parent != null && found[q.parent] != 'yes') continue;
      final options = q.answers.keys.toList();
      final label = await ask(questionPrompt(note, q.question, options), options);
      final value = q.answers[label];
      if (value != null) found[q.id] = value;
    }
    // Same validation as model-written JSON.
    return parse(jsonEncode(found));
  }

  /// Parses model output defensively. Never throws; returns {} on garbage.
  static Map<String, String> parse(String modelOutput) {
    final start = modelOutput.indexOf('{');
    final end = modelOutput.indexOf('}', start + 1);
    if (start < 0 || end < 0) return {};
    Object? decoded;
    try {
      decoded = jsonDecode(modelOutput.substring(start, end + 1));
    } on FormatException {
      return {};
    }
    if (decoded is! Map) return {};

    final out = <String, String>{};
    decoded.forEach((key, value) {
      if (key is String && value is String && (allowed[key]?.contains(value) ?? false)) {
        out[key] = value;
      }
    });
    for (final child in out.keys.toList()) {
      final parent = _parents[child];
      if (parent != null) out[parent] = 'yes';
    }
    return out;
  }
}

class _LlmQuestion {
  final String id;
  final String question;

  /// Option label shown to the model -> stored value (null = nothing).
  final Map<String, String?> answers;
  final String? parent;

  const _LlmQuestion(this.id, this.question, this.answers, {this.parent});
}
