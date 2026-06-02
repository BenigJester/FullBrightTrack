class JournalWarningService {
  const JournalWarningService._();

  static const _criticalTerms = [
    _WarningTerm('suicide', 'suicide'),
    _WarningTerm('kill myself', 'self-harm intent'),
    _WarningTerm('end my life', 'want to die'),
    _WarningTerm('self harm', 'self-harm'),
    _WarningTerm('self-harm', 'self-harm'),
    _WarningTerm('hurt myself', 'self-harm'),
    _WarningTerm('i want to die', 'want to die'),
    _WarningTerm('want to die', 'want to die'),
    _WarningTerm('gusto kong mamatay', 'want to die'),
    _WarningTerm('gusto ko mamatay', 'want to die'),
    _WarningTerm('gusto ko nang mamatay', 'want to die'),
    _WarningTerm('ayoko na mabuhay', 'do not want to live'),
    _WarningTerm('hindi ko na kaya mabuhay', 'do not want to live'),
    _WarningTerm('tapusin buhay ko', 'end my life'),
    _WarningTerm('tapusin ang buhay ko', 'end my life'),
    _WarningTerm('magpakamatay', 'suicide'),
    _WarningTerm('magpapakamatay', 'suicide'),
    _WarningTerm('saktan sarili ko', 'self-harm'),
    _WarningTerm('saktan ang sarili ko', 'self-harm'),
    _WarningTerm('sasaktan ko sarili ko', 'self-harm'),
    _WarningTerm('gusto ko na mamatay', 'want to die'),
    _WarningTerm('dili nako ganahan mabuhi', 'do not want to live'),
    _WarningTerm('di nako ganahan mabuhi', 'do not want to live'),
    _WarningTerm('dili na ko ganahan mabuhi', 'do not want to live'),
    _WarningTerm('patyon nako akong kaugalingon', 'self-harm intent'),
    _WarningTerm('kill someone', 'harm toward others'),
    _WarningTerm('kill them', 'harm toward others'),
    _WarningTerm('kill him', 'harm toward others'),
    _WarningTerm('kill her', 'harm toward others'),
    _WarningTerm('hurt someone', 'harm toward others'),
    _WarningTerm('hurt them', 'harm toward others'),
    _WarningTerm('attack someone', 'harm toward others'),
    _WarningTerm('stab someone', 'harm toward others'),
    _WarningTerm('shoot someone', 'harm toward others'),
    _WarningTerm('bomb', 'violent threat'),
    _WarningTerm('burn the school', 'violent threat'),
    _WarningTerm('patayin siya', 'harm toward others'),
    _WarningTerm('papatayin ko siya', 'harm toward others'),
    _WarningTerm('saktan siya', 'harm toward others'),
    _WarningTerm('sasaktan ko siya', 'harm toward others'),
    _WarningTerm('patyon siya', 'harm toward others'),
  ];

  static const _elevatedTerms = [
    _WarningTerm('hopeless', 'hopeless'),
    _WarningTerm('worthless', 'worthless'),
    _WarningTerm('depressed', 'depression'),
    _WarningTerm('depression', 'depression'),
    _WarningTerm('panic', 'panic'),
    _WarningTerm('anxiety', 'anxiety'),
    _WarningTerm('breakdown', 'breakdown'),
    _WarningTerm('give up', 'giving up'),
    _WarningTerm('cannot cope', 'cannot cope'),
    _WarningTerm('cant cope', 'cannot cope'),
    _WarningTerm("can't cope", 'cannot cope'),
    _WarningTerm('wala nang pag asa', 'hopeless'),
    _WarningTerm('wala ng pag asa', 'hopeless'),
    _WarningTerm('walang pag asa', 'hopeless'),
    _WarningTerm('walang kwenta', 'worthless'),
    _WarningTerm('wala akong kwenta', 'worthless'),
    _WarningTerm('depress', 'depression'),
    _WarningTerm('depressed ako', 'depression'),
    _WarningTerm('di ko na kaya', 'cannot cope'),
    _WarningTerm('hindi ko na kaya', 'cannot cope'),
    _WarningTerm('susuko na ako', 'giving up'),
    _WarningTerm('ayoko na', 'giving up'),
    _WarningTerm('panic ako', 'panic'),
    _WarningTerm('wala nay paglaum', 'hopeless'),
    _WarningTerm('di na nako kaya', 'cannot cope'),
    _WarningTerm('dili na nako kaya', 'cannot cope'),
    _WarningTerm('mosuko na ko', 'giving up'),
    _WarningTerm('explicit content', 'explicit content'),
    _WarningTerm('sexual threat', 'sexual threat'),
    _WarningTerm('harass', 'harassment'),
    _WarningTerm('blackmail', 'coercion'),
  ];

  static const _stressTerms = [
    _WarningTerm('stress', 'stress'),
    _WarningTerm('stressed', 'stress'),
    _WarningTerm('stressful', 'stress'),
    _WarningTerm('burnout', 'burnout'),
    _WarningTerm('burned out', 'burnout'),
    _WarningTerm('overwhelmed', 'overwhelmed'),
    _WarningTerm('exhausted', 'exhausted'),
    _WarningTerm('tired', 'tired'),
    _WarningTerm('drained', 'drained'),
    _WarningTerm('pressure', 'pressure'),
    _WarningTerm('pagod', 'tired'),
    _WarningTerm('pagod na pagod', 'exhausted'),
    _WarningTerm('sobrang pagod', 'exhausted'),
    _WarningTerm('naiistress', 'stress'),
    _WarningTerm('na stress', 'stress'),
    _WarningTerm('nastress', 'stress'),
    _WarningTerm('nakakapagod', 'tired'),
    _WarningTerm('naddrain', 'drained'),
    _WarningTerm('napapagod', 'tired'),
    _WarningTerm('kapoy', 'tired'),
    _WarningTerm('kapoy kaayo', 'exhausted'),
    _WarningTerm('kapoy na kaayo', 'exhausted'),
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

  static JournalWarningSummary fromAi({
    required String severity,
    required double weight,
    required String warningSignalTerm,
  }) {
    final normalizedSeverity = severity.trim().toLowerCase();
    final resolvedSeverity = switch (normalizedSeverity) {
      'critical' || 'high' => JournalWarningSeverity.critical,
      'elevated' || 'medium' => JournalWarningSeverity.elevated,
      'stress' || 'moderate' || 'low' => JournalWarningSeverity.stress,
      _ => JournalWarningSeverity.none,
    };

    if (resolvedSeverity == JournalWarningSeverity.none) {
      return const JournalWarningSummary(findings: []);
    }

    final term = warningSignalTerm.trim().isEmpty
        ? resolvedSeverity.label.toLowerCase()
        : warningSignalTerm.trim();

    return JournalWarningSummary(
      findings: [
        JournalWarningFinding(
          snippet: resolvedSeverity == JournalWarningSeverity.critical
              ? term
              : '',
          severity: resolvedSeverity,
          weight: weight.clamp(0, 1).toDouble(),
          matchedTerms: [term],
        ),
      ],
    );
  }

  static List<String> extractWarningSnippets(String text) {
    return analyze(text).snippets;
  }

  static JournalWarningFinding? _findingForLine(String line) {
    final lower = _normalizeForMatching(line);

    final critical = _matchedTerms(lower, _criticalTerms);
    if (critical.isNotEmpty) {
      return JournalWarningFinding(
        snippet: _safeSnippet(JournalWarningSeverity.critical, critical),
        severity: JournalWarningSeverity.critical,
        weight: 1.0,
        matchedTerms: critical,
      );
    }

    final elevated = _matchedTerms(lower, _elevatedTerms);
    if (elevated.isNotEmpty) {
      return JournalWarningFinding(
        snippet: _safeSnippet(JournalWarningSeverity.elevated, elevated),
        severity: JournalWarningSeverity.elevated,
        weight: 0.65,
        matchedTerms: elevated,
      );
    }

    final stress = _matchedTerms(lower, _stressTerms);
    if (stress.isNotEmpty) {
      return JournalWarningFinding(
        snippet: _safeSnippet(JournalWarningSeverity.stress, stress),
        severity: JournalWarningSeverity.stress,
        weight: 0.3,
        matchedTerms: stress,
      );
    }

    return null;
  }

  static List<String> _matchedTerms(String lower, List<_WarningTerm> terms) {
    final matches = terms
        .where((term) => _containsNormalizedTerm(lower, term.pattern))
        .map((term) => term.canonical)
        .toList();

    return _dedupeMatches(_removeContainedMatches(matches)).take(3).toList();
  }

  static List<String> _removeContainedMatches(List<String> matches) {
    return matches.where((term) {
      final normalized = _normalizeForMatching(term);
      return !matches.any((other) {
        final otherNormalized = _normalizeForMatching(other);
        return otherNormalized != normalized &&
            otherNormalized.contains(normalized);
      });
    }).toList();
  }

  static List<String> _dedupeMatches(List<String> matches) {
    final seen = <String>{};
    final deduped = <String>[];

    for (final match in matches) {
      final normalized = _normalizeForMatching(match);
      if (seen.add(normalized)) {
        deduped.add(match);
      }
    }

    return deduped;
  }

  static String _normalizeForMatching(String value) {
    return _foldLatin(value.toLowerCase())
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static bool _containsNormalizedTerm(String normalizedText, String pattern) {
    final normalizedPattern = _normalizeForMatching(pattern);
    if (normalizedPattern.isEmpty) return false;

    final textWithBoundaries = ' $normalizedText ';
    final patternWithBoundaries = ' $normalizedPattern ';
    return textWithBoundaries.contains(patternWithBoundaries);
  }

  static String _foldLatin(String value) {
    const replacements = {
      'á': 'a',
      'à': 'a',
      'â': 'a',
      'ä': 'a',
      'ã': 'a',
      'å': 'a',
      'é': 'e',
      'è': 'e',
      'ê': 'e',
      'ë': 'e',
      'í': 'i',
      'ì': 'i',
      'î': 'i',
      'ï': 'i',
      'ó': 'o',
      'ò': 'o',
      'ô': 'o',
      'ö': 'o',
      'õ': 'o',
      'ú': 'u',
      'ù': 'u',
      'û': 'u',
      'ü': 'u',
      'ñ': 'n',
      'ç': 'c',
    };

    var folded = value;
    for (final entry in replacements.entries) {
      folded = folded.replaceAll(entry.key, entry.value);
    }

    return folded;
  }

  static String _safeSnippet(
    JournalWarningSeverity severity,
    List<String> matchedTerms,
  ) {
    if (severity != JournalWarningSeverity.critical) return '';

    return matchedTerms.take(2).join(', ');
  }
}

class _WarningTerm {
  const _WarningTerm(this.pattern, this.canonical);

  final String pattern;
  final String canonical;
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
      if (snippet.isNotEmpty) 'snippet': snippet,
      'severity': severity.name,
      'weight': weight,
      if (severity == JournalWarningSeverity.critical)
        'matchedTerms': matchedTerms,
    };
  }
}

class JournalWarningSummary {
  const JournalWarningSummary({required this.findings});

  final List<JournalWarningFinding> findings;

  List<String> get snippets {
    return findings
        .where(
          (finding) =>
              finding.severity == JournalWarningSeverity.critical &&
              finding.snippet.isNotEmpty,
        )
        .map((finding) => finding.snippet)
        .toList();
  }

  List<String> get signatures {
    return findings
        .map(
          (finding) =>
              '${finding.severity.name}:${finding.matchedTerms.take(3).join(',')}',
        )
        .toList();
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
