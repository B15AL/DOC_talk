import 'package:flutter/material.dart';

import 'package:health_core/health_core.dart';
import '../services/language_service.dart';

/// Answer area for the current question: Yes / No / Not sure for yes-no
/// questions, one big button per option for choice questions.
class AnswerButtons extends StatelessWidget {
  final Question question;
  final void Function(String value) onAnswer;

  const AnswerButtons({super.key, required this.question, required this.onAnswer});

  @override
  Widget build(BuildContext context) {
    const t = LanguageService.t;
    if (question.type == QuestionType.choice) {
      return Column(
        children: [
          for (final opt in question.options)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _bigButton(t('opt_$opt'), Colors.teal, () => onAnswer(opt)),
            ),
        ],
      );
    }
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _bigButton(t('yes'), Colors.green, () => onAnswer(Answer.yes.name)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _bigButton(
                  t('no'), Colors.red.shade400, () => onAnswer(Answer.no.name)),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: () => onAnswer(Answer.unsure.name),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              side: const BorderSide(color: Colors.orange),
            ),
            child: Text(t('unsure'),
                style: const TextStyle(fontSize: 15, color: Colors.orange)),
          ),
        ),
      ],
    );
  }

  Widget _bigButton(String label, Color color, VoidCallback onPressed) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        child: Text(label, style: const TextStyle(fontSize: 17)),
      ),
    );
  }
}
