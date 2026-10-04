import 'package:flutter/material.dart';

import 'package:health_core/health_core.dart';
import '../services/ai_model_service.dart';
import '../services/language_service.dart';
import '../services/storage_service.dart';
import 'ai_model_screen.dart';
import 'consultation_screen.dart';
import 'history_screen.dart';
import 'language_selection_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Consultation> _saved = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final all = await StorageService.loadAll();
    if (mounted) setState(() => _saved = all);
  }

  Future<void> _startConsultation() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ConsultationScreen()),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    const t = LanguageService.t;
    final pending = _saved.where((c) => !c.synced).length;

    return Scaffold(
      appBar: AppBar(
        title: Text(t('app_title')),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: t('change_language'),
            icon: const Icon(Icons.translate),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const LanguageSelectionScreen()),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.health_and_safety, size: 80, color: Colors.teal),
            const SizedBox(height: 20),
            Text(
              t('app_title'),
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              t('tagline'),
              style: const TextStyle(fontSize: 14, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 50),
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.mic),
                label: Text(t('start'), style: const TextStyle(fontSize: 18)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _startConsultation,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.history),
                label: Text(t('history'), style: const TextStyle(fontSize: 16)),
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const HistoryScreen()),
                  );
                  _load();
                },
              ),
            ),
            const SizedBox(height: 12),
            ListenableBuilder(
              listenable: AiModelService.instance,
              builder: (context, _) => _aiCard(),
            ),
            const SizedBox(height: 24),
            Text('${t('saved_count')}: ${_saved.length}  •  ${t('pending_sync')}: $pending',
                style: const TextStyle(color: Colors.black54)),
          ],
        ),
      ),
    );
  }

  /// Shows whether smart AI or keyword mode is active; tap to manage.
  Widget _aiCard() {
    const t = LanguageService.t;
    final ai = AiModelService.instance;
    final on = ai.usable;
    return Card(
      color: on ? Colors.teal.shade50 : Colors.grey.shade100,
      child: ListTile(
        leading: Icon(on ? Icons.auto_awesome : Icons.text_fields,
            color: on ? Colors.teal : Colors.grey),
        title: Text(on ? t('ai_title') : t('ai_keywords')),
        subtitle: Text(t('ai_status_${ai.status.name}')),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AiModelScreen()),
        ),
      ),
    );
  }
}
