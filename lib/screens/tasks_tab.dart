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
  String? _openSection = 'active';
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

  void _toggleSection(String section) {
    setState(() {
      _openSection = _openSection == section ? null : section;
    });
  }

  // ================= UI =================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),

      floatingActionButton: FloatingActionButton.extended(
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
              physics: const BouncingScrollPhysics(),

              padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),

              children: [
                // ================= HERO =================
                _buildHeroCard(
                  active: activeTasks.length,
                  overdue: overdueTasks.length,
                  completed: completedTasks.length,
                ),

                const SizedBox(height: 22),

                // ================= ACTIVE =================
                buildSection(
                  title: "Active",
                  icon: Icons.flash_on_rounded,
                  color: Colors.green,
                  isOpen: _openSection == 'active',
                  count: activeTasks.length,
                  tasks: activeTasks,
                  onTap: () => _toggleSection('active'),
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
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  // ================= SECTION =================

  Widget buildSection({
    required String title,
    required IconData icon,
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
                                  "No tasks here 🎉",
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
    final diff = task.deadline.difference(DateTime.now());

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
    } else if (diff.inHours <= 1) {
      color = Colors.orange;
      status = "Due Soon";
      icon = Icons.access_time_filled_rounded;
    } else {
      color = Colors.green;
      status = "${diff.inHours} hrs left";
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
                    if (DateTime.now().isAfter(task.deadline)) {
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

                    const SizedBox(width: 8),

                    Expanded(
                      child: Text(
                        _formatDateTime(task.deadline),

                        overflow: TextOverflow.ellipsis,

                        style: TextStyle(
                          color: Colors.grey.shade600,
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
                if (DateTime.now().isAfter(task.deadline)) {
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
    String? localError;

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

                  // ================= DEADLINE PICKER =================
                  InkWell(
                    onTap: () async {
                      final pickedDate = await showDatePicker(
                        context: context,
                        firstDate: DateTime.now(),
                        lastDate: DateTime(2100),
                      );

                      if (!context.mounted || pickedDate == null) return;

                      final pickedTime = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay.now(),
                      );

                      if (!context.mounted || pickedTime == null) return;

                      final combined = DateTime(
                        pickedDate.year,
                        pickedDate.month,
                        pickedDate.day,
                        pickedTime.hour,
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
                                  ? "Set deadline"
                                  : _formatDateTime(selectedDeadline!),
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),

                          const Icon(Icons.arrow_forward_ios_rounded, size: 16),
                        ],
                      ),
                    ),
                  ),

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
                      onPressed: () async {
                        final navigator = Navigator.of(context);
                        final messenger = ScaffoldMessenger.of(context);

                        final now = DateTime.now();

                        if (titleController.text.trim().isEmpty ||
                            selectedDeadline == null) {
                          setState(() {
                            localError = "Please complete all fields.";
                          });
                          return;
                        }

                        if (selectedDeadline!.isBefore(now)) {
                          setState(() {
                            localError = "Deadline must be in the future.";
                          });
                          return;
                        }

                        try {
                          await addTask(
                            titleController.text.trim(),
                            selectedDeadline!,
                          );

                          if (!mounted) return;

                          navigator.pop();
                        } catch (e) {
                          if (!mounted) return;

                          messenger.showSnackBar(
                            SnackBar(content: Text("Error: $e")),
                          );
                        }
                      },
                      child: const Text(
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

    await _taskRef.doc(task.id).delete();
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
