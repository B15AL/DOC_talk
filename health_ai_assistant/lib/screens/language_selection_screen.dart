import 'package:flutter/material.dart';

import '../services/language_service.dart';
import 'home_screen.dart';

class LanguageSelectionScreen extends StatefulWidget {
  const LanguageSelectionScreen({super.key});

  @override
  State<LanguageSelectionScreen> createState() => _LanguageSelectionScreenState();
}

class _LanguageSelectionScreenState extends State<LanguageSelectionScreen> {
  String? selectedCode = LanguageService.current.value;

  Future<void> _continue() async {
    await LanguageService.saveLanguage(selectedCode!);
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Shown in both languages: the user hasn't picked one yet.
      appBar: AppBar(title: const Text('भाषा चुनें / Choose language')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            RadioGroup<String>(
              groupValue: selectedCode,
              onChanged: (value) => setState(() => selectedCode = value),
              child: Column(
                children: [
                  for (final entry in LanguageService.supportedLanguages.entries)
                    RadioListTile<String>(
                      title: Text(entry.value, style: const TextStyle(fontSize: 18)),
                      value: entry.key,
                    ),
                ],
              ),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: selectedCode == null ? null : _continue,
                child: const Text('आगे बढ़ें / Continue', style: TextStyle(fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
