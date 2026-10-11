import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/csv_export.dart';

/// Every attended student across the lecturer's sessions, filtered by date range and search text.
class AttendanceListScreen extends StatefulWidget {
  const AttendanceListScreen({super.key});

  @override
  State<AttendanceListScreen> createState() => _AttendanceListScreenState();
}

class _AttendanceListScreenState extends State<AttendanceListScreen> {
  late DateTimeRange _range = _lastDays(7);
  String _query = '';

  static DateTimeRange _lastDays(int days) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return DateTimeRange(start: today.subtract(Duration(days: days - 1)), end: today);
  }

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      initialDateRange: _range,
    );
    if (picked != null) setState(() => _range = picked);
  }

  bool _matches(Map<String, dynamic> d) {
    if (_query.isEmpty) return true;
    final q = _query.toLowerCase();
    return ['studentId', 'studentName', 'subject', 'hallName'].any((k) => '${d[k] ?? ''}'.toLowerCase().contains(q));
  }

  @override
  Widget build(BuildContext context) {
    final stream = FirebaseFirestore.instance
        .collection('attendance')
        .where('lecturerUid', isEqualTo: FirebaseAuth.instance.currentUser!.uid)
        .where('at', isGreaterThanOrEqualTo: Timestamp.fromDate(_range.start))
        .where('at', isLessThan: Timestamp.fromDate(_range.end.add(const Duration(days: 1))))
        .orderBy('at', descending: true)
        .snapshots();
    final dayFmt = DateFormat('d MMM');
    final timeFmt = DateFormat('EEE d MMM, HH:mm');

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snap) {
        final records = (snap.data?.docs ?? const []).map((d) => d.data()).where(_matches).toList();
        return Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.date_range),
                label: Text('${dayFmt.format(_range.start)} – ${dayFmt.format(_range.end)}'),
                onPressed: _pickRange,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(
                    isDense: true,
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Student, subject or hall',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) => setState(() => _query = v.trim()),
                ),
              ),
              IconButton(
                tooltip: 'Export CSV',
                icon: const Icon(Icons.download),
                onPressed: records.isEmpty ? null : () => shareAttendanceCsv(records, 'attendance.csv'),
              ),
            ]),
          ),
          Expanded(
            child: snap.hasError
                ? Center(child: Text('${snap.error}'))
                : !snap.hasData
                    ? const Center(child: CircularProgressIndicator())
                    : records.isEmpty
                        ? const Center(child: Text('No attendance in this period.'))
                        : ListView.builder(
                            padding: const EdgeInsets.only(bottom: 88),
                            itemCount: records.length,
                            itemBuilder: (_, i) {
                              final d = records[i];
                              final flagged = (d['flags'] as List? ?? const []).isNotEmpty;
                              return ListTile(
                                leading: Icon(flagged ? Icons.flag : Icons.check_circle,
                                    color: flagged ? Colors.orange : Colors.green),
                                title: Text('${d['studentName']} (${d['studentId']})'),
                                subtitle: Text(
                                    '${d['subject']} · ${d['hallName']} · ${timeFmt.format((d['at'] as Timestamp).toDate())}'),
                              );
                            },
                          ),
          ),
        ]);
      },
    );
  }
}
