import 'dart:convert';

import 'package:health_core/health_core.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'conversation.dart';

/// One server for both channels.
///
/// SMS gateways (feature phones):
///  * POST /sms/incoming  JSON {"from": "+91...", "text": "..."} -> {"replies": [...]}
///  * POST /sms/twilio    Twilio form webhook (From, Body) -> TwiML
///
/// Android app (smartphones with internet), header `x-api-key: <API_KEY>`:
///  * GET  /api/status         -> {"ai": true|false}
///  * POST /api/understand     {"text": "..."} -> {"findings": {...}, "aiOnly": [...]}
///  * POST /api/consultations  Consultation JSON -> {"ok": true}
///
///  * GET  /health
Handler buildHandler(ConversationManager conversations, {String? apiKey}) {
  Response json(Object body, {int status = 200}) => Response(status,
      body: jsonEncode(body), headers: {'content-type': 'application/json; charset=utf-8'});

  Future<Map<String, dynamic>?> readJson(Request req) async {
    try {
      final body = jsonDecode(await req.readAsString());
      return body is Map<String, dynamic> ? body : null;
    } on FormatException {
      return null;
    }
  }

  final router = Router()
    ..get('/health', (Request _) => Response.ok('ok'))
    ..post('/sms/incoming', (Request req) async {
      final body = await readJson(req);
      if (body == null || body['from'] is! String || body['text'] is! String) {
        return Response.badRequest(body: 'expected {"from": string, "text": string}');
      }
      final replies = await conversations.handle(body['from'], body['text']);
      return json({'replies': replies});
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
    })
    ..get('/api/status', (Request _) => json({'ai': conversations.extractor.hasModel}))
    ..post('/api/understand', (Request req) async {
      final body = await readJson(req);
      final text = body?['text'];
      if (text is! String || text.length > 2000) {
        return Response.badRequest(body: 'expected {"text": string}');
      }
      final u = await conversations.extractor.understand(text);
      return json({'findings': u.findings, 'aiOnly': u.aiOnly.toList()});
    })
    ..post('/api/consultations', (Request req) async {
      final body = await readJson(req);
      final Consultation c;
      try {
        c = Consultation.fromJson(body!);
      } on Object {
        return Response.badRequest(body: 'invalid consultation');
      }
      await conversations.store.saveUploadedConsultation(c, device: req.headers['x-device']);
      return json({'ok': true, 'id': c.id});
    });

  return const Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(_requireApiKey(apiKey))
      .addHandler(router.call);
}

/// Protects /api/* with a shared key (SMS webhooks stay open for gateways).
Middleware _requireApiKey(String? apiKey) => (inner) => (req) {
      final protected = req.url.path.startsWith('api/');
      if (protected && apiKey != null && req.headers['x-api-key'] != apiKey) {
        return Response(401, body: 'missing or wrong x-api-key');
      }
      return inner(req);
    };

String _xmlEscape(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');
