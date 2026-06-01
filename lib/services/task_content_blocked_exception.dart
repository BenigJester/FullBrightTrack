import 'task_content_guard_service.dart';

class TaskContentBlockedException implements Exception {
  const TaskContentBlockedException(this.result);

  final TaskContentGuardResult result;

  @override
  String toString() => 'TaskContentBlockedException: ${result.label}';
}
