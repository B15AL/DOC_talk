import 'dart:convert';
import 'dart:io';

import 'package:health_core/health_core.dart';

/// Append-only JSON-lines files. Good enough for a pilot; swap for a real
/// database (with encryption at rest) before handling real patient data.
class ReportStore {
  final Directory dir;

  ReportStore(String path) : dir = Directory(path);

  /// Keeps only the last 4 digits so the file isn't a list of phone numbers.
  static String maskPhone(String phone) => phone.length <= 4
      ? phone
      : '${'*' * (phone.length - 4)}${phone.substring(phone.length - 4)}';

  Future<void> saveConsultation(String from, Consultation c) => _append(
      'sms_consultations.jsonl', {'from': maskPhone(from), ...c.toJson()});

  /// Consultation uploaded by the Android app over the internet.
  Future<void> saveUploadedConsultation(Consultation c, {String? device}) => _append(
      'app_consultations.jsonl',
      {'device': device, 'receivedAt': DateTime.now().toIso8601String(), ...c.toJson()});

  Future<void> saveAppReport(String from, Map<String, String> decoded, DateTime at) =>
      _append('app_reports.jsonl', {
        'from': maskPhone(from),
        'receivedAt': at.toIso8601String(),
        ...decoded,
      });

  Future<void> _append(String file, Map<String, dynamic> record) async {
    await dir.create(recursive: true);
    await File('${dir.path}/$file')
        .writeAsString('${jsonEncode(record)}\n', mode: FileMode.append, flush: true);
  }
}
