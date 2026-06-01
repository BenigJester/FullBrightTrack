import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:productivity_and_wellbeing/screens/tasks_tab.dart';
import 'package:productivity_and_wellbeing/services/task_content_guard_service.dart';

void main() {
  test('task parser allows documents without a deadline', () {
    final task = Task.fromFirestore('flexible', {'title': 'No deadline'});

    expect(task, isNotNull);
    expect(task!.deadline, isNull);
    expect(task.isOverdue, isFalse);
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

  test('task parser adds flags from task title', () {
    final task = Task.fromFirestore('task-2', {
      'title': 'Urgent exam review',
      'deadline': Timestamp.fromDate(DateTime(2030, 1, 1, 8)),
    });

    expect(task, isNotNull);
    expect(
      task!.flags.map((flag) => flag.label),
      containsAll(['Urgent', 'Exam', 'Study']),
    );
  });

  test('task content guard blocks self-harm task wording', () {
    final result = TaskContentGuardService.validate(
      'I will kill myself tomorrow',
    );

    expect(result.isAllowed, isFalse);
    expect(result.label, contains('self-harm'));
  });
}
