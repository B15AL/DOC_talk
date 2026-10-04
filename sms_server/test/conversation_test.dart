import 'dart:convert';
import 'dart:io';

import 'package:health_core/health_core.dart';
import 'package:shelf/shelf.dart';
import 'package:sms_server/ai_extractor.dart';
import 'package:sms_server/conversation.dart';
import 'package:sms_server/report_store.dart';
import 'package:sms_server/server.dart';
import 'package:test/test.dart';

void main() {
  late Directory tmp;
  late ConversationManager cm;
  const phone = '+919876543210';

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('sms_test');
    cm = ConversationManager(ReportStore(tmp.path));
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  /// Sends [messages] in order, returns the last reply.
  Future<String> chat(List<String> messages) async {
    late List<String> replies;
    for (final m in messages) {
      replies = await cm.handle(phone, m);
    }
    return replies.join('\n');
  }

  test('language detection', () {
    expect(ConversationManager.detectLanguage('मुझे बुखार है'), 'hi');
    expect(ConversationManager.detectLanguage('3 din se bukhar hai'), 'hi');
    expect(ConversationManager.detectLanguage('I have fever'), 'en');
  });

  test('English: first SMS pre-fills, asks age with numbered options', () async {
    final reply = await chat(['child has fever for 2 days']);
    expect(reply, contains('Age of the patient?'));
    expect(reply, contains('1=Under 2 months'));
  });

  test('full routine conversation ends with disclaimer and is stored', () async {
    // age 3 (>5y), 5 danger signs no, fever checks added at runtime (stiff
    // neck no, rash no, malaria test 3 = not done), cough no, diarrhea no.
    final reply = await chat(
        ['fever for 2 days', '3', '2', '2', '2', '2', '2', '2', '2', '3', '2', '2']);
    expect(reply, contains('ROUTINE CARE'));
    expect(reply, contains('This is only a suggestion'));
    final saved = File('${tmp.path}/sms_consultations.jsonl').readAsLinesSync();
    expect(saved, hasLength(1));
    final record = jsonDecode(saved.single) as Map<String, dynamic>;
    expect(record['from'], '*********3210');
    expect(record['answers']['fever_days'], 'd_1_2');
  });

  test('Hindi danger sign -> urgent referral immediately', () async {
    // age -> "how many days?" (follow-up on the fever) -> first danger sign
    final reply = await chat(['बच्चे को बुखार है', '2', '2', 'haan']);
    expect(reply, contains(Strings.of('hi', 'level_urgentReferral')));
    expect(reply, contains(Strings.of('hi', 'disclaimer')));
  });

  test('invalid reply repeats the question', () async {
    await chat(['fever']);
    final reply = await chat(['banana']);
    expect(reply, contains('Please reply with one of the numbers.'));
    expect(reply, contains('Age of the patient?'));
  });

  test('0 restarts, ENGLISH switches language', () async {
    await chat(['बुखार है']);
    final reply = await chat(['english']);
    expect(reply, contains('Age of the patient?'));
  });

  test('session expires after timeout', () async {
    final t0 = DateTime(2026, 10, 4, 10);
    await cm.handle(phone, 'fever', now: t0);
    final r = await cm.handle(phone, '1', now: t0.add(const Duration(hours: 1)));
    expect(r.single, startsWith('Health Assistant')); // new conversation
  });

  test('app report SMS is decoded and stored', () async {
    final reply = await chat(['HAI1 abcdef U A1 D1Y']);
    expect(reply, contains('abcdef'));
    final saved = File('${tmp.path}/app_reports.jsonl').readAsStringSync();
    expect(saved, contains('"ds_unconscious":"yes"'));
  });

  test('HTTP: JSON and Twilio webhooks', () async {
    final handler = buildHandler(cm);
    final json = await handler(Request('POST', Uri.parse('http://x/sms/incoming'),
        body: jsonEncode({'from': '+911', 'text': 'fever'})));
    expect(json.statusCode, 200);
    final replies = jsonDecode(await json.readAsString())['replies'] as List;
    expect(replies.single, contains('Age of the patient?'));

    final twilio = await handler(Request('POST', Uri.parse('http://x/sms/twilio'),
        body: 'From=%2B912&Body=cough'));
    expect(await twilio.readAsString(), contains('<Message>Health Assistant'));

    final bad = await handler(
        Request('POST', Uri.parse('http://x/sms/incoming'), body: 'nope'));
    expect(bad.statusCode, 400);
  });

  group('AI on the server', () {
    // Stands in for the GGUF model: understands one phrase keywords miss.
    final fakeModel = _FakeModel({'paani jaisa latrine': {'diarrhea': 'yes'}});

    test('SMS: AI understands what keywords miss, in the first message', () async {
      cm = ConversationManager(ReportStore(tmp.path),
          extractor: CombinedExtractor(model: fakeModel));
      await chat(['baccha: paani jaisa latrine', '2']); // age 2 months–5 years
      // Diarrhoea understood -> its follow-up comes next.
      final reply = await chat(['2']); // blood in stool: no
      expect(reply, contains(Strings.of('hi', 'because_diarrhea')));
    });

    test('SMS: free-text reply answers the question and adds findings', () async {
      cm = ConversationManager(ReportStore(tmp.path),
          extractor: CombinedExtractor(model: fakeModel));
      await chat(['help', '3']); // no description, age > 5
      final reply = await chat(['haan aur paani jaisa latrine bhi']); // "unconscious?" -> yes
      expect(reply, contains('URGENT'));
    });

    test('API: understand, auth and upload', () async {
      cm = ConversationManager(ReportStore(tmp.path),
          extractor: CombinedExtractor(model: fakeModel));
      final handler = buildHandler(cm, apiKey: 'secret');
      Request post(String path, Object body, {String? key}) => Request(
          'POST', Uri.parse('http://x/$path'),
          body: jsonEncode(body), headers: {if (key != null) 'x-api-key': key});

      expect((await handler(post('api/understand', {'text': 'x'}))).statusCode, 401);

      final res = await handler(
          post('api/understand', {'text': 'bukhar aur paani jaisa latrine'}, key: 'secret'));
      final body = jsonDecode(await res.readAsString());
      expect(body['findings'], {'diarrhea': 'yes', 'fever': 'yes'});
      expect(body['aiOnly'], ['diarrhea']);

      final c = Consultation(
        id: 'abc123-1', createdAt: DateTime(2026), languageCode: 'en', freeText: '',
        answers: const {'fever': 'yes'}, level: TriageLevel.routine, suggestions: const [],
      );
      final up = await handler(post('api/consultations', c.toJson(), key: 'secret'));
      expect(up.statusCode, 200);
      expect(File('${tmp.path}/app_consultations.jsonl').readAsStringSync(), contains('abc123-1'));

      // SMS webhooks stay open for gateways.
      final sms = await handler(post('sms/incoming', {'from': '+1', 'text': 'hi'}));
      expect(sms.statusCode, 200);
    });
  });
}

class _FakeModel implements AnswerExtractor {
  final Map<String, Map<String, String>> known;
  _FakeModel(this.known);

  @override
  Future<Map<String, String>> extract(String text) async {
    for (final e in known.entries) {
      if (text.contains(e.key)) return e.value;
    }
    return const {};
  }
}
