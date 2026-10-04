import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:health_ai_assistant/main.dart';
import 'package:health_ai_assistant/screens/ai_model_screen.dart';
import 'package:health_ai_assistant/screens/consultation_screen.dart';
import 'package:health_ai_assistant/services/language_service.dart';
import 'package:health_ai_assistant/widgets/consultation_view.dart';
import 'package:health_core/health_core.dart';

void main() {
  testWidgets('first launch shows language selection', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MyApp(languageChosen: false));
    expect(find.text('English'), findsOneWidget);
    expect(find.byType(RadioListTile<String>), findsNWidgets(2));
  });

  testWidgets('consultation view shows level, reasons and prefilled tag', (tester) async {
    LanguageService.current.value = 'en';
    final ai = LocalAIService()..prefillFromText('cough for 3 weeks');
    for (var q = ai.nextQuestion(); q != null; q = ai.nextQuestion()) {
      ai.answer(q.id, q.options.isEmpty ? 'no' : q.options.last);
    }
    final c = Consultation(
      id: 'abcdef-1',
      createdAt: DateTime(2026, 10, 4),
      languageCode: 'en',
      freeText: 'cough for 3 weeks',
      answers: ai.answers,
      prefilledIds: ai.prefilled.toList(),
      level: ai.level,
      suggestions: ai.suggestions(),
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: ConsultationView(consultation: c))),
    ));
    expect(find.text('Clinician review needed'), findsOneWidget);
    expect(find.textContaining('TB testing'), findsOneWidget);
    expect(find.textContaining('(from description)'), findsNWidgets(2));
  });

  testWidgets('AI model screen offers import when no download URL is set', (tester) async {
    LanguageService.current.value = 'en';
    await tester.pumpWidget(const MaterialApp(home: AiModelScreen()));
    expect(find.textContaining('Gemma 3 270M'), findsOneWidget);
    expect(find.text('Import model file'), findsOneWidget);
    expect(find.byIcon(Icons.download), findsNothing); // no AI_MODEL_URL in tests
  });

  testWidgets('description findings need a tick before questions are skipped', (tester) async {
    LanguageService.current.value = 'en';
    // No TTS engine in tests.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter_tts'), (_) async => 1);

    await tester.pumpWidget(const MaterialApp(home: ConsultationScreen()));
    await tester.enterText(find.byType(TextField), '3 din se bukhar aur khansi hai');
    await tester.tap(find.text('Start questions'));
    await tester.pumpAndSettle();

    // Confirm step lists what was understood, all ticked.
    expect(find.text('Understood from the description'), findsOneWidget);
    expect(find.byType(CheckboxListTile), findsNWidgets(3));

    // Untick fever -> its duration is unticked too.
    await tester.tap(find.text('Does the patient have fever?'));
    await tester.pump();
    final ticked = tester
        .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
        .where((c) => c.value == true);
    expect(ticked, hasLength(1)); // only cough

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Age of the patient?'), findsOneWidget);
  });
}
