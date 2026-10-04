import 'consultation_model.dart';
import 'local_ai_service.dart';

/// Compact, PII-free SMS encoding of a consultation, e.g.
///   "HAI1 a1b2c3 U A1 D1N D2N D3N D4N D5Y"
/// Fits easily in one 160-char SMS and is still readable by a clinician.
/// The server decodes it with [decode].
class SmsCodec {
  static const _version = 'HAI1';

  static const Map<String, String> _questionCodes = {
    'age_group': 'A',
    'ds_unconscious': 'D1',
    'ds_convulsions': 'D2',
    'ds_cannot_drink': 'D3',
    'ds_vomits_everything': 'D4',
    'ds_breathing': 'D5',
    'fever': 'F',
    'fever_days': 'FD',
    'cough': 'C',
    'cough_days': 'CD',
    'diarrhea': 'DI',
    'blood_in_stool': 'BS',
    'fever_stiff_neck': 'SN',
    'fever_rash': 'RA',
    'malaria_test': 'MT',
    'cough_fast_breathing': 'FB',
    'chest_indrawing': 'CI',
    'tb_symptoms': 'TB',
    'dehyd_sunken_eyes': 'SE',
    'dehyd_thirsty': 'TH',
    'dehyd_skin_pinch': 'SP',
    'dehyd_restless': 'RS',
  };

  static const Map<String, String> _valueCodes = {
    'yes': 'Y',
    'no': 'N',
    'unsure': 'U',
    'age_infant': '0',
    'age_child': '1',
    'age_older': '2',
    'd_1_2': '1',
    'd_3_6': '3',
    'd_7_plus': '7',
    'c_lt_14': '1',
    'c_14_plus': '14',
    'rdt_positive': '+',
    'rdt_negative': '-',
    'rdt_not_done': '0',
    'pinch_normal': '1',
    'pinch_slow': '2',
    'pinch_very_slow': '3',
  };

  static const Map<TriageLevel, String> _levelCodes = {
    TriageLevel.routine: 'R',
    TriageLevel.clinicianReview: 'C',
    TriageLevel.urgentReferral: 'U',
  };

  /// True if [sms] looks like an app-generated report rather than a person
  /// typing.
  static bool isReport(String sms) => sms.trim().startsWith('$_version ');

  static String encode(Consultation c) {
    final parts = <String>[
      _version,
      c.id.substring(0, 6),
      _levelCodes[c.level]!,
    ];
    // Iterate in a fixed order so the same answers always give the same SMS.
    _questionCodes.forEach((questionId, code) {
      final value = c.answers[questionId];
      if (value != null) parts.add('$code${_valueCodes[value] ?? '?'}');
    });
    return parts.join(' ');
  }

  /// Inverse of [encode]: returns question id -> value, plus 'level' and 'ref'.
  /// Longer codes are tried first so "FD3" isn't read as "F" + "D3".
  static Map<String, String> decode(String sms) {
    final tokens = sms.trim().split(RegExp(r'\s+'));
    if (tokens.length < 3 || tokens[0] != _version) {
      throw const FormatException('Not a HAI1 message');
    }
    final out = <String, String>{
      'ref': tokens[1],
      'level': _levelCodes.entries.firstWhere((e) => e.value == tokens[2]).key.name,
    };
    final codes = _questionCodes.entries.toList()
      ..sort((a, b) => b.value.length.compareTo(a.value.length));
    for (final token in tokens.skip(3)) {
      for (final q in codes) {
        if (!token.startsWith(q.value)) continue;
        final v = token.substring(q.value.length);
        final match = _valueCodes.entries.where((e) =>
            e.value == v && _validValueFor(q.key, e.key));
        if (match.isEmpty) continue;
        out[q.key] = match.first.key;
        break;
      }
    }
    return out;
  }

  static bool _validValueFor(String questionId, String value) {
    final q = LocalAIService.questionBank.firstWhere((q) => q.id == questionId);
    return q.type == QuestionType.choice
        ? q.options.contains(value)
        : const ['yes', 'no', 'unsure'].contains(value);
  }
}
