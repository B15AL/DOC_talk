import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'screens/language_selection_screen.dart';
import 'services/ai_model_service.dart';
import 'services/language_service.dart';
import 'services/server_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final saved = await LanguageService.getSavedLanguage();
  if (saved != null) LanguageService.current.value = saved;
  // Only checks whether a model is already downloaded; loading into RAM
  // happens later, when a consultation starts.
  await AiModelService.instance.init();
  await ServerService.instance.init();
  runApp(MyApp(languageChosen: saved != null));
}

class MyApp extends StatelessWidget {
  final bool languageChosen;

  const MyApp({super.key, required this.languageChosen});

  @override
  Widget build(BuildContext context) {
    // Rebuild the whole app when the language changes.
    return ValueListenableBuilder<String>(
      valueListenable: LanguageService.current,
      builder: (context, lang, _) => MaterialApp(
        title: 'Health AI Assistant',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
        home: languageChosen ? const HomeScreen() : const LanguageSelectionScreen(),
      ),
    );
  }
}
