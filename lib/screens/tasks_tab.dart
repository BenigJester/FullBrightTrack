import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../services/task_content_guard_service.dart';
import '../services/task_content_blocked_exception.dart';
import '../services/wellness_signal_service.dart';

class Task {
  final String id;
  final String title;
  final DateTime? deadline;
  final bool dateOnly;
  final bool isCompleted;
  final List<TaskFlag> flags;

  Task({
    required this.id,
    required this.title,
    required this.deadline,
    required this.dateOnly,
    required this.isCompleted,
    required this.flags,
  });

  bool get isOverdue =>
      deadline != null && !isCompleted && DateTime.now().isAfter(deadline!);

  static Task? fromFirestore(String id, Map<String, dynamic> data) {
    final rawDeadline = data['deadline'];
    final title = (data['title'] as String?)?.trim() ?? '';
    if (title.isEmpty) return null;

    return Task(
      id: id,
      title: title,
      deadline: rawDeadline is Timestamp ? rawDeadline.toDate() : null,
      dateOnly: data['dateOnly'] == true,
      isCompleted: data['isCompleted'] == true,
      flags: TaskFlag.detect(title),
    );
  }
}

class TaskFlag {
  const TaskFlag({
    required this.label,
    required this.color,
    required this.icon,
    required this.keywords,
  });

  final String label;
  final Color color;
  final IconData icon;
  final List<String> keywords;

  static const urgent = TaskFlag(
    label: 'Urgent',
    color: Colors.red,
    icon: Icons.priority_high_rounded,
    keywords: ['urgent', 'asap', 'immediately', 'emergency'],
  );
  static const exam = TaskFlag(
    label: 'Exam',
    color: Colors.deepPurple,
    icon: Icons.school_rounded,
    keywords: ['exam', 'quiz', 'test', 'midterm', 'final'],
  );
  static const assignment = TaskFlag(
    label: 'Assignment',
    color: Colors.blue,
    icon: Icons.assignment_rounded,
    keywords: ['assignment', 'homework', 'report', 'project', 'submit'],
  );
  static const study = TaskFlag(
    label: 'Study',
    color: Colors.teal,
    icon: Icons.menu_book_rounded,
    keywords: ['study', 'review', 'read', 'practice'],
  );
  static const personal = TaskFlag(
    label: 'Personal',
    color: Colors.orange,
    icon: Icons.self_improvement_rounded,
    keywords: ['rest', 'break', 'sleep', 'health', 'family'],
  );

  static const values = [urgent, exam, assignment, study, personal];

  static List<TaskFlag> detect(String title) {
    final normalized = title.toLowerCase();
    return values.where((flag) {
      return flag.keywords.any((keyword) => normalized.contains(keyword));
    }).toList();
  }
}

class TasksTab extends StatefulWidget {
  const TasksTab({super.key});

  @override
  State<TasksTab> createState() => _TasksTabState();
}

class _TasksTabState extends State<TasksTab> {
  String? _openSection = 'active';
  Timer? _refreshTimer;
  late final Stream<List<Task>> _tasksStream;

  @override
  void initState() {
    super.initState();
    _tasksStream = _createTasksStream();

    _refreshTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  CollectionReference<Map<String, dynamic>>? get _taskRef {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;

    return FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('tasks');
  }

  // ================= STREAM =================

  Stream<List<Task>> _createTasksStream() {
    StreamSubscription<User?>? authSubscription;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? taskSubscription;

    late final StreamController<List<Task>> controller;
    controller = StreamController<List<Task>>(
      onListen: () {
        authSubscription = FirebaseAuth.instance.authStateChanges().listen(
          (user) async {
            await taskSubscription?.cancel();
            taskSubscription = null;

            if (user == null) {
              if (!controller.isClosed) controller.add(const []);
              return;
            }

            final ref = FirebaseFirestore.instance
                .collection('users')
                .doc(user.uid)
                .collection('tasks');

            taskSubscription = ref.snapshots().listen(
              (snapshot) {
                final tasks = snapshot.docs
                    .map((doc) => Task.fromFirestore(doc.id, doc.data()))
                    .whereType<Task>()
                    .where((task) => task.title.isNotEmpty)
                    .toList();

                if (!controller.isClosed) controller.add(tasks);
              },
              onError: (Object error, StackTrace stackTrace) {
                final signedOut = FirebaseAuth.instance.currentUser == null;
                if (signedOut &&
                    error is FirebaseException &&
                    error.code == 'permission-denied') {
                  if (!controller.isClosed) controller.add(const []);
                  return;
                }

                if (!controller.isClosed) {
                  controller.addError(error, stackTrace);
                }
              },
            );
          },
          onError: (Object error, StackTrace stackTrace) {
            if (!controller.isClosed) {
              controller.addError(error, stackTrace);
            }
          },
        );
      },
      onCancel: () async {
        await taskSubscription?.cancel();
        await authSubscription?.cancel();
      },
    );

    return controller.stream;
  }

  // ================= CRUD =================

  Future<void> toggleTask(Task task, bool value) async {
    if (task.isCompleted || task.isOverdue) {
      return;
    }

    final taskRef = _taskRef;
    if (taskRef == null) return;

    await taskRef.doc(task.id).update({'isCompleted': value});
    await WellnessSignalService.publishCurrentUserSignals();
  }

  Future<void> addTask(
    String title,
    DateTime? deadline, {
    bool dateOnly = false,
  }) async {
    final trimmedTitle = title.trim();
    if (trimmedTitle.isEmpty) return;
    if (deadline != null && !deadline.isAfter(DateTime.now())) return;
    final guardResult = TaskContentGuardService.validate(trimmedTitle);
    if (!guardResult.isAllowed) {
      throw TaskContentBlockedException(guardResult);
    }

    final taskRef = _taskRef;
    if (taskRef == null) return;

    await taskRef.add({
      'title': trimmedTitle,
      'deadline': ?deadline,
      'dateOnly': dateOnly,
      'flags': TaskFlag.detect(trimmedTitle).map((flag) => flag.label).toList(),
      'isCompleted': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
    await WellnessSignalService.publishCurrentUserSignals();
  }

  Future<void> deleteTaskGroup({
    required String title,
    required List<Task> tasks,
  }) async {
    if (tasks.isEmpty) return;

    final taskRef = _taskRef;
    if (taskRef == null) return;

    final confirmed = await _showClearTasksDialog(
      context,
      title: title,
      count: tasks.length,
    );
    if (confirmed != true) return;

    final batch = FirebaseFirestore.instance.batch();
    for (final task in tasks.take(450)) {
      batch.delete(taskRef.doc(task.id));
    }

    await batch.commit();
    await WellnessSignalService.publishCurrentUserSignals();

    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text("$title tasks cleared"),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  Future<bool?> _showClearTasksDialog(
    BuildContext context, {
    required String title,
    required int count,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          title: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.delete_sweep_rounded,
                  color: Colors.red,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text("Clear $title tasks?")),
            ],
          ),
          content: Text(
            "This will permanently delete $count ${count == 1 ? "task" : "tasks"} from the $title section. This action cannot be undone.",
            style: TextStyle(color: Colors.grey.shade800, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Cancel"),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(context, true),
              icon: const Icon(Icons.delete_outline_rounded),
              label: const Text("Delete"),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showTaskBlockedDialog(
    BuildContext context,
    TaskContentGuardResult result,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          titlePadding: const EdgeInsets.fromLTRB(22, 22, 22, 0),
          contentPadding: const EdgeInsets.fromLTRB(22, 14, 22, 8),
          actionsPadding: const EdgeInsets.fromLTRB(22, 0, 22, 18),
          title: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.health_and_safety_rounded,
                  color: Colors.red,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  "Task needs revision",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "FullBrightTrack could not save this task because it may contain ${result.label}.",
                style: TextStyle(color: Colors.grey.shade800, height: 1.4),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  result.guidance,
                  style: TextStyle(
                    color: Colors.orange.shade900,
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.deepOrange,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(context),
              child: const Text("Edit task"),
            ),
          ],
        );
      },
    );
  }

  String _formatDateTime(DateTime dt, {bool dateOnly = false}) {
    if (dateOnly) {
      return "${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}";
    }

    return "${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} "
        "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
  }

  String? errorText;

  void _toggleSection(String section) {
    setState(() {
      _openSection = _openSection == section ? null : section;
    });
  }

  String _timeLeftLabel(DateTime? deadline, {bool dateOnly = false}) {
    if (deadline == null) return "No deadline";

    final diff = deadline.difference(DateTime.now());

    if (diff.isNegative) return "Overdue";
    if (dateOnly) {
      final now = DateTime.now();
      final sameDay =
          deadline.year == now.year &&
          deadline.month == now.month &&
          deadline.day == now.day;
      return sameDay
          ? "Due today"
          : "Due ${_formatDateTime(deadline, dateOnly: true)}";
    }

    final totalMinutes = diff.inMinutes;
    if (totalMinutes < 1) return "Due now";
    if (totalMinutes < 60) return "$totalMinutes min left";

    final hours = (totalMinutes / 60).ceil();
    if (hours < 24) return "$hours ${hours == 1 ? "hr" : "hrs"} left";

    final days = (hours / 24).ceil();
    return "$days ${days == 1 ? "day" : "days"} left";
  }

  Future<void> _refreshTasks() async {
    setState(() {});
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }

  // ================= UI =================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),

      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'tasks_add_task_fab',
        onPressed: _showAddTaskDialog,

        backgroundColor: Colors.deepOrange,

        elevation: 4,

        icon: const Icon(Icons.add_rounded, color: Colors.white),

        label: const Text(
          "Add Task",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),

      body: SafeArea(
        child: RefreshIndicator(
          color: Colors.deepOrange,
          onRefresh: _refreshTasks,
          child: StreamBuilder<List<Task>>(
            stream: _tasksStream,

            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return ListView(
                  physics: const AlwaysScrollableScrollPhysics(
                    parent: BouncingScrollPhysics(),
                  ),
                  padding: const EdgeInsets.all(24),
                  children: [
                    const SizedBox(height: 220),
                    Icon(
                      Icons.cloud_off_rounded,
                      size: 42,
                      color: Colors.grey.shade500,
                    ),
                    const SizedBox(height: 12),
                    Center(
                      child: Text(
                        "Could not load tasks",
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                );
              }

              if (!snapshot.hasData) {
                return ListView(
                  physics: const AlwaysScrollableScrollPhysics(
                    parent: BouncingScrollPhysics(),
                  ),
                  children: const [
                    SizedBox(height: 260),
                    Center(child: CircularProgressIndicator()),
                  ],
                );
              }

              final tasks = snapshot.data!;

              final activeTasks = tasks
                  .where((t) => !t.isCompleted && !t.isOverdue)
                  .toList();

              final overdueTasks =
                  tasks.where((t) => !t.isCompleted && t.isOverdue).toList()
                    ..sort((a, b) {
                      final aDeadline = a.deadline;
                      final bDeadline = b.deadline;
                      if (aDeadline == null || bDeadline == null) return 0;
                      return bDeadline.compareTo(aDeadline);
                    });

              final completedTasks = tasks.where((t) => t.isCompleted).toList()
                ..sort((a, b) {
                  final aDeadline = a.deadline;
                  final bDeadline = b.deadline;
                  if (aDeadline == null && bDeadline == null) return 0;
                  if (aDeadline == null) return 1;
                  if (bDeadline == null) return -1;
                  return bDeadline.compareTo(aDeadline);
                });

              return ListView(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),

                padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),

                children: [
                  // ================= HERO =================
                  _buildHeroCard(
                    active: activeTasks.length,
                    overdue: overdueTasks.length,
                    completed: completedTasks.length,
                  ),

                  const SizedBox(height: 22),

                  _buildTaskRecommendation(
                    active: activeTasks.length,
                    overdue: overdueTasks.length,
                    completed: completedTasks.length,
                  ),

                  const SizedBox(height: 14),

                  // ================= ACTIVE =================
                  buildSection(
                    title: "Active",
                    icon: Icons.flash_on_rounded,
                    color: Colors.green,
                    isOpen: _openSection == 'active',
                    count: activeTasks.length,
                    tasks: activeTasks,
                    onTap: () => _toggleSection('active'),
                    onClear: () =>
                        deleteTaskGroup(title: "Active", tasks: activeTasks),
                  ),

                  const SizedBox(height: 14),

                  // ================= OVERDUE =================
                  buildSection(
                    title: "Overdue",
                    icon: Icons.warning_amber_rounded,
                    color: Colors.redAccent,
                    isOpen: _openSection == 'overdue',
                    count: overdueTasks.length,
                    tasks: overdueTasks,
                    onTap: () => _toggleSection('overdue'),
                    onClear: () =>
                        deleteTaskGroup(title: "Overdue", tasks: overdueTasks),
                  ),

                  const SizedBox(height: 14),

                  // ================= COMPLETED =================
                  buildSection(
                    title: "Completed",
                    icon: Icons.task_alt_rounded,
                    color: Colors.grey,
                    isOpen: _openSection == 'completed',
                    count: completedTasks.length,
                    tasks: completedTasks,
                    onTap: () => _toggleSection('completed'),
                    onClear: () => deleteTaskGroup(
                      title: "Completed",
                      tasks: completedTasks,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildTaskRecommendation({
    required int active,
    required int overdue,
    required int completed,
  }) {
    final user = FirebaseAuth.instance.currentUser;
    final stream = user == null
        ? null
        : FirebaseFirestore.instance
              .collection('admin_monitoring')
              .doc(user.uid)
              .snapshots();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snapshot) {
        final monitoring = snapshot.data?.data() ?? const <String, dynamic>{};
        final rank = (monitoring['stressRank'] as String?) ?? 'Pending';
        final confidence =
            ((monitoring['confidence'] as num?)?.toDouble() ?? 0);
        final recommendation = _taskRecommendationText(
          rank: rank,
          confidence: confidence,
          active: active,
          overdue: overdue,
          completed: completed,
        );

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.deepOrange.withValues(alpha: 0.1)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 12,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.deepOrange.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  color: Colors.deepOrange,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "AI Task Recommendation",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      recommendation,
                      style: TextStyle(
                        color: Colors.grey.shade800,
                        height: 1.38,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _taskRecommendationText({
    required String rank,
    required double confidence,
    required int active,
    required int overdue,
    required int completed,
  }) {
    if (confidence <= 0) {
      return "Create only the next clear action first. Add deadlines when they are real, and leave flexible tasks without one.";
    }

    if (rank == 'High' || overdue >= 3) {
      return "Prioritize the smallest urgent task, pause anything optional, and ask for support before adding more work today.";
    }

    if (rank == 'Elevated' || active >= 6) {
      return "Your task load looks busy. Group similar school tasks, choose one deadline task for the next hour, then schedule a short reset.";
    }

    if (completed > active && active > 0) {
      return "You are clearing tasks well. Keep momentum by setting one focused task with a realistic date or no deadline if it is flexible.";
    }

    return "Your workload looks manageable. Pick one meaningful task, give it a clear title, and add a date only when timing matters.";
  }

  // ================= SECTION =================

  Widget buildSection({
    required String title,
    required IconData icon,
    required Color color,
    required bool isOpen,
    required int count,
    required VoidCallback onTap,
    required VoidCallback onClear,
    required List<Task> tasks,
  }) {
    return Column(
      children: [
        GestureDetector(
          onTap: onTap,

          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),

            padding: const EdgeInsets.all(16),

            decoration: BoxDecoration(
              color: Colors.white,

              borderRadius: BorderRadius.circular(24),

              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 12,
                  offset: const Offset(0, 5),
                ),
              ],
            ),

            child: Row(
              children: [
                // ================= ICON =================
                Container(
                  padding: const EdgeInsets.all(10),

                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),

                  child: Icon(icon, color: color),
                ),

                const SizedBox(width: 14),

                // ================= TITLE =================
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,

                    children: [
                      Text(
                        title,

                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: color,
                        ),
                      ),

                      const SizedBox(height: 2),

                      Text(
                        "$count tasks",
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),

                // ================= ARROW =================
                AnimatedRotation(
                  turns: isOpen ? 0.5 : 0,
                  duration: const Duration(milliseconds: 250),

                  child: Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: Colors.grey.shade700,
                  ),
                ),
                if (count > 0) ...[
                  const SizedBox(width: 6),
                  Tooltip(
                    message: "Clear $title tasks",
                    child: IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: onClear,
                      icon: Icon(Icons.delete_sweep_rounded, color: color),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),

        const SizedBox(height: 10),

        // ================= TASKS =================
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),

          child: isOpen
              ? Column(
                  children: tasks.isEmpty
                      ? [
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(24),

                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(22),
                            ),

                            child: Column(
                              children: [
                                Icon(
                                  Icons.inbox_rounded,
                                  size: 42,
                                  color: Colors.grey.shade400,
                                ),

                                const SizedBox(height: 10),

                                Text(
                                  "No tasks here \u{1F389}",
                                  style: TextStyle(color: Colors.grey.shade600),
                                ),
                              ],
                            ),
                          ),
                        ]
                      : tasks.map((t) => buildTaskCard(t)).toList(),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  // ================= TASK CARD =================

  Widget buildTaskCard(Task task) {
    final diff = task.deadline?.difference(DateTime.now());

    Color color;
    String status;
    IconData icon;

    if (task.isCompleted) {
      color = Colors.grey;
      status = "Completed";
      icon = Icons.check_circle_rounded;
    } else if (task.isOverdue) {
      color = Colors.redAccent;
      status = "Overdue";
      icon = Icons.warning_rounded;
    } else if (task.deadline == null) {
      color = Colors.blueGrey;
      status = "No deadline";
      icon = Icons.inbox_rounded;
    } else if (task.dateOnly) {
      color = Colors.blue;
      status = _timeLeftLabel(task.deadline, dateOnly: true);
      icon = Icons.event_rounded;
    } else if (diff!.inMinutes <= 60) {
      color = Colors.orange;
      status = _timeLeftLabel(task.deadline);
      icon = Icons.access_time_filled_rounded;
    } else {
      color = Colors.green;
      status = _timeLeftLabel(task.deadline);
      icon = Icons.bolt_rounded;
    }

    final canInteract = !task.isCompleted && !task.isOverdue;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),

      margin: const EdgeInsets.only(bottom: 12),

      padding: const EdgeInsets.all(16),

      decoration: BoxDecoration(
        color: Colors.white,

        borderRadius: BorderRadius.circular(24),

        border: Border.all(color: color.withValues(alpha: 0.12)),

        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),

      child: Row(
        children: [
          // ================= STATUS BUTTON =================
          GestureDetector(
            onTap: canInteract
                ? () async {
                    if (task.deadline != null &&
                        DateTime.now().isAfter(task.deadline!)) {
                      setState(() {});
                      return;
                    }

                    await toggleTask(task, true);
                  }
                : null,

            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),

              width: 34,
              height: 34,

              decoration: BoxDecoration(
                shape: BoxShape.circle,

                color: task.isCompleted
                    ? Colors.green
                    : color.withValues(alpha: 0.08),

                border: Border.all(color: color, width: 2),
              ),

              child: Icon(
                task.isCompleted ? Icons.check_rounded : icon,

                size: 18,

                color: task.isCompleted ? Colors.white : color,
              ),
            ),
          ),

          const SizedBox(width: 14),

          // ================= TEXT =================
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,

              children: [
                Text(
                  task.title,

                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,

                    decoration: task.isCompleted
                        ? TextDecoration.lineThrough
                        : null,
                  ),
                ),

                const SizedBox(height: 8),

                if (task.flags.isNotEmpty) ...[
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final flag in task.flags) _taskFlagChip(flag: flag),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],

                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),

                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(30),
                      ),

                      child: Text(
                        status,

                        style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ================= DELETE =================
          if (canInteract)
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded),
              color: Colors.redAccent,

              onPressed: () async {
                if (task.deadline != null &&
                    DateTime.now().isAfter(task.deadline!)) {
                  setState(() {});
                  return;
                }

                await deleteTask(task);
              },
            ),
        ],
      ),
    );
  }

  // ================= ADD TASK =================

  void _showAddTaskDialog() {
    final titleController = TextEditingController();
    DateTime? selectedDeadline;
    bool hasDeadline = false;
    bool dateOnly = false;
    String? localError;
    bool isCreating = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return Container(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ================= HANDLE =================
                  Center(
                    child: Container(
                      width: 50,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // ================= TITLE =================
                  const Text(
                    "Create New Task",
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),

                  const SizedBox(height: 6),

                  Text(
                    "Stay organized and track your progress",
                    style: TextStyle(color: Colors.grey.shade600),
                  ),

                  const SizedBox(height: 20),

                  // ================= TASK INPUT =================
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: TextField(
                      controller: titleController,
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        hintText: "What do you need to do?",
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    value: hasDeadline,
                    activeThumbColor: Colors.deepOrange,
                    title: const Text(
                      "Add deadline",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: const Text("Optional for flexible tasks"),
                    onChanged: (value) {
                      setState(() {
                        hasDeadline = value;
                        if (!value) {
                          selectedDeadline = null;
                          dateOnly = false;
                        }
                        localError = null;
                      });
                    },
                  ),

                  if (hasDeadline) ...[
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: dateOnly,
                      activeColor: Colors.deepOrange,
                      title: const Text("Date only"),
                      subtitle: const Text("No exact time needed"),
                      onChanged: (value) {
                        setState(() {
                          dateOnly = value ?? false;
                          selectedDeadline = null;
                          localError = null;
                        });
                      },
                    ),
                    InkWell(
                      onTap: () async {
                        final pickedDate = await showDatePicker(
                          context: context,
                          firstDate: DateTime.now(),
                          lastDate: DateTime(2100),
                        );

                        if (!context.mounted || pickedDate == null) return;

                        TimeOfDay? pickedTime;
                        if (!dateOnly) {
                          pickedTime = await showTimePicker(
                            context: context,
                            initialTime: TimeOfDay.now(),
                          );

                          if (!context.mounted || pickedTime == null) return;
                        }

                        final combined = dateOnly
                            ? DateTime(
                                pickedDate.year,
                                pickedDate.month,
                                pickedDate.day,
                                23,
                                59,
                              )
                            : DateTime(
                                pickedDate.year,
                                pickedDate.month,
                                pickedDate.day,
                                pickedTime!.hour,
                                pickedTime.minute,
                              );

                        setState(() {
                          selectedDeadline = combined;
                          localError = null;
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.orange.shade50,
                              Colors.deepOrange.shade50,
                            ],
                          ),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.orange.shade100),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.calendar_today,
                              color: Colors.deepOrange,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                selectedDeadline == null
                                    ? "Set ${dateOnly ? "date" : "deadline"}"
                                    : _formatDateTime(
                                        selectedDeadline!,
                                        dateOnly: dateOnly,
                                      ),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const Icon(
                              Icons.arrow_forward_ios_rounded,
                              size: 16,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 10),

                  // ================= ERROR =================
                  if (localError != null)
                    Text(
                      localError!,
                      style: const TextStyle(color: Colors.red, fontSize: 13),
                    ),

                  const SizedBox(height: 20),

                  // ================= ACTION BUTTON =================
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepOrange,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      onPressed: isCreating
                          ? null
                          : () async {
                              final navigator = Navigator.of(context);
                              final messenger = ScaffoldMessenger.of(context);

                              final now = DateTime.now();
                              final title = titleController.text.trim();

                              if (title.isEmpty) {
                                setState(() {
                                  localError = "Please enter a task title.";
                                });
                                return;
                              }

                              if (hasDeadline && selectedDeadline == null) {
                                setState(() {
                                  localError =
                                      "Choose a deadline or turn it off.";
                                });
                                return;
                              }

                              if (selectedDeadline != null &&
                                  selectedDeadline!.isBefore(now)) {
                                setState(() {
                                  localError =
                                      "Deadline must be in the future.";
                                });
                                return;
                              }

                              final guardResult =
                                  TaskContentGuardService.validate(title);
                              if (!guardResult.isAllowed) {
                                await _showTaskBlockedDialog(
                                  context,
                                  guardResult,
                                );
                                return;
                              }

                              try {
                                setState(() {
                                  isCreating = true;
                                  localError = null;
                                });
                                await addTask(
                                  title,
                                  hasDeadline ? selectedDeadline : null,
                                  dateOnly: dateOnly,
                                );

                                if (!mounted) return;

                                navigator.pop();
                              } on TaskContentBlockedException catch (e) {
                                if (!context.mounted) return;
                                await _showTaskBlockedDialog(context, e.result);
                              } catch (e) {
                                if (!mounted) return;

                                messenger.showSnackBar(
                                  SnackBar(content: Text("Error: $e")),
                                );
                              } finally {
                                if (context.mounted) {
                                  setState(() => isCreating = false);
                                }
                              }
                            },
                      child: isCreating
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.4,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              "Create Task",
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ============== DELETE ACTIVE TASK ===================

  Future<void> deleteTask(Task task) async {
    if (task.isCompleted || task.isOverdue) {
      return;
    }

    final taskRef = _taskRef;
    if (taskRef == null) return;

    await taskRef.doc(task.id).delete();
    await WellnessSignalService.publishCurrentUserSignals();
  }

  Widget _taskFlagChip({required TaskFlag flag}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: flag.color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(flag.icon, color: flag.color, size: 13),
          const SizedBox(width: 4),
          Text(
            flag.label,
            style: TextStyle(
              color: flag.color,
              fontWeight: FontWeight.w800,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  // ================ CARD =====================

  Widget _buildHeroCard({
    required int active,
    required int overdue,
    required int completed,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),

      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.orange.shade300, Colors.deepOrange.shade400],

          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),

        borderRadius: BorderRadius.circular(30),

        boxShadow: [
          BoxShadow(
            color: Colors.orange.withValues(alpha: 0.25),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,

        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),

                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(18),
                ),

                child: const Icon(
                  Icons.task_alt_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),

              const Spacer(),

              Text(
                "$active Active",

                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          const Text(
            "Today's Productivity",

            style: TextStyle(color: Colors.white70, fontSize: 15),
          ),

          const SizedBox(height: 8),

          const Text(
            "Stay organized and focused",

            style: TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.bold,
              height: 1.1,
            ),
          ),

          const SizedBox(height: 24),

          Row(
            children: [
              _heroStat("Completed", completed.toString()),
              const SizedBox(width: 12),
              _heroStat("Overdue", overdue.toString()),
            ],
          ),
        ],
      ),
    );
  }

  Widget _heroStat(String title, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),

        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(18),
        ),

        child: Column(
          children: [
            Text(
              value,

              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 22,
              ),
            ),

            const SizedBox(height: 4),

            Text(
              title,

              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
