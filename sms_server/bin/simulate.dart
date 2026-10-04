import 'dart:convert';
import 'dart:io';

import 'package:sms_server/ai_extractor.dart';
import 'package:sms_server/conversation.dart';
import 'package:sms_server/report_store.dart';

/// Terminal "feature phone" for demos — no gateway or internet needed.
///   dart run bin/simulate.dart                 (keywords only)
///   MODEL_PATH=model.gguf dart run bin/simulate.dart   (with the AI)
Future<void> main() async {
  final modelPath = Platform.environment['MODEL_PATH'];
  final model = modelPath == null ? null : await ModelExtractor.load(modelPath);
  stdout.writeln(model == null ? 'Keyword mode.' : 'AI model loaded.');
  final conversations =
      ConversationManager(ReportStore('data'), extractor: CombinedExtractor(model: model));
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
