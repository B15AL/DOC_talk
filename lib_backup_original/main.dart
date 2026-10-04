import 'package:flutter/material.dart';
import 'services/language_service.dart';
import 'screens/language_selection_screen.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Health AI Assistant',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.teal,
        useMaterial3: true,
      ),
      // TEMPORARY: Force language selection for testing
      home: const LanguageSelectionScreen(),

      // Later we will switch back to this:
      // home: FutureBuilder<String?>(
      //   future: LanguageService.getSavedLanguage(),
      //   builder: (context, snapshot) {
      //     if (snapshot.connectionState == ConnectionState.waiting) {
      //       return const Scaffold(body: Center(child: CircularProgressIndicator()));
      //     }
      //     if (snapshot.data == null) {
      //       return const LanguageSelectionScreen();
      //     }
      //     return const HomeScreen();
      //   },
      // ),
    );
  }
}
