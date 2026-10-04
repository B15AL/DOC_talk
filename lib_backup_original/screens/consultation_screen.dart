import 'package:flutter/material.dart';
import '../services/local_ai_service.dart';
import 'summary_screen.dart';

class ConsultationScreen extends StatefulWidget {
  const ConsultationScreen({super.key});

  @override
  State<ConsultationScreen> createState() => _ConsultationScreenState();
}

class _ConsultationScreenState extends State<ConsultationScreen> {
  final LocalAIService ai = LocalAIService();
  final List<Map<String, String>> conversation = [];
  String? currentQuestion;

  @override
  void initState() {
    super.initState();
    currentQuestion = ai.getNextQuestion();
  }

  void _answer(String answer) {
    if (currentQuestion == null) return;

    setState(() {
      // Add AI question
      conversation.add({
        "role": "ai",
        "text": currentQuestion!,
      });
      // Add user answer
      conversation.add({
        "role": "user",
        "text": answer,
      });

      // Save to Local AI
      ai.saveAnswer(answer);

      // Get next question
      currentQuestion = ai.getNextQuestion();

      // If no more questions → go to summary
      if (currentQuestion == null) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => SummaryScreen(
              conversation: conversation,
              suggestions: ai.getSafeSuggestions(),
            ),
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("New Consultation"),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // Progress
          LinearProgressIndicator(
            value: ai.currentIndex / ai.questionBank.length,
            backgroundColor: Colors.teal.shade50,
            color: Colors.teal,
            minHeight: 6,
          ),

          // Conversation
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: conversation.length + (currentQuestion != null ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == conversation.length && currentQuestion != null) {
                  return _buildAIMessage(currentQuestion!);
                }

                final msg = conversation[index];
                if (msg["role"] == "ai") {
                  return _buildAIMessage(msg["text"]!);
                } else {
                  return _buildUserMessage(msg["text"]!);
                }
              },
            ),
          ),

          // Answer buttons
          if (currentQuestion != null)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 4,
                    offset: Offset(0, -2),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => _answer("Haan"),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: const Text("Haan", style: TextStyle(fontSize: 17)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => _answer("Nahi"),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red.shade400,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: const Text("Nahi", style: TextStyle(fontSize: 17)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () => _answer("Mujhe sure nahi hai"),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: const BorderSide(color: Colors.orange),
                      ),
                      child: const Text(
                        "Mujhe sure nahi hai",
                        style: TextStyle(fontSize: 15, color: Colors.orange),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAIMessage(String text) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        decoration: BoxDecoration(
          color: Colors.teal.shade50,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(4),
            topRight: Radius.circular(16),
            bottomLeft: Radius.circular(16),
            bottomRight: Radius.circular(16),
          ),
        ),
        child: Text(text, style: const TextStyle(fontSize: 16)),
      ),
    );
  }

  Widget _buildUserMessage(String text) {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        decoration: BoxDecoration(
          color: Colors.blue.shade100,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(4),
            bottomLeft: Radius.circular(16),
            bottomRight: Radius.circular(16),
          ),
        ),
        child: Text(text, style: const TextStyle(fontSize: 16)),
      ),
    );
  }
}
