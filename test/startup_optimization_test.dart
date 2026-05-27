import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('loading screen does not use artificial startup delays', () {
    final source = File('lib/screens/loading_screen.dart').readAsStringSync();

    expect(source, isNot(contains('Future.delayed')));
    expect(source, contains('Future.wait'));
    expect(source, contains('_setLoadingText'));
    expect(source, contains('HomeTabService.loadCached'));
    expect(source, contains('unawaited'));
  });

  test('startup services use range queries for historical data', () {
    final homeSource = File(
      'lib/services/hometab_service.dart',
    ).readAsStringSync();
    final streakSource = File(
      'lib/services/streak_service.dart',
    ).readAsStringSync();
    final leaderboardSource = File(
      'lib/services/leaderboard_service.dart',
    ).readAsStringSync();

    expect(homeSource, contains('where(FieldPath.documentId'));
    expect(streakSource, contains('where(FieldPath.documentId'));
    expect(leaderboardSource, contains('where(FieldPath.documentId'));
  });
}
