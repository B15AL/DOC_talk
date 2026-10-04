import 'package:health_core/health_core.dart';
import 'package:test/test.dart';

/// Answers every remaining question: [overrides] by id, otherwise "no"
/// (or the first option for choice questions).
LocalAIService run(Map<String, String> overrides) {
  final ai = LocalAIService();
  for (var q = ai.nextQuestion(); q != null; q = ai.nextQuestion()) {
    ai.answer(q.id, overrides[q.id] ?? (q.options.isEmpty ? 'no' : q.options.first));
  }
  return ai;
}

void main() {
  group('triage engine', () {
    test('no symptoms -> routine with observe advice', () {
      final ai = run({'age_group': 'age_older'});
      expect(ai.level, TriageLevel.routine);
      expect(ai.suggestions().map((s) => s.id), contains('s_routine_observe'));
    });

    test('danger sign stops questioning and refers urgently', () {
      final ai = LocalAIService();
      ai.answer('age_group', 'age_child');
      ai.answer('ds_unconscious', 'yes');
      expect(ai.nextQuestion(), isNull);
      expect(ai.level, TriageLevel.urgentReferral);
      expect(ai.suggestions().first.reasonIds, ['ds_unconscious']);
    });

    test('"not sure" on a danger sign is never treated as no', () {
      final ai = run({'age_group': 'age_older', 'ds_breathing': 'unsure'});
      expect(ai.level, TriageLevel.clinicianReview);
    });

    test('fever in young infant -> urgent', () {
      final ai = run({'age_group': 'age_infant', 'fever': 'yes'});
      expect(ai.level, TriageLevel.urgentReferral);
    });

    test('follow-up questions only asked when relevant', () {
      final ai = run({'age_group': 'age_older', 'fever': 'no'});
      expect(ai.answers.containsKey('fever_days'), isFalse);
    });

    test('long cough suggests TB test', () {
      final ai = run({'age_group': 'age_older', 'cough': 'yes', 'cough_days': 'c_14_plus'});
      expect(ai.suggestions().map((s) => s.id), contains('s_cough_tb'));
    });

    test('undo re-asks the previous question', () {
      final ai = LocalAIService();
      ai.answer('age_group', 'age_child');
      expect(ai.nextQuestion()!.id, 'ds_unconscious');
      ai.undo();
      expect(ai.nextQuestion()!.id, 'age_group');
    });

    test('every question, option and suggestion has text in every language', () {
      final keys = <String>[
        for (final q in LocalAIService.questionBank) ...[
          'q_${q.id}',
          for (final o in q.options) 'opt_$o',
        ],
        ...run({'age_group': 'age_infant', 'fever': 'yes', 'diarrhea': 'yes'})
            .suggestions()
            .map((s) => s.id),
      ];
      for (final lang in ['en', 'hi']) {
        for (final k in keys) {
          expect(Strings.of(lang, k), isNot(k), reason: '$lang missing $k');
        }
      }
    });
  });

  group('symptom extractor', () {
    test('Hinglish with duration', () {
      expect(SymptomExtractor.extract('3 din se bukhar aur khansi hai'),
          {'fever': 'yes', 'fever_days': 'd_3_6', 'cough': 'yes'});
    });

    test('Devanagari with number word', () {
      expect(SymptomExtractor.extract('मुझे तीन दिन से बुखार है'),
          {'fever': 'yes', 'fever_days': 'd_3_6'});
    });

    test('English weeks -> long cough', () {
      expect(SymptomExtractor.extract('cough for 3 weeks'),
          {'cough': 'yes', 'cough_days': 'c_14_plus'});
    });

    test('number-less durations and colloquial words', () {
      expect(SymptomExtractor.extract('patient has had a cough for a month'),
          {'cough': 'yes', 'cough_days': 'c_14_plus'});
      expect(SymptomExtractor.extract('pichle hafte se tez bukhar'),
          {'fever': 'yes', 'fever_days': 'd_7_plus'});
      expect(SymptomExtractor.extract('child is hot since yesterday and has loose motions'),
          {'fever': 'yes', 'fever_days': 'd_1_2', 'diarrhea': 'yes'});
      expect(SymptomExtractor.extract('टट्टी पतली हो रही है कल से'), {'diarrhea': 'yes'});
      expect(SymptomExtractor.extract('बच्चे को दस्त हो रहे हैं और मल में खून आ रहा है'),
          {'diarrhea': 'yes', 'blood_in_stool': 'yes'});
      expect(SymptomExtractor.extract('बच्चा ठीक है, बस टीका लगवाना है'), isEmpty);
    });

    test('negated clause is ignored', () {
      expect(SymptomExtractor.extract('bukhar nahi hai, dast ho rahe hain'),
          {'diarrhea': 'yes'});
    });

    test('prefilled answers skip questions', () {
      final ai = LocalAIService()..prefillFromText('fever for 8 days');
      final asked = <String>[];
      for (var q = ai.nextQuestion(); q != null; q = ai.nextQuestion()) {
        asked.add(q.id);
        ai.answer(q.id, q.options.isEmpty ? 'no' : 'age_older');
      }
      expect(asked, isNot(contains('fever')));
      expect(asked, isNot(contains('fever_days')));
      expect(ai.level, TriageLevel.clinicianReview);
    });
  });

  test('SMS encode/decode round-trip', () {
    final ai = run({'age_group': 'age_child', 'fever': 'yes', 'fever_days': 'd_7_plus'});
    final c = Consultation(
      id: 'abcdef12-1',
      createdAt: DateTime(2026),
      languageCode: 'hi',
      freeText: '',
      answers: ai.answers,
      level: ai.level,
      suggestions: ai.suggestions(),
    );
    final sms = SmsCodec.encode(c);
    expect(sms.length, lessThan(160));
    expect(sms, startsWith('HAI1 abcdef C A1'));
    final restored = Consultation.fromJson(c.toJson());
    expect(restored.suggestions.map((s) => s.id), c.suggestions.map((s) => s.id));
    final decoded = SmsCodec.decode(sms);
    expect(decoded['level'], 'clinicianReview');
    for (final e in ai.answers.entries) {
      expect(decoded[e.key], e.value, reason: e.key);
    }
  });

  group('LLM output validation', () {
    test('keeps only allowed keys and values', () {
      expect(
        LlmExtraction.parse(
            'Sure! {"fever":"yes","fever_days":"d_3_6","cancer":"yes","cough":"maybe"}'),
        {'fever': 'yes', 'fever_days': 'd_3_6'},
      );
    });

    test('never accepts danger signs or "no"', () {
      expect(LlmExtraction.parse('{"ds_unconscious":"yes","fever":"no"}'), isEmpty);
    });

    test('follow-up implies parent symptom', () {
      expect(LlmExtraction.parse('{"cough_days":"c_14_plus"}'),
          {'cough_days': 'c_14_plus', 'cough': 'yes'});
    });

    test('garbage output -> empty, no exception', () {
      expect(LlmExtraction.parse('I think the patient has fever'), isEmpty);
      expect(LlmExtraction.parse('{"fever": yes'), isEmpty);
    });

    test('fine-tuned prompt matches tools/finetune/train.py', () {
      expect(LlmExtraction.finetunedPrompt('x'),
          'Extract symptoms from this health worker note as JSON.\nNote: x');
    });

    test('prompt lists every allowed key', () {
      final prompt = LlmExtraction.buildPrompt('test');
      for (final key in LlmExtraction.allowed.keys) {
        expect(prompt, contains('"$key"'));
      }
      expect(prompt, isNot(contains('ds_')));
    });
  });
}
