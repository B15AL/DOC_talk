import 'package:health_core/health_core.dart';
import 'package:test/test.dart';

Question q(String id) => LocalAIService.questionBank.firstWhere((q) => q.id == id);

void main() {
  group('dynamic question order', () {
    test('follow-up on a mentioned symptom comes right after age', () {
      final ai = LocalAIService()..prefillFromText('bukhar hai');
      ai.answer('age_group', 'age_child');
      expect(ai.nextQuestion()!.id, 'fever_days');
    });

    test('danger signs related to the reported symptom come first', () {
      final ai = LocalAIService()..prefillFromText('dast ho rahe hain');
      ai.answer('age_group', 'age_child');
      ai.answer('blood_in_stool', 'no');
      expect(ai.nextQuestion()!.id, 'ds_cannot_drink');
    });

    test('every danger sign is still asked', () {
      final ai = LocalAIService()..prefillFromText('khansi 3 din se');
      final asked = <String>[];
      for (var next = ai.nextQuestion(); next != null; next = ai.nextQuestion()) {
        asked.add(next.id);
        ai.answer(next.id, next.options.isEmpty ? 'no' : next.options.last);
      }
      expect(asked, containsAll(LocalAIService.dangerSignIds));
      expect(asked.indexOf('ds_breathing'), lessThan(asked.indexOf('ds_unconscious')));
    });

    test('removing a wrong finding re-asks it and its follow-up', () {
      final ai = LocalAIService()..prefillFromText('fever 3 days');
      ai.removePrefilled('fever');
      expect(ai.answers.containsKey('fever'), isFalse);
      expect(ai.answers.containsKey('fever_days'), isFalse);
    });
  });

  group('phrasing', () {
    test('refers back to what was said', () {
      final ai = LocalAIService()..prefillFromText('bukhar hai');
      ai.answer('age_group', 'age_older');
      expect(QuestionPhrasing.phrase('en', q('fever_days'), ai, previousAnswer: 'age_older'),
          'Thanks. You mentioned fever. For how many days has it been there?');
    });

    test('child wording, safety intro and reason', () {
      final ai = LocalAIService()..prefillFromText('dast');
      ai.answer('age_group', 'age_child');
      final text = QuestionPhrasing.phrase('en', q('ds_cannot_drink'), ai);
      expect(text, 'Now a few important safety questions. '
          'With loose motions, please check: Is the child unable to drink or breastfeed?');
    });

    test('every phrasing key exists in Hindi', () {
      for (final key in [
        'ack_yes_1', 'ack_no_2', 'ds_intro', 'qc_fever_days', 'because_cough',
        'q_ds_cannot_drink_child', 'chat_start', 'chat_understood',
      ]) {
        expect(Strings.of('hi', key), isNot(Strings.of('en', key)), reason: key);
      }
    });
  });

  group('typed answers', () {
    test('yes / no / unsure in three languages', () {
      final fever = q('fever');
      expect(AnswerParser.parse(fever, 'haan ji'), 'yes');
      expect(AnswerParser.parse(fever, 'नहीं'), 'no');
      expect(AnswerParser.parse(fever, 'pata nahi'), 'unsure');
      expect(AnswerParser.parse(fever, 'yes it is there'), 'yes');
      expect(AnswerParser.parse(fever, 'banana'), isNull);
    });

    test('durations and ages in words', () {
      expect(AnswerParser.parse(q('fever_days'), '5 din se'), 'd_3_6');
      expect(AnswerParser.parse(q('fever_days'), 'ek hafte se'), 'd_7_plus');
      expect(AnswerParser.parse(q('cough_days'), '3 weeks'), 'c_14_plus');
      expect(AnswerParser.parse(q('age_group'), '3 saal ka hai'), 'age_child');
      expect(AnswerParser.parse(q('age_group'), '1 mahine ka'), 'age_infant');
      expect(AnswerParser.parse(q('age_group'), '35 years'), 'age_older');
    });

    test('digits: options on SMS, quantities in the app', () {
      expect(AnswerParser.parse(q('fever_days'), '2', digitsAreOptions: true), 'd_3_6');
      expect(AnswerParser.parse(q('fever_days'), '2'), 'd_1_2'); // 2 days
      expect(AnswerParser.parse(q('fever'), '2', digitsAreOptions: true), 'no');
    });
  });
}
