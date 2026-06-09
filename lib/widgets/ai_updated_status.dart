import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class AiUpdatedStatus extends StatelessWidget {
  const AiUpdatedStatus({super.key, required this.statusText});

  final String statusText;

  static String fromMonitoring(Map<String, dynamic> data) {
    final timestamp = _timestampFromData(data);
    if (timestamp == null) return 'Status: waiting for AI update';
    return 'Status: ${_formatTimestamp(timestamp)}';
  }

  static DateTime? _timestampFromData(Map<String, dynamic> data) {
    final value = data['aiMoodStatusUpdatedAt'] ?? data['updatedAt'];
    if (value is Timestamp) return value.toDate();
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  static String _formatTimestamp(DateTime value) {
    final manila = value.toUtc().add(const Duration(hours: 8));
    final hour = manila.hour > 12
        ? manila.hour - 12
        : manila.hour == 0
        ? 12
        : manila.hour;
    final minute = manila.minute.toString().padLeft(2, '0');
    final second = manila.second.toString().padLeft(2, '0');
    final period = manila.hour >= 12 ? 'PM' : 'AM';
    return '${manila.year}-${manila.month.toString().padLeft(2, '0')}-${manila.day.toString().padLeft(2, '0')} $hour:$minute:$second $period';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.schedule_rounded,
            size: 17,
            color: Color(0xFF64748B),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              statusText,
              style: const TextStyle(
                color: Color(0xFF475569),
                fontSize: 12.5,
                height: 1.25,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
