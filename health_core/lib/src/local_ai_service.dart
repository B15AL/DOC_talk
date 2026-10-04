import 'consultation_model.dart';
import 'symptom_extractor.dart';

/// Offline triage engine: decides which question to ask next and turns the
/// answers into suggestions with a triage level.
///
/// Deliberately rule-based (WHO IMCI-style) rather than generative: every
/// suggestion is traceable to specific answers, works on any phone, and
/// cannot hallucinate. An LLM, if added, should only fill [answers] from
/// free text (see [SymptomExtractor]) — never decide referrals.
class LocalAIService {
  static const List<String> dangerSignIds = [
    'ds_unconscious',
    'ds_convulsions',
    'ds_cannot_drink',
    'ds_vomits_everything',
    'ds_breathing',
  ];

  /// Danger signs come first so an emergency is caught in the first few taps.
  static const List<Question> questionBank = [
    Question(
      id: 'age_group',
      type: QuestionType.choice,
      options: ['age_infant', 'age_child', 'age_older'],
    ),
    Question(id: 'ds_unconscious', isDangerSign: true),
    Question(id: 'ds_convulsions', isDangerSign: true),
    Question(id: 'ds_cannot_drink', isDangerSign: true),
    Question(id: 'ds_vomits_everything', isDangerSign: true),
    Question(id: 'ds_breathing', isDangerSign: true),
    Question(id: 'fever'),
    Question(
      id: 'fever_days',
      type: QuestionType.choice,
      options: ['d_1_2', 'd_3_6', 'd_7_plus'],
      showIf: {'fever': Answer.yes},
    ),
    Question(id: 'cough'),
    Question(
      id: 'cough_days',
      type: QuestionType.choice,
      options: ['c_lt_14', 'c_14_plus'],
      showIf: {'cough': Answer.yes},
    ),
    Question(id: 'diarrhea'),
    Question(id: 'blood_in_stool', showIf: {'diarrhea': Answer.yes}),
  ];

  /// question id -> Answer name or choice option id.
  final Map<String, String> answers = {};

  /// Answers that came from the free-text description, not a button tap.
  final Set<String> prefilled = {};

  final List<String> _history = [];

  void prefillFromText(String text) => prefill(SymptomExtractor.extract(text));

  /// Pre-fill from any extractor (keywords, on-device LLM, ...). Never
  /// overwrites an answer the worker gave by tapping.
  void prefill(Map<String, String> extracted) {
    extracted.forEach((id, value) {
      if (answers.containsKey(id)) return;
      answers[id] = value;
      prefilled.add(id);
    });
  }

  /// Next unanswered, applicable question; null when done. Stops early once
  /// a danger sign is confirmed — the worker should act, not keep tapping.
  Question? nextQuestion() {
    if (hasDangerSign) return null;
    for (final q in questionBank) {
      if (!answers.containsKey(q.id) && _shouldShow(q)) return q;
    }
    return null;
  }

  void answer(String questionId, String value) {
    answers[questionId] = value;
    prefilled.remove(questionId);
    _history.add(questionId);
  }

  bool get canUndo => _history.isNotEmpty;

  void undo() {
    if (_history.isEmpty) return;
    answers.remove(_history.removeLast());
  }

  /// Answered / (answered + still applicable), so skipped follow-ups
  /// don't leave the bar stuck below 100%.
  double get progress {
    final applicable = questionBank.where(_shouldShow).toList();
    if (applicable.isEmpty) return 1;
    final done = applicable.where((q) => answers.containsKey(q.id)).length;
    return hasDangerSign ? 1 : done / applicable.length;
  }

  bool get hasDangerSign => dangerSignIds.any((id) => _is(id, Answer.yes));

  List<Suggestion> suggestions() {
    final out = <Suggestion>[];

    final dangerYes = dangerSignIds.where((id) => _is(id, Answer.yes)).toList();
    if (dangerYes.isNotEmpty) {
      out.add(Suggestion('s_urgent_danger', TriageLevel.urgentReferral, dangerYes));
    }
    if (answers['age_group'] == 'age_infant' && _is('fever', Answer.yes)) {
      out.add(const Suggestion(
          's_infant_fever', TriageLevel.urgentReferral, ['age_group', 'fever']));
    }

    // "Not sure" on a danger sign is treated cautiously, never as "no".
    final dangerUnsure = dangerSignIds.where((id) => _is(id, Answer.unsure)).toList();
    if (dangerUnsure.isNotEmpty) {
      out.add(Suggestion('s_unsure_danger', TriageLevel.clinicianReview, dangerUnsure));
    }
    if (answers['fever_days'] == 'd_7_plus') {
      out.add(const Suggestion('s_fever_long', TriageLevel.clinicianReview, ['fever_days']));
    }
    if (answers['cough_days'] == 'c_14_plus') {
      out.add(const Suggestion('s_cough_tb', TriageLevel.clinicianReview, ['cough_days']));
    }
    if (_is('blood_in_stool', Answer.yes)) {
      out.add(const Suggestion(
          's_blood_stool', TriageLevel.clinicianReview, ['blood_in_stool']));
    }

    if (_is('fever', Answer.yes)) {
      out.add(const Suggestion('s_fever_tests', TriageLevel.routine, ['fever']));
    }
    if (_is('diarrhea', Answer.yes)) {
      out.add(const Suggestion('s_diarrhea_ors', TriageLevel.routine, ['diarrhea']));
    }
    out.add(const Suggestion('s_common_checks', TriageLevel.routine));
    if (_levelOf(out) == TriageLevel.routine) {
      out.add(const Suggestion('s_routine_observe', TriageLevel.routine));
    }

    // Most urgent first; sort is stable so rule order is kept within a level.
    out.sort((a, b) => b.level.index.compareTo(a.level.index));
    return out;
  }

  TriageLevel get level => _levelOf(suggestions());

  static TriageLevel _levelOf(List<Suggestion> s) => s.isEmpty
      ? TriageLevel.routine
      : s.map((e) => e.level).reduce((a, b) => a.index >= b.index ? a : b);

  bool _is(String id, Answer a) => answers[id] == a.name;

  bool _shouldShow(Question q) => q.showIf.entries.every((cond) {
        final expected = cond.value is Answer ? (cond.value as Answer).name : cond.value;
        return answers[cond.key] == expected;
      });

  void reset() {
    answers.clear();
    prefilled.clear();
    _history.clear();
  }
}
