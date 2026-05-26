import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:productivity_and_wellbeing/screens/tasks_tab.dart';

void main() {
  test('task parser ignores documents without a valid deadline', () {
    final task = Task.fromFirestore('bad', {'title': 'No deadline'});

    expect(task, isNull);
  });

  test('task parser trims title and reads completion state', () {
    final deadline = Timestamp.fromDate(DateTime(2030, 1, 1, 8));
    final task = Task.fromFirestore('task-1', {
      'title': '  Study  ',
      'deadline': deadline,
      'isCompleted': true,
    });

    expect(task, isNotNull);
    expect(task!.title, 'Study');
    expect(task.isCompleted, isTrue);
    expect(task.deadline, DateTime(2030, 1, 1, 8));
  });
}
