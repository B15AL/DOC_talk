import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'conversation.dart';

/// HTTP webhooks for SMS gateways.
///
///  * POST /sms/incoming  JSON {"from": "+91...", "text": "..."}
///                        -> {"replies": ["..."]}   (generic / Android gateway apps)
///  * POST /sms/twilio    Twilio form webhook (From, Body) -> TwiML
///  * GET  /health
Handler buildHandler(ConversationManager conversations) {
  final router = Router()
    ..get('/health', (Request _) => Response.ok('ok'))
    ..post('/sms/incoming', (Request req) async {
      final Object? body;
      try {
        body = jsonDecode(await req.readAsString());
      } on FormatException {
        return Response.badRequest(body: 'invalid JSON');
      }
      if (body is! Map || body['from'] is! String || body['text'] is! String) {
        return Response.badRequest(body: 'expected {"from": string, "text": string}');
      }
      final replies = await conversations.handle(body['from'], body['text']);
      return Response.ok(jsonEncode({'replies': replies}),
          headers: {'content-type': 'application/json; charset=utf-8'});
    })
    ..post('/sms/twilio', (Request req) async {
      final form = Uri.splitQueryString(await req.readAsString());
      final from = form['From'];
      final text = form['Body'];
      if (from == null || text == null) return Response.badRequest(body: 'missing From/Body');
      final replies = await conversations.handle(from, text);
      final messages = replies.map((r) => '<Message>${_xmlEscape(r)}</Message>').join();
      return Response.ok('<?xml version="1.0" encoding="UTF-8"?><Response>$messages</Response>',
          headers: {'content-type': 'text/xml; charset=utf-8'});
    });

  return const Pipeline().addMiddleware(logRequests()).addHandler(router.call);
}

String _xmlEscape(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');
