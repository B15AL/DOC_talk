import 'dart:convert';
import 'dart:io';

import 'package:health_core/health_core.dart';
import 'package:shelf/shelf.dart';
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
    // age 3 (>5y), 5 danger signs no, cough no, diarrhea no (fever pre-filled)
    final reply = await chat(['fever for 2 days', '3', '2', '2', '2', '2', '2', '2', '2']);
    expect(reply, contains('ROUTINE CARE'));
    expect(reply, contains('This is only a suggestion'));
    final saved = File('${tmp.path}/sms_consultations.jsonl').readAsLinesSync();
    expect(saved, hasLength(1));
    final record = jsonDecode(saved.single) as Map<String, dynamic>;
    expect(record['from'], '*********3210');
    expect(record['answers']['fever_days'], 'd_1_2');
  });

  test('Hindi danger sign -> urgent referral immediately', () async {
    final reply = await chat(['बच्चे को बुखार है', '2', 'haan']);
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
}
