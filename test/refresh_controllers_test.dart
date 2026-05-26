import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:productivity_and_wellbeing/models/app_data.dart';
import 'package:productivity_and_wellbeing/screens/home_tab.dart';
import 'package:productivity_and_wellbeing/screens/journal_history.dart';
import 'package:productivity_and_wellbeing/screens/journal_screen.dart';
import 'package:productivity_and_wellbeing/screens/mood_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _withAppData(Widget child) {
  return ChangeNotifierProvider(
    create: (_) => AppData(),
    child: MaterialApp(home: Scaffold(body: child)),
  );
}

void main() {
  testWidgets('home tab has pull to refresh', (tester) async {
    final now = DateTime.now();
    SharedPreferences.setMockInitialValues({
      'last_mood_popup': '${now.year}-${now.month}-${now.day}',
    });

    await tester.pumpWidget(_withAppData(const HomeTab()));

    expect(find.byType(RefreshIndicator), findsOneWidget);
    expect(find.byType(Scrollable), findsWidgets);
  });

  testWidgets('mood screen has pull to refresh', (tester) async {
    await tester.pumpWidget(_withAppData(const MoodScreen()));

    expect(find.byType(RefreshIndicator), findsOneWidget);
    expect(find.byType(Scrollable), findsOneWidget);
  });

  testWidgets('journal screen has pull to refresh', (tester) async {
    await tester.pumpWidget(_withAppData(const JournalScreen()));

    expect(find.byType(RefreshIndicator), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(RefreshIndicator),
        matching: find.byType(Scrollable),
      ),
      findsWidgets,
    );
  });

  testWidgets('journal history has pull to refresh', (tester) async {
    await tester.pumpWidget(_withAppData(const JournalHistoryScreen()));

    expect(find.byType(RefreshIndicator), findsOneWidget);
    expect(find.byType(CustomScrollView), findsOneWidget);
  });

  test('tasks and more screens keep refresh controllers wired', () {
    final tasksSource = File('lib/screens/tasks_tab.dart').readAsStringSync();
    final moreSource = File('lib/screens/other_screen.dart').readAsStringSync();

    expect(tasksSource, contains('RefreshIndicator'));
    expect(tasksSource, contains('_refreshTasks'));
    expect(moreSource, contains('RefreshIndicator'));
    expect(moreSource, contains('_refreshProfile'));
  });
}
