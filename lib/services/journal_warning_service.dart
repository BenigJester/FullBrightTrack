class JournalWarningService {
  const JournalWarningService._();

  static const _terms = [
    'suicide',
    'kill myself',
    'end my life',
    'self harm',
    'self-harm',
    'hurt myself',
    'hopeless',
    'worthless',
    'depressed',
    'depression',
    'panic',
    'anxiety',
    'burnout',
    'breakdown',
    'give up',
  ];

  static List<String> extractWarningSnippets(String text) {
    final snippets = <String>[];
    final lines = text
        .split(RegExp(r'[\r\n.!?]+'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty);

    for (final line in lines) {
      final lower = line.toLowerCase();
      final matched = _terms.any(lower.contains);
      if (!matched) continue;

      snippets.add(_limitSnippet(line));
      if (snippets.length >= 3) break;
    }

    return snippets;
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
