import 'dart:async';

import 'package:flutter/material.dart';
import 'package:health_core/health_core.dart';

import '../services/ai_model_service.dart';
import '../services/language_service.dart';
import '../services/server_service.dart';
import '../services/stt_service.dart';
import '../services/tts_service.dart';
import 'summary_screen.dart';

enum _Role { bot, user, understood, typing, note }

class _Msg {
  final _Role role;
  final String text;

  /// For [_Role.understood]: findings shown as removable chips.
  final List<String> findingIds;

  /// For bot questions: which question this bubble asks (for undo).
  final String? questionId;

  const _Msg(this.role, this.text, {this.findingIds = const [], this.questionId});
}

/// The whole consultation as one conversation.
///
/// The worker describes the patient in their own words (typed or spoken);
/// on-device AI + keywords pick out symptoms, shown as chips that can be
/// removed. The next question is chosen from what has been understood
/// ([LocalAIService.nextQuestion]) and phrased in context
/// ([QuestionPhrasing]). Answers can be tapped or typed ("haan 5 din se") —
/// typed answers are parsed and also mined for extra symptoms.
///
/// Everything that changes at runtime is announced in the chat: checks
/// added because of a symptom, questions skipped because they were already
/// understood, and treatment advice / triage level changes (shown live in
/// the assessment panel at the top).
class ConsultationScreen extends StatefulWidget {
  const ConsultationScreen({super.key});

  @override
  State<ConsultationScreen> createState() => _ConsultationScreenState();
}

class _ConsultationScreenState extends State<ConsultationScreen> {
  final LocalAIService ai = LocalAIService();
  final AiModelService aiModel = AiModelService.instance;
  final SttService stt = SttService();
  final TtsService tts = TtsService();
  final TextEditingController input = TextEditingController();
  final ScrollController scroll = ScrollController();

  final List<_Msg> messages = [];
  final List<String> userTexts = [];

  /// Findings that only the AI model (not keywords) picked up.
  final Set<String> fromAiOnly = {};

  /// Index of the question bubble for each tapped/typed answer (for undo).
  final List<int> answeredAt = [];

  Question? current;
  bool describing = true;
  bool busy = false;
  bool listening = false;
  bool finished = false;
  String? lastAnswer;
  int turn = 0;

  // Last reported state, to announce what changed.
  Set<String> _pending = {};
  TriageLevel _level = TriageLevel.routine;
  Set<String> _advice = {};
  bool panelOpen = false;

  /// Generic advice that is always present; not announced.
  static const _quietAdvice = {'s_common_checks', 's_routine_observe'};

  String get lang => LanguageService.current.value;
  String t(String key) => LanguageService.t(key);

  @override
  void initState() {
    super.initState();
    // Load the model into RAM while the worker is still typing.
    aiModel.ensureLoaded();
    _syncSilently();
    _bot(t('chat_start'), speak: true);
  }

  void _syncSilently() {
    _pending = ai.pendingIds;
    _level = ai.level;
    _advice = ai.suggestions().map((s) => s.id).toSet();
  }

  void _note(String text) => messages.add(_Msg(_Role.note, text));

  /// Announces checks added / questions skipped / advice changed since the
  /// last call. Call after every change to the answers.
  void _reportChanges() {
    final now = ai.pendingIds;
    final added = now.difference(_pending);
    final skipped = _pending
        .difference(now)
        .where((id) => ai.prefilled.contains(id) && id != current?.id);

    // Group added questions by the symptom that triggered them.
    final byReason = <String, int>{};
    for (final id in added) {
      final q = LocalAIService.questionBank.firstWhere((q) => q.id == id);
      if (q.showIf.isNotEmpty) byReason.update(q.showIf.keys.first, (n) => n + 1, ifAbsent: () => 1);
    }

    final suggestions = ai.suggestions();
    final level = ai.level;
    final newAdvice = suggestions
        .where((s) => !_advice.contains(s.id) && !_quietAdvice.contains(s.id))
        .take(2);

    setState(() {
      if (skipped.isNotEmpty) {
        _note(t('note_skipped').replaceAll('{n}', '${skipped.length}'));
      }
      byReason.forEach((reason, n) {
        if (Strings.has(lang, 'note_added_$reason')) {
          _note(t('note_added_$reason').replaceAll('{n}', '$n'));
        }
      });
      if (level != _level) {
        _note(t('note_level').replaceAll('{level}', t('level_${level.name}')));
      }
      for (final s in newAdvice) {
        _note(t('note_advice').replaceAll('{text}', _firstSentence(t(s.id))));
      }
    });
    _pending = now;
    _level = level;
    _advice = suggestions.map((s) => s.id).toSet();
  }

  static String _firstSentence(String text) {
    final m = RegExp(r'^.*?[.।](\s|$)').firstMatch(text);
    return (m?.group(0) ?? text).trim();
  }

  @override
  void dispose() {
    stt.stop();
    tts.stop();
    input.dispose();
    scroll.dispose();
    super.dispose();
  }

  // ---- Conversation --------------------------------------------------------

  void _bot(String text, {String? questionId, bool speak = false}) {
    setState(() => messages.add(_Msg(_Role.bot, text, questionId: questionId)));
    if (speak) tts.speak(lang, text);
    _scrollDown();
  }

  Future<void> _send() async {
    final text = input.text.trim();
    if (text.isEmpty || busy || finished) return;
    input.clear();
    if (listening) await _toggleVoice();
    userTexts.add(text);
    setState(() => messages.add(_Msg(_Role.user, text)));
    _scrollDown();

    if (describing) {
      final found = await _understand(text);
      if (!mounted) return;
      describing = false;
      if (found.isEmpty) _bot(t('chat_nothing'));
      _askNext();
      return;
    }

    final q = current!;
    var value = AnswerParser.parse(q, text);
    final found = await _understand(text, also: true);
    if (!mounted) return;
    // e.g. "fever?" answered with "bukhar 3 din se": the finding is the answer.
    value ??= _consumeFinding(q.id);
    if (value != null) {
      _answer(value);
    } else if (found.isEmpty) {
      _bot(t('chat_not_understood'));
    } else {
      _askNext(); // new info may change what is most important to ask
    }
  }

  /// Runs AI (if downloaded) + keywords, pre-fills what's new and shows it
  /// as removable chips. Returns the new finding ids.
  Future<List<String>> _understand(String text, {bool also = false}) async {
    setState(() {
      busy = true;
      messages.add(const _Msg(_Role.typing, ''));
    });
    _scrollDown();
    // On-device model first; with internet and no local model, the server's.
    final server = ServerService.instance;
    final fromAi = aiModel.usable
        ? await aiModel.extract(text)
        : (server.configured ? await server.understand(text) : const <String, String>{});
    if (!mounted) return const [];
    final fromKeywords = SymptomExtractor.extract(text);

    final before = ai.answers.keys.toSet();
    ai.prefill({...fromAi, ...fromKeywords});
    final added = ai.answers.keys.where((id) => !before.contains(id)).toList();
    fromAiOnly.addAll(added.where((id) => !fromKeywords.containsKey(id)));

    setState(() {
      busy = false;
      messages.removeWhere((m) => m.role == _Role.typing);
      if (added.isNotEmpty) {
        messages.add(_Msg(
          _Role.understood,
          t(also ? 'chat_also_understood' : 'chat_understood'),
          findingIds: added,
        ));
      }
    });
    if (added.isNotEmpty) _reportChanges();
    _scrollDown();
    return added;
  }

  /// If the reply was understood as the current question's own finding,
  /// take it as the answer instead of a pre-fill.
  String? _consumeFinding(String questionId) {
    if (!ai.prefilled.contains(questionId)) return null;
    final value = ai.answers.remove(questionId);
    ai.prefilled.remove(questionId);
    return value;
  }

  void _tap(String value) {
    if (busy || finished || current == null) return;
    final q = current!;
    final label = q.type == QuestionType.choice ? t('opt_$value') : t(value);
    setState(() => messages.add(_Msg(_Role.user, label)));
    _answer(value);
  }

  void _answer(String value) {
    final q = current!;
    answeredAt.add(messages.lastIndexWhere((m) => m.questionId == q.id));
    ai.answer(q.id, value);
    lastAnswer = value;
    _reportChanges();
    _askNext();
  }

  void _askNext() {
    final next = ai.nextQuestion();
    if (next == null) {
      _finish();
      return;
    }
    current = next;
    final text = QuestionPhrasing.phrase(lang, next, ai,
        previousAnswer: lastAnswer, turn: turn++);
    lastAnswer = null;
    _bot(text, questionId: next.id, speak: true);
  }

  void _finish() {
    setState(() {
      finished = true;
      current = null;
    });
    _bot(t('chat_done'));
    tts.stop();
    Timer(const Duration(milliseconds: 700), () {
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => SummaryScreen(ai: ai, freeText: userTexts.join(' / ')),
        ),
      );
    });
  }

  void _undo() {
    if (answeredAt.isEmpty || busy || finished) return;
    final from = answeredAt.removeLast();
    ai.undo();
    _syncSilently();
    setState(() {
      // Keep "understood" chips: those findings are still in effect.
      for (var i = messages.length - 1; i >= from && i >= 0; i--) {
        if (messages[i].role != _Role.understood) messages.removeAt(i);
      }
    });
    lastAnswer = null;
    _askNext();
  }

  void _removeFinding(String id) {
    if (finished || busy) return;
    setState(() => ai.removePrefilled(id));
    _bot(t('chat_removed'));
    _reportChanges();
    // "How many days of fever?" makes no sense once "fever" is removed.
    final q = current;
    if (q != null && q.showIf.keys.any((k) => !ai.answers.containsKey(k))) _askNext();
  }

  Future<void> _toggleVoice() async {
    if (listening) {
      await stt.stop();
      if (mounted) setState(() => listening = false);
      return;
    }
    if (!await stt.init()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(t('mic_unavailable'))));
      return;
    }
    await tts.stop();
    setState(() => listening = true);
    await stt.listen(lang, (text) {
      if (!mounted) return;
      input.text = text;
      input.selection = TextSelection.collapsed(offset: text.length);
    });
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (scroll.hasClients) {
        scroll.animateTo(scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  // ---- UI ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(t('new_consultation')),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        actions: [
          if (aiModel.usable || ServerService.instance.configured)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Icon(aiModel.usable ? Icons.auto_awesome : Icons.cloud_outlined, size: 20),
            ),
          if (answeredAt.isNotEmpty && !finished)
            IconButton(icon: const Icon(Icons.undo), onPressed: _undo),
        ],
      ),
      body: Column(
        children: [
          if (!describing) ...[
            LinearProgressIndicator(
              value: ai.progress,
              backgroundColor: Colors.teal.shade50,
              color: Colors.teal,
              minHeight: 4,
            ),
            _assessmentPanel(),
          ],
          Expanded(
            child: ListView.builder(
              controller: scroll,
              padding: const EdgeInsets.all(12),
              itemCount: messages.length,
              itemBuilder: (_, i) => _bubble(messages[i]),
            ),
          ),
          if (!finished) _inputArea(),
        ],
      ),
    );
  }

  Widget _bubble(_Msg m) {
    final maxWidth = MediaQuery.of(context).size.width * 0.8;
    switch (m.role) {
      case _Role.typing:
        return Align(
          alignment: Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.teal.shade50,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                    width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(width: 8),
                Text(t('understanding')),
              ],
            ),
          ),
        );
      case _Role.note:
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              constraints: BoxConstraints(maxWidth: maxWidth),
              decoration: BoxDecoration(
                color: Colors.blueGrey.shade50,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(m.text,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, color: Colors.black87)),
            ),
          ),
        );
      case _Role.understood:
        final live = m.findingIds.where(ai.prefilled.contains).toList();
        if (live.isEmpty) return const SizedBox.shrink();
        return Align(
          alignment: Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            constraints: BoxConstraints(maxWidth: maxWidth),
            decoration: BoxDecoration(
              color: Colors.amber.shade50,
              border: Border.all(color: Colors.amber.shade300),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(m.text, style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [for (final id in live) _findingChip(id)],
                ),
                const SizedBox(height: 4),
                Text(t('chat_understood_hint'),
                    style: const TextStyle(fontSize: 12, color: Colors.black54)),
              ],
            ),
          ),
        );
      case _Role.bot:
      case _Role.user:
        final isBot = m.role == _Role.bot;
        return Align(
          alignment: isBot ? Alignment.centerLeft : Alignment.centerRight,
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            constraints: BoxConstraints(maxWidth: maxWidth),
            decoration: BoxDecoration(
              color: isBot ? Colors.teal.shade50 : Colors.blue.shade100,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(isBot ? 4 : 16),
                topRight: Radius.circular(isBot ? 16 : 4),
                bottomLeft: const Radius.circular(16),
                bottomRight: const Radius.circular(16),
              ),
            ),
            child: Text(m.text, style: const TextStyle(fontSize: 16)),
          ),
        );
    }
  }

  /// Triage level + current advice, updated after every answer.
  Widget _assessmentPanel() {
    final suggestions = ai.suggestions();
    final level = ai.level;
    final color = switch (level) {
      TriageLevel.routine => Colors.green,
      TriageLevel.clinicianReview => Colors.orange,
      TriageLevel.urgentReferral => Colors.red,
    };
    return Material(
      color: color.withValues(alpha: 0.12),
      child: InkWell(
        onTap: () => setState(() => panelOpen = !panelOpen),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.monitor_heart, color: color, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${t('assessment_title')}: ${t('level_${level.name}')}',
                      style: TextStyle(fontWeight: FontWeight.bold, color: color),
                    ),
                  ),
                  Text('${suggestions.length}'),
                  Icon(panelOpen ? Icons.expand_less : Icons.expand_more),
                ],
              ),
              if (panelOpen)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 220),
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final s in suggestions)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text('• ${t(s.id)}', style: const TextStyle(fontSize: 13)),
                        ),
                      const SizedBox(height: 6),
                      Text(t('disclaimer'),
                          style: const TextStyle(fontSize: 11, color: Colors.redAccent)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _findingChip(String id) {
    final value = ai.answers[id]!;
    final label = value == 'yes'
        ? t('label_$id')
        : '${t('label_$id')}: ${Strings.answerLabel(lang, value)}';
    return InputChip(
      avatar: fromAiOnly.contains(id)
          ? const Icon(Icons.auto_awesome, size: 16, color: Colors.teal)
          : null,
      label: Text(label),
      onDeleted: () => _removeFinding(id),
    );
  }

  Widget _inputArea() {
    final q = current;
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, -2)),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (describing)
              Align(
                alignment: Alignment.centerLeft,
                child: ActionChip(
                  label: Text(t('chat_skip_describe')),
                  onPressed: busy
                      ? null
                      : () {
                          describing = false;
                          _askNext();
                        },
                ),
              )
            else if (q != null)
              _quickReplies(q),
            Row(
              children: [
                IconButton(
                  icon: Icon(listening ? Icons.stop_circle : Icons.mic),
                  color: listening ? Colors.red : Colors.teal,
                  onPressed: busy ? null : _toggleVoice,
                ),
                Expanded(
                  child: TextField(
                    controller: input,
                    enabled: !busy,
                    minLines: 1,
                    maxLines: 3,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    decoration: InputDecoration(
                      hintText: listening
                          ? t('listening')
                          : (describing ? t('describe_hint') : t('chat_input_hint')),
                      isDense: true,
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send),
                  color: Colors.teal,
                  onPressed: busy ? null : _send,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _quickReplies(Question q) {
    final options = q.type == QuestionType.choice
        ? [for (final o in q.options) (o, t('opt_$o'), Colors.teal)]
        : [
            (Answer.yes.name, t('yes'), Colors.green),
            (Answer.no.name, t('no'), Colors.red.shade400),
            (Answer.unsure.name, t('unsure'), Colors.orange),
          ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        alignment: WrapAlignment.center,
        children: [
          for (final (value, label, color) in options)
            ElevatedButton(
              onPressed: busy ? null : () => _tap(value),
              style: ElevatedButton.styleFrom(
                backgroundColor: color,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
              child: Text(label, style: const TextStyle(fontSize: 16)),
            ),
        ],
      ),
    );
  }
}
