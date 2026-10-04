import 'dart:io';

import 'package:shelf/shelf_io.dart' as io;
import 'package:sms_server/ai_extractor.dart';
import 'package:sms_server/conversation.dart';
import 'package:sms_server/report_store.dart';
import 'package:sms_server/server.dart';

/// Environment:
///   PORT        default 8080
///   DATA_DIR    default ./data
///   MODEL_PATH  fine-tuned .gguf (tools/finetune) — enables the AI;
///               without it the server uses keyword matching
///   API_KEY     required header for the app API (/api/*)
Future<void> main() async {
  final env = Platform.environment;
  final port = int.parse(env['PORT'] ?? '8080');
  final store = ReportStore(env['DATA_DIR'] ?? 'data');

  ModelExtractor? model;
  final modelPath = env['MODEL_PATH'];
  if (modelPath != null) {
    stdout.write('Loading AI model $modelPath ... ');
    model = await ModelExtractor.load(modelPath);
    stdout.writeln('ok');
  } else {
    stdout.writeln('MODEL_PATH not set: keyword matching only.');
  }

  final apiKey = env['API_KEY'];
  if (apiKey == null) {
    stdout.writeln('WARNING: API_KEY not set — the app API (/api/*) is open to anyone.');
  }

  final conversations = ConversationManager(store, extractor: CombinedExtractor(model: model));
  final server = await io.serve(
    buildHandler(conversations, apiKey: apiKey),
    InternetAddress.anyIPv4,
    port,
  );
  stdout.writeln('Listening on http://${server.address.host}:${server.port}');
}
