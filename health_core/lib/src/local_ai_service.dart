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
    Question(id: 'fever_stiff_neck', showIf: {'fever': Answer.yes}, isAssessment: true),
    Question(id: 'fever_rash', showIf: {'fever': Answer.yes}, isAssessment: true),
    Question(
      id: 'malaria_test',
      type: QuestionType.choice,
      options: ['rdt_positive', 'rdt_negative', 'rdt_not_done'],
      showIf: {'fever': Answer.yes},
      isAssessment: true,
    ),
    Question(id: 'cough'),
    Question(
      id: 'cough_days',
      type: QuestionType.choice,
      options: ['c_lt_14', 'c_14_plus'],
      showIf: {'cough': Answer.yes},
    ),
    Question(id: 'cough_fast_breathing', showIf: {'cough': Answer.yes}, isAssessment: true),
    Question(id: 'chest_indrawing', showIf: {'cough': Answer.yes}, isAssessment: true),
    Question(id: 'tb_symptoms', showIf: {'cough_days': 'c_14_plus'}, isAssessment: true),
    Question(id: 'diarrhea'),
    Question(id: 'blood_in_stool', showIf: {'diarrhea': Answer.yes}),
    // WHO IMCI dehydration classification.
    Question(id: 'dehyd_sunken_eyes', showIf: {'diarrhea': Answer.yes}, isAssessment: true),
    Question(id: 'dehyd_thirsty', showIf: {'diarrhea': Answer.yes}, isAssessment: true),
    Question(
      id: 'dehyd_skin_pinch',
      type: QuestionType.choice,
      options: ['pinch_normal', 'pinch_slow', 'pinch_very_slow'],
      showIf: {'diarrhea': Answer.yes},
      isAssessment: true,
    ),
    Question(id: 'dehyd_restless', showIf: {'diarrhea': Answer.yes}, isAssessment: true),
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

  /// Removes an understood finding (and its follow-ups) so it gets asked
  /// again — used when the worker taps ✕ on something the AI got wrong.
  void removePrefilled(String questionId) {
    if (!prefilled.contains(questionId)) return;
    answers.remove(questionId);
    prefilled.remove(questionId);
    for (final q in questionBank.where((q) => q.showIf.containsKey(questionId))) {
      if (prefilled.contains(q.id)) removePrefilled(q.id);
    }
  }

  /// Questions that still apply and are unanswered — grows when a symptom
  /// is reported (checks get added), shrinks as things are understood.
  Set<String> get pendingIds => {
        for (final q in questionBank)
          if (!answers.containsKey(q.id) && _shouldShow(q)) q.id,
      };

  /// Danger signs most relevant to each symptom (WHO IMCI): asked first when
  /// that symptom has been mentioned.
  static const Map<String, List<String>> relatedDangerSigns = {
    'fever': ['ds_convulsions', 'ds_unconscious'],
    'cough': ['ds_breathing'],
    'diarrhea': ['ds_cannot_drink', 'ds_vomits_everything'],
  };

  /// Symptoms reported so far (from the description or answers).
  Iterable<String> get reportedSymptoms =>
      relatedDangerSigns.keys.where((s) => _is(s, Answer.yes));

  /// Next question, chosen from what has been understood so far:
  ///  1. patient age (changes every rule),
  ///  2. follow-ups on what was just mentioned ("fever -> how many days?"),
  ///  3. danger signs — those related to reported symptoms first, but all
  ///     of them are always asked,
  ///  4. checks added because of a reported symptom (dehydration, breathing,
  ///     malaria test, ...),
  ///  5. remaining symptoms.
  /// Returns null when done, or as soon as a danger sign is confirmed.
  Question? nextQuestion() {
    if (hasDangerSign) return null;
    final pending =
        questionBank.where((q) => !answers.containsKey(q.id) && _shouldShow(q));
    if (pending.isEmpty) return null;
    final relevant = {for (final s in reportedSymptoms) ...relatedDangerSigns[s]!};
    int priority(Question q) {
      final index = questionBank.indexOf(q);
      if (q.id == 'age_group') return 0;
      if (q.isAssessment) return 350 + index; // added checks, after danger signs
      if (q.showIf.isNotEmpty) return 100 + index;
      if (q.isDangerSign) return (relevant.contains(q.id) ? 200 : 300) + index;
      return 400 + index;
    }

    return pending.reduce((a, b) => priority(a) <= priority(b) ? a : b);
  }

  /// The reported symptom that made [q] come up now, if any — used to
  /// phrase the question in context ("Since there is fever, ...").
  String? reasonFor(Question q) {
    if (q.showIf.isNotEmpty) return q.showIf.keys.first;
    for (final s in reportedSymptoms) {
      if (relatedDangerSigns[s]!.contains(q.id)) return s;
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

  /// WHO IMCI-style rules. Treatment advice comes only from here — never
  /// from the language model — and always says "as per protocol".
  List<Suggestion> suggestions() {
    final out = <Suggestion>[];
    const yes = Answer.yes;
    void add(String id, TriageLevel level, List<String> reasons) =>
        out.add(Suggestion(id, level, reasons));
    List<String> which(Iterable<String> ids, Answer a) => ids.where((id) => _is(id, a)).toList();

    // --- General danger signs --------------------------------------------
    final dangerYes = which(dangerSignIds, yes);
    if (dangerYes.isNotEmpty) add('s_urgent_danger', TriageLevel.urgentReferral, dangerYes);
    if (answers['age_group'] == 'age_infant' && _is('fever', yes)) {
      add('s_infant_fever', TriageLevel.urgentReferral, ['age_group', 'fever']);
    }
    // "Not sure" is treated cautiously, never as "no".
    final dangerUnsure = which(dangerSignIds, Answer.unsure);
    if (dangerUnsure.isNotEmpty) {
      add('s_unsure_danger', TriageLevel.clinicianReview, dangerUnsure);
    }
    final checksUnsure = which(
        questionBank.where((q) => q.isAssessment && q.type == QuestionType.yesNo).map((q) => q.id),
        Answer.unsure);
    if (checksUnsure.isNotEmpty) {
      add('s_unsure_check', TriageLevel.clinicianReview, checksUnsure);
    }

    // --- Fever -------------------------------------------------------------
    if (_is('fever_stiff_neck', yes)) {
      add('s_stiff_neck', TriageLevel.urgentReferral, ['fever', 'fever_stiff_neck']);
    }
    if (answers['fever_days'] == 'd_7_plus') {
      add('s_fever_long', TriageLevel.clinicianReview, ['fever_days']);
    }
    if (_is('fever_rash', yes)) add('s_measles', TriageLevel.clinicianReview, ['fever_rash']);
    if (_is('fever', yes)) {
      switch (answers['malaria_test']) {
        case 'rdt_positive':
          add('s_malaria_positive', TriageLevel.clinicianReview, ['malaria_test']);
        case 'rdt_negative':
          add('s_malaria_negative', TriageLevel.routine, ['malaria_test']);
        default:
          add('s_fever_tests', TriageLevel.routine, ['fever']);
      }
      add('s_fever_care', TriageLevel.routine, ['fever']);
    }

    // --- Cough / breathing -------------------------------------------------
    if (_is('chest_indrawing', yes)) {
      add('s_severe_pneumonia', TriageLevel.urgentReferral, ['chest_indrawing']);
    } else if (_is('cough_fast_breathing', yes)) {
      if (answers['age_group'] == 'age_infant') {
        add('s_infant_fast_breathing', TriageLevel.urgentReferral,
            ['age_group', 'cough_fast_breathing']);
      } else {
        add('s_pneumonia', TriageLevel.clinicianReview, ['cough_fast_breathing']);
      }
    } else if (_is('cough', yes) && _is('cough_fast_breathing', Answer.no)) {
      add('s_cough_home', TriageLevel.routine, ['cough_fast_breathing']);
    }
    if (answers['cough_days'] == 'c_14_plus') {
      add('s_cough_tb', TriageLevel.clinicianReview,
          ['cough_days', if (_is('tb_symptoms', yes)) 'tb_symptoms']);
    }

    // --- Diarrhoea: WHO IMCI dehydration classification --------------------
    if (_is('blood_in_stool', yes)) {
      add('s_blood_stool', TriageLevel.clinicianReview, ['blood_in_stool']);
    }
    if (_is('diarrhea', yes)) {
      final pinch = answers['dehyd_skin_pinch'];
      final severe = [
        if (_is('ds_unconscious', yes)) 'ds_unconscious',
        if (_is('dehyd_sunken_eyes', yes)) 'dehyd_sunken_eyes',
        if (_is('ds_cannot_drink', yes)) 'ds_cannot_drink',
        if (pinch == 'pinch_very_slow') 'dehyd_skin_pinch',
      ];
      final some = [
        if (_is('dehyd_restless', yes)) 'dehyd_restless',
        if (_is('dehyd_sunken_eyes', yes)) 'dehyd_sunken_eyes',
        if (_is('dehyd_thirsty', yes)) 'dehyd_thirsty',
        if (pinch == 'pinch_slow' || pinch == 'pinch_very_slow') 'dehyd_skin_pinch',
      ];
      if (severe.length >= 2) {
        add('s_severe_dehydration', TriageLevel.urgentReferral, severe);
      } else if (some.length >= 2) {
        add('s_some_dehydration', TriageLevel.clinicianReview, some);
      } else {
        add('s_diarrhea_ors', TriageLevel.routine, ['diarrhea']);
      }
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
