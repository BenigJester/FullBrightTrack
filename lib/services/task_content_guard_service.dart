class TaskContentGuardService {
  const TaskContentGuardService._();

  static const _blockedPatterns = <_TaskContentPattern>[
    _TaskContentPattern(
      pattern: 'kill myself',
      label: 'self-harm language',
      guidance:
          'Please rewrite this as a safe support task, such as "contact a trusted person" or "ask for help today".',
    ),
    _TaskContentPattern(
      pattern: 'i will kill myself',
      label: 'self-harm language',
      guidance:
          'Please rewrite this as an immediate support action, such as "call a trusted person now".',
    ),
    _TaskContentPattern(
      pattern: 'going to kill myself',
      label: 'self-harm language',
      guidance:
          'Please rewrite this as an immediate support action before saving.',
    ),
    _TaskContentPattern(
      pattern: 'suicide',
      label: 'self-harm language',
      guidance:
          'Please create a task focused on immediate support instead of harmful wording.',
    ),
    _TaskContentPattern(
      pattern: 'end my life',
      label: 'self-harm language',
      guidance:
          'Please rewrite this as a support action so the task stays safe and constructive.',
    ),
    _TaskContentPattern(
      pattern: 'hurt myself',
      label: 'self-harm language',
      guidance: 'Please rewrite this as a safe support task before saving it.',
    ),
    _TaskContentPattern(
      pattern: 'harm myself',
      label: 'self-harm language',
      guidance: 'Please rewrite this as a safe support task before saving it.',
    ),
    _TaskContentPattern(
      pattern: 'attack',
      label: 'harmful instruction',
      guidance:
          'Tasks should not include plans to harm another person. Please rewrite it as a safe action.',
    ),
    _TaskContentPattern(
      pattern: 'hurt someone',
      label: 'harmful instruction',
      guidance:
          'Tasks should not include threats or harmful plans. Please rewrite it professionally.',
    ),
    _TaskContentPattern(
      pattern: 'cheat on exam',
      label: 'academic misconduct',
      guidance: 'Please change this to an honest study or preparation task.',
    ),
    _TaskContentPattern(
      pattern: 'forge',
      label: 'dishonest action',
      guidance:
          'Please rewrite the task as a legitimate school or personal responsibility.',
    ),
  ];

  static TaskContentGuardResult validate(String title) {
    final normalized = _normalize(title);
    if (normalized.isEmpty) {
      return const TaskContentGuardResult.allowed();
    }

    if (_looksLikeSelfHarmIntent(normalized)) {
      return const TaskContentGuardResult.blocked(
        label: 'self-harm language',
        guidance:
            'Please rewrite this as a safe support task, such as "message my adviser" or "call a trusted person".',
      );
    }

    for (final pattern in _blockedPatterns) {
      if (_containsPhrase(normalized, pattern.pattern)) {
        return TaskContentGuardResult.blocked(
          label: pattern.label,
          guidance: pattern.guidance,
        );
      }
    }

    return const TaskContentGuardResult.allowed();
  }

  static String _normalize(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static bool _containsPhrase(String text, String phrase) {
    final normalizedPhrase = _normalize(phrase);
    return ' $text '.contains(' $normalizedPhrase ');
  }

  static bool _looksLikeSelfHarmIntent(String text) {
    final firstPerson = RegExp(r'\b(i|me|myself|ako|ko)\b').hasMatch(text);
    final harmIntent = RegExp(
      r'\b(kill myself|end my life|hurt myself|harm myself|suicide|magpakamatay|mamatay|saktan sarili)\b',
    ).hasMatch(text);
    return firstPerson && harmIntent;
  }
}

class TaskContentGuardResult {
  const TaskContentGuardResult.allowed()
    : isAllowed = true,
      label = '',
      guidance = '';

  const TaskContentGuardResult.blocked({
    required this.label,
    required this.guidance,
  }) : isAllowed = false;

  final bool isAllowed;
  final String label;
  final String guidance;
}

class _TaskContentPattern {
  const _TaskContentPattern({
    required this.pattern,
    required this.label,
    required this.guidance,
  });

  final String pattern;
  final String label;
  final String guidance;
}
