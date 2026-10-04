import 'dart:io';

import 'package:shelf/shelf_io.dart' as io;
import 'package:sms_server/conversation.dart';
import 'package:sms_server/report_store.dart';
import 'package:sms_server/server.dart';

/// dart run bin/server.dart          (PORT and DATA_DIR env vars optional)
Future<void> main() async {
  final port = int.parse(Platform.environment['PORT'] ?? '8080');
  final store = ReportStore(Platform.environment['DATA_DIR'] ?? 'data');
  final server = await io.serve(
    buildHandler(ConversationManager(store)),
    InternetAddress.anyIPv4,
    port,
  );
  print('SMS server listening on http://${server.address.host}:${server.port}');
}
