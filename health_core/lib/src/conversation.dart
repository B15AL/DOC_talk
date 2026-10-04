import 'consultation_model.dart';
import 'local_ai_service.dart';
import 'strings.dart';
import 'symptom_extractor.dart';

/// Turns the next question into a conversational message that reacts to
/// what has been said: acknowledges the last answer, explains *why* this
/// question comes now ("You mentioned fever…"), and speaks about "the child"
/// for young patients. All text comes from reviewed language packs — the
/// small model never writes medical questions itself.
class QuestionPhrasing {
  static String phrase(
    String lang,
    Question q,
    LocalAIService ai, {
    String? previousAnswer,
    int turn = 0,
  }) {
    String t(String key) => Strings.of(lang, key);
    final parts = <String>[];

    if (previousAnswer != null) {
      final ack = switch (previousAnswer) {
        'yes' => turn.isEven ? 'ack_yes_1' : 'ack_yes_2',
        'no' => turn.isEven ? 'ack_no_1' : 'ack_no_2',
        'unsure' => 'ack_unsure',
        _ => 'ack_choice',
      };
      parts.add(t(ack));
    }

    final firstDangerSign = q.isDangerSign &&
        !LocalAIService.dangerSignIds.any(ai.answers.containsKey);
    if (firstDangerSign) parts.add(t('ds_intro'));

    final reason = ai.reasonFor(q);
    final fromDescription = reason != null && ai.prefilled.contains(reason);
    if (q.showIf.isNotEmpty && fromDescription && Strings.has(lang, 'qc_${q.id}')) {
      // "You mentioned fever. For how many days has it been there?"
      parts.add(t('qc_${q.id}'));
    } else {
      // "With loose motions, please check:" — once per group of added checks.
      final groupStarted = q.isAssessment &&
          LocalAIService.questionBank.any((o) =>
              o.isAssessment &&
              o.showIf.keys.first == reason &&
              ai.answers.containsKey(o.id));
      if ((q.isDangerSign || q.isAssessment) && reason != null && !groupStarted) {
        parts.add(t('because_$reason'));
      }
      parts.add(_questionText(lang, q, ai));
    }
    return parts.join(' ');
  }

  /// Plain question text, child-specific wording for patients under 5.
  static String _questionText(String lang, Question q, LocalAIService ai) {
    final isChild = const ['age_infant', 'age_child'].contains(ai.answers['age_group']);
    if (isChild && Strings.has(lang, 'q_${q.id}_child')) {
      return Strings.of(lang, 'q_${q.id}_child');
    }
    return Strings.of(lang, 'q_${q.id}');
  }
}

/// Understands a typed / spoken reply to the current question:
/// "haan", "nahi", "pata nahi", "5 din se", "3 saal ka hai", "2"...
class AnswerParser {
  static const _yes = {
    'y', 'yes', 'yeah', 'yup', 'ha', 'haa', 'haan', 'han', 'hn', 'ji', 'hanji',
    'bilkul', 'sahi', 'हाँ', 'हां', 'हा', 'जी',
  };
  static const _no = {
    'n', 'no', 'nope', 'nahi', 'nahin', 'nai', 'na', 'nhi', 'not', 'never',
    'नहीं', 'नही', 'ना', 'न',
  };
  static const _unsurePhrases = [
    'not sure', 'unsure', "don't know", 'dont know', 'pata nahi', 'pta nahi',
    'malum nahi', 'pakka nahi', 'पता नहीं', 'पक्का नहीं', 'मालूम नहीं',
  ];

  /// Returns the answer value for [q], or null if not understood.
  ///
  /// [digitsAreOptions]: on SMS a bare "2" means option 2 / "No"; in the app
  /// (which has buttons) a bare number is read as days or years instead.
  static String? parse(Question q, String reply, {bool digitsAreOptions = false}) {
    final r = reply.trim().toLowerCase().replaceAll(RegExp(r'[.!?।,]+$'), '');
    if (r.isEmpty) return null;
    final n = int.tryParse(r);

    if (q.type == QuestionType.yesNo) {
      if (n != null && digitsAreOptions) {
        return const {1: 'yes', 2: 'no', 3: 'unsure'}[n];
      }
      if (r == '?' || _unsurePhrases.any(r.contains)) return Answer.unsure.name;
      final words = r.split(RegExp(r'[\s,]+'));
      final saysNo = words.any(_no.contains);
      final saysYes = words.any(_yes.contains);
      if (saysNo && !saysYes) return Answer.no.name;
      if (saysYes && !saysNo) return Answer.yes.name;
      return null;
    }

    if (n != null && digitsAreOptions) {
      return n >= 1 && n <= q.options.length ? q.options[n - 1] : null;
    }
    return switch (q.id) {
      'age_group' => _ageGroup(r),
      'fever_days' => _bucket(r, (d) => d >= 7 ? 'd_7_plus' : (d >= 3 ? 'd_3_6' : 'd_1_2')),
      'cough_days' => _bucket(r, (d) => d >= 14 ? 'c_14_plus' : 'c_lt_14'),
      _ => null,
    };
  }

  static String? _bucket(String r, String Function(int days) toOption) {
    final days = SymptomExtractor.durationInDays(r) ?? int.tryParse(r);
    return days == null ? null : toOption(days);
  }

  static final _ageNumber = RegExp(r'(\d+)\s*([^\d\s]*)');

  static String? _ageGroup(String r) {
    if (const ['newborn', 'navjaat', 'नवजात'].any(r.contains)) return 'age_infant';
    final m = _ageNumber.firstMatch(r);
    if (m == null) return null;
    final n = int.parse(m.group(1)!);
    final unit = m.group(2)!;
    final months = switch (unit) {
      _ when unit.startsWith('d') || unit.startsWith('दि') => n / 30,
      _ when unit.startsWith('w') || unit.startsWith('haf') || unit.startsWith('हफ') => n / 4,
      _ when unit.startsWith('m') || unit.startsWith('मही') => n.toDouble(),
      _ => n * 12.0, // years: "3", "3 saal", "3 years", "3 साल"
    };
    if (months < 2) return 'age_infant';
    if (months < 60) return 'age_child';
    return 'age_older';
  }
}
