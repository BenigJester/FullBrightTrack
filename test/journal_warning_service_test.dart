import 'package:flutter_test/flutter_test.dart';
import 'package:productivity_and_wellbeing/services/journal_warning_service.dart';

void main() {
  test('detects Philippine language critical phrases locally', () {
    final tagalog = JournalWarningService.analyze('Ayoko na mabuhay.');
    final cebuano = JournalWarningService.analyze('Dili na ko ganahan mabuhi.');

    expect(tagalog.severity, JournalWarningSeverity.critical);
    expect(cebuano.severity, JournalWarningSeverity.critical);
    expect(tagalog.snippets, contains('do not want to live'));
    expect(cebuano.snippets, contains('do not want to live'));
  });

  test(
    'critical snippets use canonical labels instead of raw journal text',
    () {
      const privateText = 'Gusto ko mamatay because of a private reason.';
      final summary = JournalWarningService.analyze(privateText);

      expect(summary.severity, JournalWarningSeverity.critical);
      expect(summary.snippets.join(' '), contains('want to die'));
      expect(summary.snippets.join(' '), isNot(contains('private reason')));
      expect(summary.snippets.join(' '), isNot(contains('Gusto ko mamatay')));
    },
  );

  test('Philippine language elevated phrases still match warning terms', () {
    final summary = JournalWarningService.analyze('Wala nang pag asa.');

    expect(summary.severity, JournalWarningSeverity.elevated);
    expect(summary.weight, 0.65);
    expect(summary.snippets, isEmpty);
  });

  test('does not flag energetic or profane wording without stress meaning', () {
    final summary = JournalWarningService.analyze(
      "I'll rule the world and fuck it.",
    );

    expect(summary.severity, JournalWarningSeverity.none);
    expect(summary.weight, 0);
    expect(summary.snippets, isEmpty);
  });

  test('matches warning words as words instead of partial text', () {
    final neutral = JournalWarningService.analyze(
      'This is a stressfulness test.',
    );
    final stressed = JournalWarningService.analyze('I feel stressed today.');

    expect(neutral.severity, JournalWarningSeverity.none);
    expect(stressed.severity, JournalWarningSeverity.stress);
    expect(stressed.weight, 0.3);
  });

  test('detects harm toward others as a critical warning label', () {
    final summary = JournalWarningService.analyze(
      'I feel like I might hurt someone tomorrow.',
    );

    expect(summary.severity, JournalWarningSeverity.critical);
    expect(summary.snippets.join(' '), contains('harm toward others'));
    expect(summary.snippets.join(' '), isNot(contains('tomorrow')));
  });
}
