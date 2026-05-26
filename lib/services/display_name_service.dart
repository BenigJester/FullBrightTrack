class DisplayNameService {
  const DisplayNameService._();

  static const minLength = 3;
  static const maxLength = 6;
  static final _spacePattern = RegExp(r'\s+');

  static String normalize(String? value) {
    return (value ?? '').trim().replaceAll(_spacePattern, ' ');
  }

  static String cleanForDisplay(String? value, {String fallback = 'User'}) {
    final normalized = normalize(value);
    if (normalized.isEmpty) return fallback;

    if (normalized.length <= maxLength) {
      return normalized;
    }

    return normalized.substring(0, maxLength).trimRight();
  }

  static String firstName(String? value, {String fallback = 'User'}) {
    final cleaned = cleanForDisplay(value, fallback: fallback);
    if (cleaned == fallback) return fallback;

    return cleaned.split(' ').first;
  }

  static String? validationError(String value) {
    final normalized = normalize(value);

    if (normalized.isEmpty) {
      return 'Name cannot be empty';
    }

    if (normalized.length < minLength) {
      return 'Name must be at least $minLength characters';
    }

    if (normalized.length > maxLength) {
      return 'Name must be $maxLength characters or fewer';
    }

    return null;
  }
}
