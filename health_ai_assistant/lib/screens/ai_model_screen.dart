import 'package:flutter/material.dart';

import '../services/ai_model_service.dart';
import '../services/language_service.dart';
import '../services/server_service.dart';

/// Optional on-device AI model (import / download / delete) and the
/// optional online server (AI for phones without the model + uploads).
class AiModelScreen extends StatefulWidget {
  const AiModelScreen({super.key});

  @override
  State<AiModelScreen> createState() => _AiModelScreenState();
}

class _AiModelScreenState extends State<AiModelScreen> {
  final AiModelService ai = AiModelService.instance;
  final ServerService server = ServerService.instance;
  late final TextEditingController urlController = TextEditingController(text: server.url);
  late final TextEditingController keyController = TextEditingController(text: server.apiKey);
  bool testing = false;
  bool? testResult;

  @override
  void dispose() {
    urlController.dispose();
    keyController.dispose();
    super.dispose();
  }

  Future<void> _saveServer() async {
    FocusScope.of(context).unfocus();
    setState(() => testing = true);
    await server.save(urlController.text, keyController.text);
    final ok = server.configured && await server.test();
    if (mounted) {
      setState(() {
        testing = false;
        testResult = server.configured ? ok : null;
      });
    }
  }

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
            const Divider(height: 40),
            _serverSection(),
          ],
        ),
      ),
    );
  }

  Widget _serverSection() {
    const t = LanguageService.t;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.cloud_outlined, color: Colors.teal),
            const SizedBox(width: 8),
            Text(t('server_title'),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 6),
        Text(t('server_hint'), style: const TextStyle(fontSize: 13, color: Colors.black54)),
        const SizedBox(height: 12),
        TextField(
          controller: urlController,
          keyboardType: TextInputType.url,
          decoration: InputDecoration(
            labelText: t('server_url'),
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: keyController,
          obscureText: true,
          decoration: InputDecoration(
            labelText: t('server_key'),
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          icon: testing
              ? const SizedBox(
                  width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.wifi_tethering),
          label: Text(t('server_save')),
          onPressed: testing ? null : _saveServer,
        ),
        if (testResult != null) ...[
          const SizedBox(height: 10),
          testResult!
              ? _statusBox(
                  server.serverHasAi == true ? t('server_ok_ai') : t('server_ok'), Colors.green)
              : _statusBox(t('server_fail'), Colors.red),
        ],
      ],
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
