import 'package:flutter/material.dart';

class SummaryScreen extends StatelessWidget {
  final List<Map<String, String>> conversation;
  final List<Map<String, String>> suggestions;

  const SummaryScreen({
    super.key,
    required this.conversation,
    required this.suggestions,
  });
  @override
  Widget build(BuildContext context) {
    // Pair questions with answers
    final List<Map<String, String>> pairs = [];
    for (int i = 0; i < conversation.length; i += 2) {
      if (i + 1 < conversation.length) {
        pairs.add({
          "question": conversation[i]["text"]!,
          "answer": conversation[i + 1]["text"]!,
        });
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Consultation Summary"),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Symptom Summary",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),

            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: pairs.map((pair) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.check_circle, size: 18, color: Colors.teal),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  pair["question"]!,
                                  style: const TextStyle(fontSize: 13, color: Colors.grey),
                                ),
                                Text(
                                  pair["answer"]!,
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),

            const SizedBox(height: 28),
            const Text(
              "Safe Suggestions",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                "Yeh sirf sujhav hai. Antim faisla aapka hai. AI kisi bhi bimari ka diagnosis nahi karta.",
                style: TextStyle(fontSize: 13, color: Colors.redAccent),
              ),
            ),
            const SizedBox(height: 16),

            _suggestionCard(
              icon: Icons.monitor_heart,
              title: "Common Checks",
              content: "Temperature, oxygen level (agar available ho), basic physical examination.",
            ),
            _suggestionCard(
              icon: Icons.science,
              title: "Possible Basic Tests",
              content: "Agar clinic mein available ho: Malaria test, Blood sugar, Basic blood count.",
            ),
            _suggestionCard(
              icon: Icons.local_hospital,
              title: "Referral Suggestion",
              content: "Agar danger signs hain (saans lene mein takleef, bahut zyada bukhar, etc.) to higher facility refer karne ka soch sakte hain.",
            ),

            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () {
                  Navigator.popUntil(context, (route) => route.isFirst);
                },
                child: const Text("Finish & Return Home", style: TextStyle(fontSize: 16)),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _suggestionCard({required IconData icon, required String title, required String content}) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: Icon(icon, color: Colors.teal, size: 28),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(content),
      ),
    );
  }
}
