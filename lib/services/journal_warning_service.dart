class JournalWarningService {
  const JournalWarningService._();

  static const _criticalTerms = [
    'suicide',
    'kill myself',
    'end my life',
    'self harm',
    'self-harm',
    'hurt myself',
    'i want to die',
    'want to die',
  ];

  static const _elevatedTerms = [
    'hopeless',
    'worthless',
    'depressed',
    'depression',
    'panic',
    'anxiety',
    'breakdown',
    'give up',
    'cannot cope',
    "can't cope",
  ];

  static const _stressTerms = [
    'stress',
    'stressed',
    'stressful',
    'burnout',
    'burned out',
    'overwhelmed',
    'exhausted',
    'tired',
    'drained',
    'pressure',
  ];

  static JournalWarningSummary analyze(String text) {
    final findings = <JournalWarningFinding>[];
    final lines = text
        .split(RegExp(r'[\r\n.!?]+'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty);

    for (final line in lines) {
      final finding = _findingForLine(line);
      if (finding == null) continue;

      findings.add(finding);
      if (findings.length >= 3) break;
    }

    return JournalWarningSummary(findings: findings);
  }

  static List<String> extractWarningSnippets(String text) {
    return analyze(text).snippets;
  }

  static JournalWarningFinding? _findingForLine(String line) {
    final lower = _normalizeForMatching(line);

    final critical = _matchedTerms(lower, _criticalTerms);
    if (critical.isNotEmpty) {
      return JournalWarningFinding(
        snippet: _limitSnippet(line),
        severity: JournalWarningSeverity.critical,
        weight: 1.0,
        matchedTerms: critical,
      );
    }

    final elevated = _matchedTerms(lower, _elevatedTerms);
    if (elevated.isNotEmpty) {
      return JournalWarningFinding(
        snippet: _limitSnippet(line),
        severity: JournalWarningSeverity.elevated,
        weight: 0.65,
        matchedTerms: elevated,
      );
    }

    final stress = _matchedTerms(lower, _stressTerms);
    if (stress.isNotEmpty) {
      return JournalWarningFinding(
        snippet: _limitSnippet(line),
        severity: JournalWarningSeverity.stress,
        weight: 0.3,
        matchedTerms: stress,
      );
    }

    return null;
  }

  static List<String> _matchedTerms(String lower, List<String> terms) {
    return terms
        .where((term) => lower.contains(_normalizeForMatching(term)))
        .take(3)
        .toList();
  }

  static String _normalizeForMatching(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static String _limitSnippet(String value) {
    const maxLength = 120;
    final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();

    if (normalized.length <= maxLength) {
      return normalized;
    }

    return '${normalized.substring(0, maxLength).trimRight()}...';
  }
}

enum JournalWarningSeverity {
  none,
  stress,
  elevated,
  critical;

  String get label {
    switch (this) {
      case JournalWarningSeverity.critical:
        return 'Critical';
      case JournalWarningSeverity.elevated:
        return 'Elevated';
      case JournalWarningSeverity.stress:
        return 'Stress';
      case JournalWarningSeverity.none:
        return 'None';
    }
  }
}

class JournalWarningFinding {
  const JournalWarningFinding({
    required this.snippet,
    required this.severity,
    required this.weight,
    required this.matchedTerms,
  });

  final String snippet;
  final JournalWarningSeverity severity;
  final double weight;
  final List<String> matchedTerms;

  Map<String, dynamic> toJson() {
    return {
      'snippet': snippet,
      'severity': severity.name,
      'weight': weight,
      'matchedTerms': matchedTerms,
    };
  }
}

class JournalWarningSummary {
  const JournalWarningSummary({required this.findings});

  final List<JournalWarningFinding> findings;

  List<String> get snippets {
    return findings.map((finding) => finding.snippet).toList();
  }

  double get weight {
    if (findings.isEmpty) return 0;

    return findings
        .map((finding) => finding.weight)
        .reduce((a, b) => a > b ? a : b);
  }

  JournalWarningSeverity get severity {
    if (findings.any(
      (finding) => finding.severity == JournalWarningSeverity.critical,
    )) {
      return JournalWarningSeverity.critical;
    }
    if (findings.any(
      (finding) => finding.severity == JournalWarningSeverity.elevated,
    )) {
      return JournalWarningSeverity.elevated;
    }
    if (findings.any(
      (finding) => finding.severity == JournalWarningSeverity.stress,
    )) {
      return JournalWarningSeverity.stress;
    }

    return JournalWarningSeverity.none;
  }

  List<Map<String, dynamic>> toJsonList() {
    return findings.map((finding) => finding.toJson()).toList();
  }
}
