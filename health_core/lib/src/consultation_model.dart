/// Core data types. Answers are stored as language-neutral enums/ids,
/// never as display strings like "Haan", so logic works in every language.
library;

enum Answer { yes, no, unsure }

enum QuestionType { yesNo, choice }

/// Overall urgency, ordered from least to most urgent.
enum TriageLevel { routine, clinicianReview, urgentReferral }

class Question {
  final String id;
  final QuestionType type;

  /// Option ids for [QuestionType.choice] questions.
  final List<String> options;

  /// Question is only asked when every listed answer matches.
  /// Values are either an [Answer] or a choice option id.
  final Map<String, Object> showIf;

  /// WHO IMCI-style general danger sign: a "yes" ends questioning early.
  final bool isDangerSign;

  const Question({
    required this.id,
    this.type = QuestionType.yesNo,
    this.options = const [],
    this.showIf = const {},
    this.isDangerSign = false,
  });
}

/// One rule-engine output. [reasonIds] point at the answers that triggered
/// it, so the health worker can see *why* something was suggested.
class Suggestion {
  final String id;
  final TriageLevel level;
  final List<String> reasonIds;

  const Suggestion(this.id, this.level, [this.reasonIds = const []]);

  Map<String, dynamic> toJson() =>
      {'id': id, 'level': level.name, 'reasons': reasonIds};

  factory Suggestion.fromJson(Map<String, dynamic> json) => Suggestion(
        json['id'] as String,
        TriageLevel.values.byName(json['level'] as String),
        List<String>.from(json['reasons'] as List? ?? const []),
      );
}

class Consultation {
  final String id;
  final DateTime createdAt;
  final String languageCode;
  final String freeText;

  /// question id -> Answer name ("yes"/"no"/"unsure") or choice option id.
  final Map<String, String> answers;

  /// Answers taken from the free-text description rather than tapped.
  final List<String> prefilledIds;
  final TriageLevel level;

  /// Exactly what was shown to the worker, so history doesn't change if
  /// the rules are updated later.
  final List<Suggestion> suggestions;
  final bool confirmedByWorker;
  final bool synced;

  Consultation({
    required this.id,
    required this.createdAt,
    required this.languageCode,
    required this.freeText,
    required this.answers,
    this.prefilledIds = const [],
    required this.level,
    required this.suggestions,
    this.confirmedByWorker = false,
    this.synced = false,
  });

  Consultation copyWith({bool? confirmedByWorker, bool? synced}) => Consultation(
        id: id,
        createdAt: createdAt,
        languageCode: languageCode,
        freeText: freeText,
        answers: answers,
        prefilledIds: prefilledIds,
        level: level,
        suggestions: suggestions,
        confirmedByWorker: confirmedByWorker ?? this.confirmedByWorker,
        synced: synced ?? this.synced,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'createdAt': createdAt.toIso8601String(),
        'languageCode': languageCode,
        'freeText': freeText,
        'answers': answers,
        'prefilledIds': prefilledIds,
        'level': level.name,
        'suggestions': suggestions.map((e) => e.toJson()).toList(),
        'confirmedByWorker': confirmedByWorker,
        'synced': synced,
      };

  factory Consultation.fromJson(Map<String, dynamic> json) => Consultation(
        id: json['id'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        languageCode: json['languageCode'] as String,
        freeText: json['freeText'] as String? ?? '',
        answers: Map<String, String>.from(json['answers'] as Map),
        prefilledIds: List<String>.from(json['prefilledIds'] as List? ?? const []),
        level: TriageLevel.values.byName(json['level'] as String),
        suggestions: [
          for (final e in json['suggestions'] as List? ?? const [])
            Suggestion.fromJson(Map<String, dynamic>.from(e as Map)),
        ],
        confirmedByWorker: json['confirmedByWorker'] as bool? ?? false,
        synced: json['synced'] as bool? ?? false,
      );
}
