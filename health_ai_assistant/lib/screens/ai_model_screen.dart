import 'package:flutter/material.dart';

import '../services/ai_model_service.dart';
import '../services/language_service.dart';

/// Choose, download, test and delete the optional on-device AI model.
class AiModelScreen extends StatefulWidget {
  const AiModelScreen({super.key});

  @override
  State<AiModelScreen> createState() => _AiModelScreenState();
}

class _AiModelScreenState extends State<AiModelScreen> {
  final AiModelService ai = AiModelService.instance;

  @override
  Widget build(BuildContext context) {
    const t = LanguageService.t;
    return Scaffold(
      appBar: AppBar(
        title: Text(t('ai_title')),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      body: ListenableBuilder(
        listenable: ai,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(t('ai_subtitle'), style: const TextStyle(fontSize: 15)),
            const SizedBox(height: 8),
            if (ai.phoneRamMb != null)
              Text('${t('ai_phone_ram')}: ${(ai.phoneRamMb! / 1024).toStringAsFixed(1)} GB',
                  style: const TextStyle(color: Colors.black54)),
            const SizedBox(height: 16),
            if (ai.status == AiStatus.unsupported)
              _statusBox(t('ai_status_unsupported'), Colors.orange)
            else ...[
              SwitchListTile(
                title: Text(t('ai_use')),
                value: ai.enabled,
                onChanged: ai.setEnabled,
                contentPadding: EdgeInsets.zero,
              ),
              const Divider(),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.memory, color: Colors.teal),
                title: const Text(AiModelService.modelName),
                subtitle: Text(_lowRam
                    ? '${t('ai_note')}\n⚠ ${t('ai_ram_warning')}'
                    : t('ai_note')),
              ),
              const SizedBox(height: 12),
              _statusAndActions(),
            ],
          ],
        ),
      ),
    );
  }

  bool get _lowRam => ai.phoneRamMb != null && ai.phoneRamMb! < 2000;

  Widget _statusAndActions() {
    const t = LanguageService.t;
    final status = ai.status;
    final statusColor = switch (status) {
      AiStatus.ready || AiStatus.downloaded => Colors.green,
      AiStatus.failed => Colors.red,
      _ => Colors.blueGrey,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _statusBox(
          status == AiStatus.failed && ai.error != null
              ? '${t('ai_status_failed')}: ${ai.error}'
              : t('ai_status_${status.name}'),
          statusColor,
        ),
        const SizedBox(height: 12),
        if (status == AiStatus.downloading) ...[
          LinearProgressIndicator(value: ai.downloadFraction, minHeight: 8),
          const SizedBox(height: 6),
          Text(
            '${ai.downloadedBytes ~/ (1024 * 1024)} / ~${AiModelService.approxSizeMb} MB',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: ai.cancelDownload, child: Text(t('ai_cancel'))),
        ] else if (status == AiStatus.importing || status == AiStatus.loading)
          const LinearProgressIndicator(minHeight: 8)
        else if (!ai.isDownloaded) ...[
          if (ai.canDownload)
            ElevatedButton.icon(
              icon: const Icon(Icons.download),
              label: Text('${t('ai_download')} (~${AiModelService.approxSizeMb} MB)'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(50),
              ),
              onPressed: ai.download,
            ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.folder_open),
            label: Text(t('ai_import')),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            onPressed: ai.importFromFile,
          ),
          const SizedBox(height: 6),
          Text(t('ai_import_hint'),
              style: const TextStyle(fontSize: 12, color: Colors.black54)),
        ] else
          OutlinedButton.icon(
            icon: const Icon(Icons.delete_outline),
            label: Text(t('ai_delete')),
            onPressed: ai.delete,
          ),
      ],
    );
  }

  Widget _statusBox(String text, Color color) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          border: Border.all(color: color),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(text, style: TextStyle(color: color)),
      );
}
