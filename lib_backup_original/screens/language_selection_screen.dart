import 'package:flutter/material.dart';
import '../services/language_service.dart';
import 'home_screen.dart';

class LanguageSelectionScreen extends StatefulWidget {
  const LanguageSelectionScreen({super.key});

  @override
  State<LanguageSelectionScreen> createState() => _LanguageSelectionScreenState();
}

class _LanguageSelectionScreenState extends State<LanguageSelectionScreen> {
  String? selectedCode;
  bool isDownloading = false;

  Future<void> _downloadAndContinue() async {
    if (selectedCode == null) return;

    setState(() => isDownloading = true);

    // TODO: Real download logic later
    // For now we just simulate + save
    await Future.delayed(const Duration(seconds: 2));
    await LanguageService.saveLanguage(selectedCode!);

    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Bhasha Chunein / Choose Language")),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Text(
              "Apni bhasha select karein",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 30),
            ...LanguageService.supportedLanguages.entries.map((entry) {
              return RadioListTile<String>(
                title: Text(entry.value),
                value: entry.key,
                groupValue: selectedCode,
                onChanged: (value) {
                  setState(() => selectedCode = value);
                },
              );
            }),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: selectedCode == null || isDownloading
                    ? null
                    : _downloadAndContinue,
                child: isDownloading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text("Download & Continue"),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
