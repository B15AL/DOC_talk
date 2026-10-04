import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'package:health_core/health_core.dart';

/// Saves consultations as one JSON object per line in the app's private
/// documents folder. Fully offline, no database dependency.
class StorageService {
  static const _fileName = 'consultations.jsonl';

  static Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  static Future<List<Consultation>> loadAll() async {
    final file = await _file();
    if (!await file.exists()) return [];
    final lines = await file.readAsLines();
    return lines
        .where((l) => l.trim().isNotEmpty)
        .map((l) => Consultation.fromJson(jsonDecode(l) as Map<String, dynamic>))
        .toList();
  }

  static Future<void> save(Consultation c) async {
    final file = await _file();
    await file.writeAsString('${jsonEncode(c.toJson())}\n',
        mode: FileMode.append, flush: true);
  }

  /// Rewrites the file with [c] replacing the record with the same id.
  static Future<void> update(Consultation c) async {
    final all = await loadAll();
    final file = await _file();
    final body = all
        .map((e) => jsonEncode((e.id == c.id ? c : e).toJson()))
        .join('\n');
    await file.writeAsString('$body\n', flush: true);
  }
}
