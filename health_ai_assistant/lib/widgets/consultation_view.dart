import 'package:flutter/material.dart';
import 'package:health_core/health_core.dart';

import '../services/language_service.dart';

const Map<TriageLevel, Color> levelColors = {
  TriageLevel.routine: Colors.green,
  TriageLevel.clinicianReview: Colors.orange,
  TriageLevel.urgentReferral: Colors.red,
};

/// Read-only view of a consultation: triage banner, disclaimer, suggestions
/// with reasons, and the answers. Used by the summary and history screens.
class ConsultationView extends StatelessWidget {
  final Consultation consultation;

  const ConsultationView({super.key, required this.consultation});

  @override
  Widget build(BuildContext context) {
    const t = LanguageService.t;
    final c = consultation;
    final answered =
        LocalAIService.questionBank.where((q) => c.answers.containsKey(q.id)).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: levelColors[c.level],
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            t('level_${c.level.name}'),
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.red.shade50,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(t('disclaimer'),
              style: const TextStyle(fontSize: 14, color: Colors.redAccent)),
        ),
        const SizedBox(height: 24),
        Text(t('suggestions_title'),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        for (final s in c.suggestions) _suggestionCard(s),
        const SizedBox(height: 24),
        Text(t('symptom_summary'),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (c.freeText.isNotEmpty) ...[
                  Text('"${c.freeText}"',
                      style: const TextStyle(fontStyle: FontStyle.italic)),
                  const Divider(),
                ],
                for (final q in answered) _answerRow(q.id),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _answerText(String questionId) => Strings.answerLabel(
      LanguageService.current.value, consultation.answers[questionId]!);

  Widget _answerRow(String questionId) {
    const t = LanguageService.t;
    final fromText = consultation.prefilledIds.contains(questionId);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t('q_$questionId'),
              style: const TextStyle(fontSize: 13, color: Colors.grey)),
          Text(
            fromText
                ? '${_answerText(questionId)}  (${t('from_description')})'
                : _answerText(questionId),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Widget _suggestionCard(Suggestion s) {
    const t = LanguageService.t;
    final color = levelColors[s.level]!;
    final reasons = s.reasonIds
        .where(consultation.answers.containsKey)
        .map((id) => '${t('q_$id')} → ${_answerText(id)}');
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t(s.id), style: const TextStyle(fontSize: 15)),
            if (reasons.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '${t('because')}: ${reasons.join('; ')}',
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Full-width teal action button used at the bottom of screens.
class PrimaryButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  const PrimaryButton(
      {super.key, required this.label, required this.icon, required this.onPressed});

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 52,
        child: ElevatedButton.icon(
          icon: Icon(icon),
          label: Text(label, style: const TextStyle(fontSize: 16)),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.teal,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: onPressed,
        ),
      );
}
