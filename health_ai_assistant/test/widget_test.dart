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

  group('chat consultation', () {
    setUp(() {
      LanguageService.current.value = 'en';
      // No TTS engine in tests.
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('flutter_tts'), (_) async => 1);
    });

    /// Tall screen so the whole chat stays built (ListView is lazy).
    Future<void> openChat(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const MaterialApp(home: ConsultationScreen()));
    }

    Future<void> say(WidgetTester tester, String text) async {
      await tester.enterText(find.byType(TextField), text);
      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();
    }

    testWidgets('description -> chips -> questions that follow what was said', (tester) async {
      await openChat(tester);
      await say(tester, 'bachche ko bukhar hai aur khansi 3 hafte se');

      // Understood symptoms appear as removable chips in the same chat.
      expect(find.text('From what you said, I understood:'), findsOneWidget);
      expect(find.widgetWithText(InputChip, 'Fever'), findsOneWidget);
      expect(find.widgetWithText(InputChip, 'Cough for: 2 weeks or more'), findsOneWidget);
      expect(find.text('Age of the patient?'), findsOneWidget);
      // Runtime changes are announced in the chat.
      expect(find.text('✓ Skipping 2 questions — already understood'), findsOneWidget);
      expect(find.text('+ Added 4 checks because of the fever'), findsOneWidget);
      expect(find.text('+ Added 2 breathing checks because of the cough'), findsOneWidget);
      expect(find.text('+ Added a TB check because the cough is long'), findsOneWidget);
      expect(find.textContaining('💊 Advice updated:'), findsWidgets);
      expect(find.textContaining('Live assessment: Clinician review needed'), findsOneWidget);

      // Tap an answer...
      await tester.tap(find.widgetWithText(ElevatedButton, '2 months – 5 years'));
      await tester.pumpAndSettle();
      expect(find.text('Thanks. You mentioned fever. For how many days has it been there?'),
          findsOneWidget);

      // ...or type it in your own words.
      await say(tester, '2 din se');
      expect(
        find.text('Thanks. Now a few important safety questions. Since there is fever, '
            'please check: Is the child unconscious, very drowsy or not responding?'),
        findsOneWidget,
      );
    });

    testWidgets('removing a wrong finding drops it and its follow-up', (tester) async {
      await openChat(tester);
      await say(tester, 'fever for 3 days');
      expect(find.byType(InputChip), findsNWidgets(2));

      // The chip's delete (✕) icon.
      await tester.tap(find
          .descendant(of: find.widgetWithText(InputChip, 'Fever'), matching: find.byType(Icon))
          .last);
      await tester.pumpAndSettle();
      expect(find.byType(InputChip), findsNothing);
      expect(find.text("Removed — I'll ask about it."), findsOneWidget);
    });

    testWidgets('dehydration checks change the advice live', (tester) async {
      await openChat(tester);
      await say(tester, 'bachche ko dast ho rahe hain');
      expect(find.text('+ Added 5 dehydration checks because of the loose motions'),
          findsOneWidget);
      await tester.tap(find.widgetWithText(ElevatedButton, '2 months – 5 years'));
      await tester.pumpAndSettle();
      // blood in stool, then the 5 danger signs: all "No".
      for (var i = 0; i < 6; i++) {
        await tester.tap(find.widgetWithText(ElevatedButton, 'No'));
        await tester.pumpAndSettle();
      }
      expect(find.textContaining('Live assessment: Routine care'), findsOneWidget);
      // Sunken eyes: yes; thirsty: yes -> "some dehydration" -> Plan B.
      await tester.tap(find.widgetWithText(ElevatedButton, 'Yes'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Yes'));
      await tester.pumpAndSettle();
      expect(find.text('⚠ Assessment changed: Clinician review needed'), findsOneWidget);
      expect(find.textContaining('ORS Plan B'), findsOneWidget);
    });

    testWidgets('typed answer that is not understood gets a gentle retry', (tester) async {
      await openChat(tester);
      await tester.tap(find.text('Skip — just ask me'));
      await tester.pumpAndSettle();
      await say(tester, 'banana');
      expect(find.textContaining("Sorry, I didn't get that."), findsOneWidget);
    });
  });
}
