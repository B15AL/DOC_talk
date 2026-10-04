import 'package:flutter/material.dart';
import 'package:health_core/health_core.dart';

import '../services/language_service.dart';
import '../services/server_service.dart';
import '../services/sms_service.dart';
import '../services/storage_service.dart';
import '../widgets/consultation_view.dart';

/// All consultations saved on this phone, newest first.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<Consultation>? _items;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final all = await StorageService.loadAll();
    all.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (mounted) setState(() => _items = all);
  }

  Future<void> _uploadUnsent() async {
    var n = 0;
    for (final c in (_items ?? const <Consultation>[]).where((c) => !c.synced)) {
      if (!await ServerService.instance.upload(c)) break;
      await StorageService.update(c.copyWith(synced: true));
      n++;
    }
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(n > 0
            ? LanguageService.t('uploaded_n').replaceAll('{n}', '$n')
            : LanguageService.t('server_fail'))));
  }

  Future<void> _open(Consultation c) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ConsultationDetailScreen(consultation: c)),
    );
    _load(); // SMS status may have changed.
  }

  @override
  Widget build(BuildContext context) {
    const t = LanguageService.t;
    final items = _items;
    return Scaffold(
      appBar: AppBar(
        title: Text(t('history')),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        actions: [
          if (ServerService.instance.configured &&
              (items ?? const <Consultation>[]).any((c) => !c.synced))
            IconButton(
              tooltip: t('upload_all'),
              icon: const Icon(Icons.cloud_upload),
              onPressed: _uploadUnsent,
            ),
        ],
      ),
      body: items == null
          ? const Center(child: CircularProgressIndicator())
          : items.isEmpty
              ? Center(child: Text(t('no_history')))
              : ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) => _tile(items[i]),
                ),
    );
  }

  Widget _tile(Consultation c) {
    const t = LanguageService.t;
    // Short list of what was found, e.g. "Fever, Cough".
    final findings = c.answers.entries
        .where((e) => e.value == 'yes' && !e.key.startsWith('ds_'))
        .map((e) => t('q_${e.key}').replaceAll('?', ''))
        .join(' • ');
    return ListTile(
      leading: CircleAvatar(backgroundColor: levelColors[c.level], radius: 10),
      title: Text(t('level_${c.level.name}'),
          style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Text(
        [_formatDate(c.createdAt), if (findings.isNotEmpty) findings].join('\n'),
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
      isThreeLine: findings.isNotEmpty,
      trailing: Icon(c.synced ? Icons.cloud_done : Icons.cloud_off,
          color: c.synced ? Colors.teal : Colors.grey,
          semanticLabel: c.synced ? t('sent') : t('not_sent')),
      onTap: () => _open(c),
    );
  }
}

class ConsultationDetailScreen extends StatefulWidget {
  final Consultation consultation;

  const ConsultationDetailScreen({super.key, required this.consultation});

  @override
  State<ConsultationDetailScreen> createState() => _ConsultationDetailScreenState();
}

class _ConsultationDetailScreenState extends State<ConsultationDetailScreen> {
  late Consultation consultation = widget.consultation;

  Future<void> _shareSms() async {
    if (await SmsService.openComposer(consultation)) {
      final updated = consultation.copyWith(synced: true);
      await StorageService.update(updated);
      if (mounted) setState(() => consultation = updated);
    }
  }

  @override
  Widget build(BuildContext context) {
    const t = LanguageService.t;
    return Scaffold(
      appBar: AppBar(
        title: Text(t('details')),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_formatDate(consultation.createdAt),
                style: const TextStyle(color: Colors.black54)),
            const SizedBox(height: 12),
            ConsultationView(consultation: consultation),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              icon: Icon(consultation.synced ? Icons.cloud_done : Icons.sms),
              label: Text(t('share_sms')),
              onPressed: _shareSms,
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

String _formatDate(DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.day)}/${two(d.month)}/${d.year}  ${two(d.hour)}:${two(d.minute)}';
}
