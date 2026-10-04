import 'dart:math';

import 'package:health_core/health_core.dart';

import 'report_store.dart';

/// One feature-phone conversation, keyed by phone number.
class _Session {
  final String lang;
  final String freeText;
  final LocalAIService ai = LocalAIService();
  Question? current;
  DateTime lastActive;

  _Session(this.lang, this.freeText, this.lastActive);
}

/// SMS conversation logic, independent of any HTTP/gateway details so it
/// can be unit-tested and driven from the terminal simulator.
///
/// Flow: first SMS = free description ("3 din se bukhar hai") → we pre-fill
/// what we understood and ask the remaining questions one per SMS, answered
/// by number → final SMS with triage level, suggestions and disclaimer.
///
/// No machine translation is involved: questions come from pre-translated,
/// clinician-reviewable language packs, which is safer for medical text.
class ConversationManager {
  static const sessionTimeout = Duration(minutes: 30);
  static const _maxSuggestionsInSms = 3;

  final ReportStore store;
  final Map<String, _Session> _sessions = {};
  final Random _random = Random.secure();

  ConversationManager(this.store);

  static final RegExp _devanagari = RegExp(r'[ऀ-ॿ]');
  static const _hinglishWords = {
    'bukhar', 'bukhaar', 'khansi', 'khaansi', 'dast', 'hai', 'mujhe', 'bacche',
    'bachche', 'nahi', 'din', 'se', 'ko', 'haan',
  };

  static String detectLanguage(String text) {
    if (_devanagari.hasMatch(text)) return 'hi';
    final words = text.toLowerCase().split(RegExp(r'[^a-z]+'));
    return words.any(_hinglishWords.contains) ? 'hi' : 'en';
  }

  /// Handles one incoming SMS and returns the reply text(s).
  Future<List<String>> handle(String from, String text, {DateTime? now}) async {
    now ??= DateTime.now();
    final msg = text.trim();
    _sessions.removeWhere((_, s) => now!.difference(s.lastActive) > sessionTimeout);

    // Report sent by the Android app ("HAI1 ...").
    if (SmsCodec.isReport(msg)) {
      try {
        final decoded = SmsCodec.decode(msg);
        await store.saveAppReport(from, decoded, now);
        return ['${Strings.of('en', 'sms_report_received')} ${decoded['ref']}'];
      } on Object {
        return ['Could not read report.'];
      }
    }

    final lower = msg.toLowerCase();
    final forcedLang = switch (lower) {
      'hindi' || 'हिंदी' || 'हिन्दी' => 'hi',
      'english' => 'en',
      _ => null,
    };
    var session = _sessions[from];
    final restart = lower == '0' || lower == 'restart' || forcedLang != null;

    if (session == null || restart) {
      final lang = forcedLang ?? session?.lang ?? detectLanguage(msg);
      final description = restart ? '' : msg;
      session = _Session(lang, description, now)..ai.prefillFromText(description);
      _sessions[from] = session;
      return [_ask(session, intro: Strings.of(lang, 'sms_welcome'))];
    }

    session.lastActive = now;
    final q = session.current!;
    final value = parseAnswer(q, msg);
    if (value == null) {
      return [_ask(session, intro: Strings.of(session.lang, 'sms_invalid'))];
    }
    session.ai.answer(q.id, value);
    if (session.ai.nextQuestion() != null) return [_ask(session)];

    _sessions.remove(from);
    return [await _finish(from, session, now)];
  }

  /// Formats the next question with numbered options, e.g.
  /// "Does the patient have fever?\n1=Yes 2=No 3=Not sure".
  String _ask(_Session s, {String? intro}) {
    final q = s.current = s.ai.nextQuestion()!;
    String t(String key) => Strings.of(s.lang, key);
    final help = q.type == QuestionType.yesNo
        ? t('sms_yes_no_help')
        : [
            for (var i = 0; i < q.options.length; i++)
              '${i + 1}=${t('opt_${q.options[i]}')}',
          ].join('\n');
    return [if (intro != null) intro, t('q_${q.id}'), help].join('\n');
  }

  static const _yes = {'1', 'y', 'yes', 'ha', 'haa', 'haan', 'han', 'ji', 'हाँ', 'हां', 'हा'};
  static const _no = {'2', 'n', 'no', 'nahi', 'nahin', 'nai', 'नहीं', 'नही', 'ना'};
  static const _unsure = {
    '3', '?', 'not sure', 'unsure', 'pata nahi', 'pta nahi', 'पता नहीं', 'पक्का नहीं',
  };

  /// Accepts the number or a yes/no word; null if not understood.
  static String? parseAnswer(Question q, String reply) {
    final r = reply.trim().toLowerCase().replaceAll(RegExp(r'[.!।]+$'), '');
    if (q.type == QuestionType.choice) {
      final n = int.tryParse(r);
      return n != null && n >= 1 && n <= q.options.length ? q.options[n - 1] : null;
    }
    if (_unsure.contains(r)) return Answer.unsure.name;
    if (_yes.contains(r)) return Answer.yes.name;
    if (_no.contains(r)) return Answer.no.name;
    return null;
  }

  Future<String> _finish(String from, _Session s, DateTime now) async {
    String t(String key) => Strings.of(s.lang, key);
    final suggestions = s.ai.suggestions();
    final c = Consultation(
      id: '${_random.nextInt(1 << 32).toRadixString(16).padLeft(8, '0')}'
          '-${now.millisecondsSinceEpoch}',
      createdAt: now,
      languageCode: s.lang,
      freeText: s.freeText,
      answers: Map.of(s.ai.answers),
      prefilledIds: s.ai.prefilled.toList(),
      level: s.ai.level,
      suggestions: suggestions,
    );
    await store.saveConsultation(from, c);

    return [
      t('level_${c.level.name}').toUpperCase(),
      for (final (i, sug) in suggestions.take(_maxSuggestionsInSms).indexed)
        '${i + 1}. ${t(sug.id)}',
      t('disclaimer'),
      t('sms_restart_hint'),
    ].join('\n');
  }
}
