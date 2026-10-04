import 'package:health_core/health_core.dart';
import 'package:url_launcher/url_launcher.dart';

class SmsService {
  /// Opens the phone's SMS app with the message pre-filled. The worker taps
  /// Send, so no SEND_SMS permission (restricted on Play Store) is needed.
  static Future<bool> openComposer(Consultation c, {String number = ''}) {
    // Built by hand: queryParameters would encode spaces as '+', which some
    // SMS apps show literally.
    final uri = Uri(
      scheme: 'sms',
      path: number,
      query: 'body=${Uri.encodeComponent(SmsCodec.encode(c))}',
    );
    return launchUrl(uri);
  }
}
