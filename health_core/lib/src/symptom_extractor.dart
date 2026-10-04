/// Turns a free-text / voice description into pre-filled answers.
///
/// This is the slot where a small on-device LLM can plug in later: it only
/// has to return the same `Map<questionId, value>`. The keyword version runs
/// on any phone, needs no download, and is predictable.
///
/// Safety rules:
///  * Only *positive* findings are pre-filled; "no" is never assumed.
///  * Clauses containing a negation ("bukhar nahi hai") are ignored.
///  * Danger signs are never pre-filled — they are always asked explicitly.
class SymptomExtractor {
  static const Map<String, List<String>> _keywords = {
    'fever': [
      'fever', 'bukhar', 'bukhaar', 'बुखार', 'ज्वर', 'badan garam', 'body hot',
      'body is hot', 'is hot', 'बदन गरम', 'शरीर गरम',
    ],
    'cough': ['cough', 'khansi', 'khaansi', 'खांसी', 'खाँसी'],
    'diarrhea': [
      'diarrhea', 'diarrhoea', 'loose motion', 'loose stool', 'dast', 'दस्त',
      'patli tatti', 'patli potty', 'पतली टट्टी', 'टट्टी पतली', 'पतले दस्त',
    ],
    'blood_in_stool': [
      'blood in stool', 'bloody stool', 'tatti mein khoon', 'potty mein khoon',
      'मल में खून', 'टट्टी में खून', 'दस्त में खून',
    ],
  };

  static const List<String> _negations = [
    'no', 'not', 'nahi', 'nahin', 'nai', 'na', 'नहीं', 'नही', 'ना', 'न',
  ];

  static const Map<String, int> _numberWords = {
    'one': 1, 'two': 2, 'three': 3, 'four': 4, 'five': 5, 'six': 6, 'seven': 7,
    'ek': 1, 'do': 2, 'teen': 3, 'char': 4, 'chaar': 4, 'paanch': 5, 'panch': 5,
    'chhe': 6, 'che': 6, 'saat': 7,
    'एक': 1, 'दो': 2, 'तीन': 3, 'चार': 4, 'पांच': 5, 'पाँच': 5, 'छह': 6, 'छः': 6,
    'सात': 7,
  };

  static final RegExp _clauseSplit =
      RegExp(r'[,.;!?।\n]|\s(?:and|aur|और|or|ya|या)\s', caseSensitive: false);
  static final RegExp _duration = RegExp(
    r'(\d+|[^\s\d]+)\s*(days?|din|दिन|weeks?|hafte|hafta|हफ़्ते|हफ्ते|हफ़्ता|हफ्ता|months?|mahine|mahina|महीने|महीना)',
    caseSensitive: false,
  );

  /// Durations without a number ("since yesterday", "pichle hafte se").
  static const Map<String, int> _durationPhrases = {
    'yesterday': 1, 'kal se': 1, 'कल से': 1, 'today': 1, 'aaj se': 1, 'आज से': 1,
    'last week': 7, 'a week': 7, 'pichle hafte': 7, 'ek hafte': 7, 'पिछले हफ्ते': 7,
    'पिछले हफ़्ते': 7, 'a month': 30, 'pichle mahine': 30, 'ek mahine': 30,
    'पिछले महीने': 30,
  };

  static Map<String, String> extract(String text) {
    final result = <String, String>{};
    for (final rawClause in text.toLowerCase().split(_clauseSplit)) {
      final clause = rawClause.trim();
      if (clause.isEmpty || _hasNegation(clause)) continue;

      final days = _durationInDays(clause);
      _keywords.forEach((symptomId, words) {
        if (!words.any(clause.contains)) return;
        result[symptomId] = 'yes';
        if (days == null) return;
        if (symptomId == 'fever') {
          result['fever_days'] = days >= 7 ? 'd_7_plus' : (days >= 3 ? 'd_3_6' : 'd_1_2');
        } else if (symptomId == 'cough') {
          result['cough_days'] = days >= 14 ? 'c_14_plus' : 'c_lt_14';
        }
      });
    }
    return result;
  }

  static bool _hasNegation(String clause) =>
      clause.split(RegExp(r'\s+')).any(_negations.contains);

  static int? _durationInDays(String clause) {
    for (final match in _duration.allMatches(clause)) {
      final n = int.tryParse(match.group(1)!) ?? _numberWords[match.group(1)!];
      if (n == null) continue; // e.g. "pichle hafte" — try phrases below
      final unit = match.group(2)!;
      if (unit.startsWith('week') || unit.startsWith('haft') || unit.startsWith('हफ')) return n * 7;
      if (unit.startsWith('month') || unit.startsWith('mahin') || unit.startsWith('मही')) return n * 30;
      return n;
    }
    for (final p in _durationPhrases.entries) {
      if (clause.contains(p.key)) return p.value;
    }
    return null;
  }

}
