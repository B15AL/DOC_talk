import 'package:flutter/material.dart';

import 'package:health_core/health_core.dart';
import '../services/ai_model_service.dart';
import '../services/language_service.dart';
import '../services/stt_service.dart';
import '../services/tts_service.dart';
import '../widgets/voice_button.dart';
import '../widgets/yes_no_buttons.dart';
import 'summary_screen.dart';

/// Step 1: free description (voice or text).
/// Step 2: worker confirms what was understood (AI / keywords) — nothing
///         skips a question without a human tick.
/// Step 3: structured questions for whatever is still unknown.
class ConsultationScreen extends StatefulWidget {
  const ConsultationScreen({super.key});

  @override
  State<ConsultationScreen> createState() => _ConsultationScreenState();
}

class _ConsultationScreenState extends State<ConsultationScreen> {
  final LocalAIService ai = LocalAIService();
  final SttService stt = SttService();
  final TtsService tts = TtsService();
  final TextEditingController descriptionController = TextEditingController();

  _Stage stage = _Stage.describe;
  bool listening = false;
  bool understanding = false;

  /// Findings from the description awaiting confirmation; value = ticked.
  Map<String, String> understood = {};
  Set<String> ticked = {};
  Set<String> fromAiOnly = {};
  Question? currentQuestion;

  String get lang => LanguageService.current.value;

  @override
  void initState() {
    super.initState();
    // Load the model into RAM while the worker is still describing.
    AiModelService.instance.ensureLoaded();
  }

  @override
  void dispose() {
    stt.stop();
    tts.stop();
    descriptionController.dispose();
    super.dispose();
  }

  Future<void> _toggleVoice() async {
    if (listening) {
      await stt.stop();
      setState(() => listening = false);
      return;
    }
    if (!await stt.init()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(LanguageService.t('mic_unavailable'))),
      );
      return;
    }
    setState(() => listening = true);
    await stt.listen(lang, (text) {
      if (mounted) setState(() => descriptionController.text = text);
    });
  }

  Future<void> _startQuestions() async {
    stt.stop();
    final text = descriptionController.text;
    setState(() {
      listening = false;
      understanding = true;
    });
    // Smart AI first (if downloaded), keywords as safety net; keyword
    // matches win on conflict because they're fully predictable.
    final aiService = AiModelService.instance;
    final fromAi = aiService.usable ? await aiService.extract(text) : const <String, String>{};
    if (!mounted) return;
    final fromKeywords = SymptomExtractor.extract(text);
    final merged = {...fromAi, ...fromKeywords};
    if (merged.isEmpty) {
      setState(() {
        understanding = false;
        stage = _Stage.questions;
      });
      _advance();
      return;
    }
    setState(() {
      understanding = false;
      understood = merged;
      ticked = merged.keys.toSet();
      fromAiOnly = merged.keys.where((k) => !fromKeywords.containsKey(k)).toSet();
      stage = _Stage.confirm;
    });
  }

  void _toggle(String id, bool on) {
    setState(() {
      // A follow-up (e.g. fever_days) can't stand without its parent.
      final dependents = LocalAIService.questionBank
          .where((q) => q.showIf.containsKey(id))
          .map((q) => q.id);
      if (on) {
        ticked.add(id);
        final q = LocalAIService.questionBank.firstWhere((q) => q.id == id);
        ticked.addAll(q.showIf.keys.where(understood.containsKey));
      } else {
        ticked.remove(id);
        ticked.removeAll(dependents);
      }
    });
  }

  void _confirmUnderstood() {
    ai.prefill({
      for (final e in understood.entries)
        if (ticked.contains(e.key)) e.key: e.value,
    });
    setState(() => stage = _Stage.questions);
    _advance();
  }

  void _answer(String value) {
    ai.answer(currentQuestion!.id, value);
    _advance();
  }

  void _undo() {
    ai.undo();
    _advance();
  }

  /// Moves to the next question, or to the summary when there are none left.
  /// Navigation happens outside setState.
  void _advance() {
    final next = ai.nextQuestion();
    if (next == null) {
      tts.stop();
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => SummaryScreen(
            ai: ai,
            freeText: descriptionController.text.trim(),
          ),
        ),
      );
      return;
    }
    setState(() => currentQuestion = next);
    tts.speak(lang, LanguageService.t('q_${next.id}'));
  }

  @override
  Widget build(BuildContext context) {
    const t = LanguageService.t;
    return Scaffold(
      appBar: AppBar(
        title: Text(t('new_consultation')),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        actions: [
          if (stage == _Stage.questions && ai.canUndo)
            IconButton(icon: const Icon(Icons.undo), onPressed: _undo),
        ],
      ),
      body: switch (stage) {
        _Stage.describe => _buildDescribe(t),
        _Stage.confirm => _buildConfirm(t),
        _Stage.questions => _buildQuestion(t),
      },
    );
  }

  Widget _buildDescribe(String Function(String) t) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(t('describe_title'),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          TextField(
            controller: descriptionController,
            maxLines: 5,
            decoration: InputDecoration(
              hintText: t('describe_hint'),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              VoiceButton(listening: listening, onPressed: _toggleVoice),
              const SizedBox(width: 12),
              if (listening) Expanded(child: Text(t('listening'))),
            ],
          ),
          const Spacer(),
          if (understanding) ...[
            const LinearProgressIndicator(),
            const SizedBox(height: 8),
            Text(t('understanding'), textAlign: TextAlign.center),
            const SizedBox(height: 12),
          ],
          SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: understanding ? null : _startQuestions,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal,
                foregroundColor: Colors.white,
              ),
              child: Text(t('start_questions'), style: const TextStyle(fontSize: 16)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConfirm(String Function(String) t) {
    final lang = LanguageService.current.value;
    // Show in question-bank order so follow-ups sit under their parent.
    final ids = LocalAIService.questionBank
        .map((q) => q.id)
        .where(understood.containsKey);
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(t('confirm_understood'),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text(t('confirm_understood_hint'),
              style: const TextStyle(color: Colors.black54)),
          const SizedBox(height: 12),
          Expanded(
            child: ListView(
              children: [
                for (final id in ids)
                  CheckboxListTile(
                    value: ticked.contains(id),
                    onChanged: (v) => _toggle(id, v ?? false),
                    title: Text(t('q_$id')),
                    subtitle: Text(
                      fromAiOnly.contains(id)
                          ? '${Strings.answerLabel(lang, understood[id]!)}  •  AI'
                          : Strings.answerLabel(lang, understood[id]!),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: _confirmUnderstood,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal,
                foregroundColor: Colors.white,
              ),
              child: Text(t('continue'), style: const TextStyle(fontSize: 16)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuestion(String Function(String) t) {
    final q = currentQuestion;
    if (q == null) return const SizedBox.shrink();
    return Column(
      children: [
        LinearProgressIndicator(
          value: ai.progress,
          backgroundColor: Colors.teal.shade50,
          color: Colors.teal,
          minHeight: 6,
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (q.isDangerSign)
                  const Icon(Icons.warning_amber, color: Colors.orange, size: 36),
                const SizedBox(height: 12),
                Text(
                  t('q_${q.id}'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w500),
                ),
                IconButton(
                  icon: const Icon(Icons.volume_up, color: Colors.teal),
                  onPressed: () => tts.speak(lang, t('q_${q.id}')),
                ),
              ],
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.grey.shade100,
          child: SafeArea(
            top: false,
            child: AnswerButtons(question: q, onAnswer: _answer),
          ),
        ),
      ],
    );
  }
}

enum _Stage { describe, confirm, questions }
