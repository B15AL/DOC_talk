import 'dart:convert';
import 'dart:io';

import 'package:sms_server/conversation.dart';
import 'package:sms_server/report_store.dart';

/// Terminal "feature phone" for demos — no gateway or internet needed.
///   dart run bin/simulate.dart
Future<void> main() async {
  final conversations = ConversationManager(ReportStore('data'));
  const phone = '+910000000001';
  stdout.writeln('Feature-phone simulator. Type an SMS (Ctrl+D to quit).');
  stdout.writeln('Try: "3 din se bukhar aur khansi hai" or "my child has fever"\n');
  final lines = stdin.transform(utf8.decoder).transform(const LineSplitter());
  stdout.write('📱 > ');
  await for (final line in lines) {
    if (line.trim().isEmpty) {
      stdout.write('📱 > ');
      continue;
    }
    for (final reply in await conversations.handle(phone, line)) {
      stdout.writeln('\n💬 ${reply.replaceAll('\n', '\n   ')}\n');
    }
    stdout.write('📱 > ');
  }
}
