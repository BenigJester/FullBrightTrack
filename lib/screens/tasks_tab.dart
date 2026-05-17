import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class Task {
  final String id;
  final String title;
  final DateTime deadline;
  final bool isCompleted;

  Task({
    required this.id,
    required this.title,
    required this.deadline,
    required this.isCompleted,
  });

  bool get isOverdue => !isCompleted && DateTime.now().isAfter(deadline);

  factory Task.fromFirestore(String id, Map<String, dynamic> data) {
    return Task(
      id: id,
      title: data['title'] ?? '',
      deadline: (data['deadline'] as Timestamp).toDate(),
      isCompleted: data['isCompleted'] ?? false,
    );
  }
}

class TasksTab extends StatefulWidget {
  const TasksTab({super.key});

  @override
  State<TasksTab> createState() => _TasksTabState();
}

class _TasksTabState extends State<TasksTab> {
  bool activeOpen = true;
  bool overdueOpen = true;
  bool completedOpen = false;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();

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

  CollectionReference<Map<String, dynamic>> get _taskRef {
    final user = FirebaseAuth.instance.currentUser;
    return FirebaseFirestore.instance
        .collection('users')
        .doc(user!.uid)
        .collection('tasks');
  }

  // ================= STREAM =================

  Stream<List<Task>> get tasksStream {
    return _taskRef.orderBy('deadline').snapshots().map((snapshot) {
      return snapshot.docs
          .map((doc) => Task.fromFirestore(doc.id, doc.data()))
          .toList();
    });
  }

  // ================= CRUD =================

  Future<void> toggleTask(Task task, bool value) async {
    if (task.deadline.isBefore(DateTime.now())) {
      return;
    }

    await _taskRef.doc(task.id).update({'isCompleted': value});
  }

  Future<void> addTask(String title, DateTime deadline) async {
    await _taskRef.add({
      'title': title,
      'deadline': deadline,
      'isCompleted': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  String _formatDateTime(DateTime dt) {
    return "${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} "
        "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
  }

  String? errorText;

  // ================= UI =================

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: StreamBuilder<List<Task>>(
        stream: tasksStream,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final tasks = snapshot.data!;

          final activeTasks = tasks
              .where((t) => !t.isCompleted && !t.isOverdue)
              .toList();

          final overdueTasks = tasks
              .where((t) => !t.isCompleted && t.isOverdue)
              .toList();

          final completedTasks = tasks.where((t) => t.isCompleted).toList();

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              buildSection(
                title: "Active",
                color: Colors.green,
                isOpen: activeOpen,
                count: activeTasks.length,
                tasks: activeTasks,
                onTap: () => setState(() => activeOpen = !activeOpen),
              ),
              buildSection(
                title: "Overdue",
                color: Colors.red,
                isOpen: overdueOpen,
                count: overdueTasks.length,
                tasks: overdueTasks,
                onTap: () => setState(() => overdueOpen = !overdueOpen),
              ),
              buildSection(
                title: "Completed",
                color: Colors.grey,
                isOpen: completedOpen,
                count: completedTasks.length,
                tasks: completedTasks,
                onTap: () => setState(() => completedOpen = !completedOpen),
              ),

              const SizedBox(height: 20),

              ElevatedButton(
                onPressed: _showAddTaskDialog,
                child: const Text("Add Task"),
              ),
            ],
          );
        },
      ),
    );
  }

  // ================= SECTION =================

  Widget buildSection({
    required String title,
    required Color color,
    required bool isOpen,
    required int count,
    required VoidCallback onTap,
    required List<Task> tasks,
  }) {
    return Column(
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
            margin: const EdgeInsets.only(bottom: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                AnimatedRotation(
                  turns: isOpen ? 0.5 : 0,
                  duration: const Duration(milliseconds: 250),
                  child: const Icon(Icons.keyboard_arrow_right),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "$title ($count)",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        if (isOpen) ...tasks.map((t) => buildTaskCard(t)),

        if (isOpen && tasks.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              "No tasks here 🎉",
              style: TextStyle(color: Colors.grey[600]),
            ),
          ),
      ],
    );
  }

  // ================= TASK CARD =================

  Widget buildTaskCard(Task task) {
    final diff = task.deadline.difference(DateTime.now());

    Color color;
    String status;

    if (task.isCompleted) {
      color = Colors.grey;
      status = "Completed";
    } else if (task.isOverdue) {
      color = Colors.red;
      status = "Overdue";
    } else if (diff.inHours <= 1) {
      color = Colors.orange;
      status = "Due soon";
    } else {
      color = Colors.green;
      status = "${diff.inHours} hrs left";
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            blurRadius: 6,
            color: Colors.black.withAlpha((0.05 * 255).round()),
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Checkbox(
            value: task.isCompleted,
            onChanged: (!task.isCompleted && !task.isOverdue)
                ? (val) async {
                    if (task.deadline.isBefore(DateTime.now())) {
                      setState(() {});
                      return;
                    }
                    await toggleTask(task, val!);
                  }
                : null,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.title,
                  style: TextStyle(
                    fontSize: 16,
                    decoration: task.isCompleted
                        ? TextDecoration.lineThrough
                        : null,
                  ),
                ),
                const SizedBox(height: 4),
                Text(status, style: TextStyle(color: color, fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ================= ADD TASK =================

  void _showAddTaskDialog() {
    final titleController = TextEditingController();
    DateTime? selectedDeadline;

    showDialog(
      context: context,
      builder: (_) {
        return StatefulBuilder(
          builder: (dialogContext, setStateDialog) {
            return AlertDialog(
              title: const Text("New Task"),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: titleController,
                    decoration: const InputDecoration(hintText: "Task title"),
                  ),

                  const SizedBox(height: 12),

                  // 🔥 SINGLE DEADLINE BUTTON
                  ElevatedButton.icon(
                    icon: const Icon(Icons.calendar_today),
                    label: Text(
                      selectedDeadline == null
                          ? "Set Deadline"
                          : _formatDateTime(selectedDeadline!),
                    ),
                    onPressed: () async {
                      if (!dialogContext.mounted) return;

                      // 1️⃣ Pick Date
                      final pickedDate = await showDatePicker(
                        context: dialogContext,
                        firstDate: DateTime.now(),
                        lastDate: DateTime(2100),
                      );

                      if (pickedDate == null || !dialogContext.mounted) return;

                      // 2️⃣ Pick Time
                      final pickedTime = await showTimePicker(
                        context: dialogContext,
                        initialTime: TimeOfDay.now(),
                      );

                      if (pickedTime == null || !dialogContext.mounted) return;

                      // 3️⃣ Combine
                      final combined = DateTime(
                        pickedDate.year,
                        pickedDate.month,
                        pickedDate.day,
                        pickedTime.hour,
                        pickedTime.minute,
                      );

                      setStateDialog(() {
                        selectedDeadline = combined;
                        errorText = null;
                      });
                    },
                  ),
                  const SizedBox(height: 10),

                  // 🔥 ERROR TEXT HERE
                  if (errorText != null)
                    Text(
                      errorText!,
                      style: const TextStyle(color: Colors.red, fontSize: 13),
                    ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () async {
                    final now = DateTime.now();

                    if (titleController.text.trim().isEmpty ||
                        selectedDeadline == null) {
                      setStateDialog(() {
                        errorText = "Please set title and deadline.";
                      });
                      return;
                    }

                    if (selectedDeadline!.isBefore(now)) {
                      setStateDialog(() {
                        errorText =
                            "You selected a past time. Please choose a future deadline.";
                      });
                      return;
                    }

                    try {
                      await addTask(
                        titleController.text.trim(),
                        selectedDeadline!,
                      );

                      if (!mounted) return;
                      Navigator.pop(context);
                    } catch (e) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text("Error: $e")));
                    }
                  },
                  child: const Text("Add"),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
