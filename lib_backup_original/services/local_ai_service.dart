class LocalAIService {
  // Current state of symptoms
  Map<String, String> symptoms = {};

  // All possible questions with conditions
  final List<Map<String, dynamic>> questionBank = [
    {
      "id": "fever",
      "question": "Kya patient ko bukhar hai?",
      "type": "yes_no",
    },
    {
      "id": "fever_days",
      "question": "Bukhar kitne din se hai?",
      "type": "text",
      "showIf": {"fever": "Haan"},
    },
    {
      "id": "cough",
      "question": "Kya khansi hai?",
      "type": "yes_no",
    },
    {
      "id": "breathing",
      "question": "Kya saans lene mein takleef hai?",
      "type": "yes_no",
    },
    {
      "id": "vomit_diarrhea",
      "question": "Kya ulti ya dast ho rahe hain?",
      "type": "yes_no",
    },
    {
      "id": "weakness",
      "question": "Kya patient ko bahut kamzori feel ho rahi hai?",
      "type": "yes_no",
    },
    {
      "id": "danger_sign",
      "question": "Kya patient ko bahut zyada neend aa rahi hai ya respond nahi kar raha?",
      "type": "yes_no",
      "showIf": {"breathing": "Haan"},
    },
  ];

  int currentIndex = 0;

  // Get next question based on rules
  String? getNextQuestion() {
    while (currentIndex < questionBank.length) {
      final q = questionBank[currentIndex];

      // Check condition
      if (q["showIf"] != null) {
        final condition = q["showIf"] as Map<String, String>;
        bool shouldShow = true;
        condition.forEach((key, value) {
          if (symptoms[key] != value) {
            shouldShow = false;
          }
        });
        if (!shouldShow) {
          currentIndex++;
          continue;
        }
      }

      return q["question"];
    }
    return null; // No more questions
  }

  // Save answer
  void saveAnswer(String answer) {
    if (currentIndex < questionBank.length) {
      final q = questionBank[currentIndex];
      symptoms[q["id"]] = answer;
      currentIndex++;
    }
  }

  // Generate summary text
  String generateSummary() {
    final buffer = StringBuffer();
    symptoms.forEach((key, value) {
      buffer.writeln("• $key: $value");
    });
    return buffer.toString();
  }

  // Simple safe suggestions based on rules
  List<Map<String, String>> getSafeSuggestions() {
    List<Map<String, String>> suggestions = [
      {
        "title": "Common Checks",
        "content": "Temperature, oxygen level (agar available ho), basic physical examination."
      },
    ];

    if (symptoms["fever"] == "Haan") {
      suggestions.add({
        "title": "Possible Basic Tests",
        "content": "Malaria test, Blood sugar, Basic blood count (agar clinic mein available ho)."
      });
    }

    if (symptoms["breathing"] == "Haan" || symptoms["danger_sign"] == "Haan") {
      suggestions.add({
        "title": "Referral Suggestion",
        "content": "Danger signs present. Higher facility refer karne ka soch sakte hain."
      });
    } else {
      suggestions.add({
        "title": "Referral Suggestion",
        "content": "Abhi ke liye is clinic mein observation continue kar sakte hain."
      });
    }

    return suggestions;
  }

  void reset() {
    symptoms.clear();
    currentIndex = 0;
  }
}
