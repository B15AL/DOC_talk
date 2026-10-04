import 'dart:math';

import 'package:flutter/material.dart';
import 'package:health_core/health_core.dart';

import '../services/language_service.dart';
import '../services/server_service.dart';
import '../services/sms_service.dart';
import '../services/storage_service.dart';
import '../widgets/consultation_view.dart';

class SummaryScreen extends StatefulWidget {
  final LocalAIService ai;
  final String freeText;

  const SummaryScreen({super.key, required this.ai, required this.freeText});

  @override
  State<SummaryScreen> createState() => _SummaryScreenState();
}

class _SummaryScreenState extends State<SummaryScreen> {
  late Consultation consultation = Consultation(
    id: _newId(),
    createdAt: DateTime.now(),
    languageCode: LanguageService.current.value,
    freeText: widget.freeText,
    answers: Map.of(widget.ai.answers),
    prefilledIds: widget.ai.prefilled.toList(),
    level: widget.ai.level,
    suggestions: widget.ai.suggestions(),
  );
  bool saved = false;

  static String _newId() {
    final rnd = Random.secure();
    final hex = List.generate(4, (_) => rnd.nextInt(256).toRadixString(16).padLeft(2, '0'));
    return '${hex.join()}-${DateTime.now().millisecondsSinceEpoch}';
  }

  /// Human decision point: nothing is stored until the worker confirms.
  Future<void> _confirmAndSave() async {
    consultation = consultation.copyWith(confirmedByWorker: true);
    await StorageService.save(consultation);
    if (!mounted) return;
    setState(() => saved = true);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(LanguageService.t('saved'))));
    // With internet + server configured, upload right away (SMS stays
    // available as the offline route).
    if (await ServerService.instance.upload(consultation)) {
      consultation = consultation.copyWith(synced: true);
      await StorageService.update(consultation);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(LanguageService.t('uploaded'))));
    }
  }

  Future<void> _shareSms() async {
    // We can only know the SMS app opened, not that the user pressed Send.
    if (await SmsService.openComposer(consultation)) {
      consultation = consultation.copyWith(synced: true);
      await StorageService.update(consultation);
    }
  }

  @override
  Widget build(BuildContext context) {
    const t = LanguageService.t;
    return Scaffold(
      appBar: AppBar(
        title: Text(t('summary_title')),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ConsultationView(consultation: consultation),
            const SizedBox(height: 24),
            if (!saved)
              PrimaryButton(
                  label: t('confirm_save'), icon: Icons.check, onPressed: _confirmAndSave)
            else ...[
              OutlinedButton.icon(
                icon: const Icon(Icons.sms),
                label: Text(t('share_sms')),
                onPressed: _shareSms,
              ),
              const SizedBox(height: 12),
              PrimaryButton(
                label: t('finish'),
                icon: Icons.home,
                onPressed: () => Navigator.popUntil(context, (route) => route.isFirst),
              ),
            ],
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
