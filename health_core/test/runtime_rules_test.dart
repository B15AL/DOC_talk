import 'package:health_core/health_core.dart';
import 'package:test/test.dart';

/// Answers questions in the engine's own order; [given] by id, else "no" /
/// the first option. Returns the ids asked, in order.
List<String> interview(LocalAIService ai, Map<String, String> given) {
  final asked = <String>[];
  for (var q = ai.nextQuestion(); q != null; q = ai.nextQuestion()) {
    asked.add(q.id);
    ai.answer(q.id, given[q.id] ?? (q.options.isEmpty ? 'no' : q.options.first));
  }
  return asked;
}

Iterable<String> ids(LocalAIService ai) => ai.suggestions().map((s) => s.id);

void main() {
  group('questions added / removed at runtime', () {
    test('no symptoms -> no extra checks', () {
      final asked = interview(LocalAIService(), {'age_group': 'age_older'});
      expect(asked.where((id) => id.startsWith('dehyd_') || id == 'chest_indrawing'), isEmpty);
    });

    test('loose motions add the dehydration checks, after the danger signs', () {
      final ai = LocalAIService()..prefillFromText('dast ho rahe hain');
      final asked = interview(ai, {'age_group': 'age_child'});
      expect(asked, containsAll(['dehyd_sunken_eyes', 'dehyd_thirsty', 'dehyd_skin_pinch']));
      expect(asked.indexOf('dehyd_sunken_eyes'), greaterThan(asked.indexOf('ds_breathing')));
      expect(asked, isNot(contains('diarrhea'))); // already understood -> removed
    });

    test('a long cough adds the TB check', () {
      final ai = LocalAIService()..prefillFromText('khansi 3 hafte se');
      expect(interview(ai, {'age_group': 'age_older'}), contains('tb_symptoms'));
    });
  });

  group('treatment advice changes with the answers (WHO IMCI)', () {
    LocalAIService diarrhoea(Map<String, String> checks) {
      final ai = LocalAIService()..prefillFromText('dast');
      interview(ai, {'age_group': 'age_child', ...checks});
      return ai;
    }

    test('no dehydration -> Plan A at home', () {
      final ai = diarrhoea({'dehyd_skin_pinch': 'pinch_normal'});
      expect(ids(ai), contains('s_diarrhea_ors'));
      expect(ai.level, TriageLevel.routine);
    });

    test('two "some" signs -> Plan B', () {
      final ai = diarrhoea({'dehyd_thirsty': 'yes', 'dehyd_skin_pinch': 'pinch_slow'});
      expect(ids(ai), contains('s_some_dehydration'));
      expect(ids(ai), isNot(contains('s_diarrhea_ors')));
      expect(ai.level, TriageLevel.clinicianReview);
    });

    test('two severe signs -> urgent referral', () {
      final ai = diarrhoea({'dehyd_sunken_eyes': 'yes', 'dehyd_skin_pinch': 'pinch_very_slow'});
      expect(ids(ai).first, 's_severe_dehydration');
      expect(ai.level, TriageLevel.urgentReferral);
    });

    test('cough: home care / amoxicillin per protocol / urgent', () {
      LocalAIService cough(Map<String, String> a, {String age = 'age_child'}) {
        final ai = LocalAIService()..prefillFromText('khansi hai');
        interview(ai, {'age_group': age, ...a});
        return ai;
      }

      expect(ids(cough({})), contains('s_cough_home'));
      expect(ids(cough({'cough_fast_breathing': 'yes'})), contains('s_pneumonia'));
      expect(cough({'chest_indrawing': 'yes'}).level, TriageLevel.urgentReferral);
      expect(cough({'cough_fast_breathing': 'yes'}, age: 'age_infant').level,
          TriageLevel.urgentReferral);
    });

    test('fever: malaria result changes the advice', () {
      LocalAIService fever(String rdt) {
        final ai = LocalAIService()..prefillFromText('bukhar 2 din se');
        interview(ai, {'age_group': 'age_older', 'malaria_test': rdt});
        return ai;
      }

      expect(ids(fever('rdt_positive')), contains('s_malaria_positive'));
      expect(ids(fever('rdt_negative')), contains('s_malaria_negative'));
      expect(ids(fever('rdt_not_done')), contains('s_fever_tests'));
      final stiff = LocalAIService()..prefillFromText('bukhar');
      interview(stiff, {'age_group': 'age_older', 'fever_stiff_neck': 'yes'});
      expect(stiff.level, TriageLevel.urgentReferral);
    });
  });

  test('every question, option and possible suggestion has Hindi + English text', () {
    final keys = <String>{
      for (final q in LocalAIService.questionBank) ...['q_${q.id}', for (final o in q.options) 'opt_$o'],
    };
    // Exercise many rule paths to collect suggestion ids.
    for (final given in [
      {'malaria_test': 'rdt_positive', 'fever_rash': 'yes', 'fever_stiff_neck': 'yes'},
      {'malaria_test': 'rdt_negative', 'cough_fast_breathing': 'yes'},
      {'chest_indrawing': 'yes', 'cough_days': 'c_14_plus', 'tb_symptoms': 'unsure'},
      {'dehyd_thirsty': 'yes', 'dehyd_restless': 'yes', 'blood_in_stool': 'yes'},
      {'dehyd_sunken_eyes': 'yes', 'dehyd_skin_pinch': 'pinch_very_slow'},
    ]) {
      final ai = LocalAIService()..prefillFromText('bukhar, khansi aur dast');
      interview(ai, {'age_group': 'age_child', ...given});
      keys.addAll(ids(ai));
    }
    for (final lang in ['en', 'hi']) {
      for (final k in keys) {
        expect(Strings.has(lang, k) && Strings.of(lang, k) != k, isTrue, reason: '$lang $k');
      }
    }
    for (final k in keys) {
      expect(Strings.of('hi', k), isNot(Strings.of('en', k)), reason: 'hi missing $k');
    }
  });
}
