import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/api.dart';
import '../../services/csv_export.dart';

/// Attended students for one session: flagged scans, remove an entry, CSV export.
class SessionReportScreen extends StatelessWidget {
  const SessionReportScreen({super.key, required this.sessionId});
  final String sessionId;

  @override
  Widget build(BuildContext context) {
    final db = FirebaseFirestore.instance;
    // Filtering by lecturerUid as well is required by the security rules.
    final attendance = db
        .collection('attendance')
        .where('sessionId', isEqualTo: sessionId)
        .where('lecturerUid', isEqualTo: FirebaseAuth.instance.currentUser!.uid)
        .snapshots();
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: db.collection('sessions').doc(sessionId).snapshots(),
      builder: (context, sessionSnap) {
        final s = sessionSnap.data?.data();
        if (s == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: attendance,
          builder: (context, attSnap) {
            if (attSnap.hasError) return Scaffold(body: Center(child: Text('${attSnap.error}')));
            if (!attSnap.hasData) return const Scaffold(body: Center(child: CircularProgressIndicator()));
            final records = attSnap.data!.docs.map((d) => d.data()).toList()
              ..sort((a, b) => (a['at'] as Timestamp).compareTo(b['at'] as Timestamp));
            return _ReportView(sessionId: sessionId, session: s, records: records);
          },
        );
      },
    );
  }
}

class _ReportView extends StatelessWidget {
  const _ReportView({required this.sessionId, required this.session, required this.records});
  final String sessionId;
  final Map<String, dynamic> session;
  final List<Map<String, dynamic>> records;

  Future<void> _remove(BuildContext context, Map<String, dynamic> d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove attendance?'),
        content: Text('${d['studentName']} (${d['studentId']}) will be marked as not attended.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remove')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Api.removeAttendance(sessionId, d['studentId'] as String);
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorText(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('HH:mm:ss');
    final flagged = records.where((d) => (d['flags'] as List? ?? const []).isNotEmpty).length;
    return Scaffold(
      appBar: AppBar(
        title: Text('${session['subject']} · ${session['hallName']}'),
        actions: [
          IconButton(
            tooltip: 'Export CSV',
            icon: const Icon(Icons.download),
            onPressed: () => shareAttendanceCsv(records, 'attendance-${session['subject']}-$sessionId.csv'),
          ),
        ],
      ),
      body: ListView(children: [
        ListTile(
          title: Text('${records.length} attended'),
          subtitle: flagged > 0 ? Text('$flagged flagged for review (scanned near the hall edge)') : null,
        ),
        const Divider(),
        for (final d in records)
          ListTile(
            leading: (d['flags'] as List? ?? const []).isNotEmpty
                ? const Icon(Icons.flag, color: Colors.orange)
                : const Icon(Icons.check_circle, color: Colors.green),
            title: Text('${d['studentName']} (${d['studentId']})'),
            subtitle: Text([
              fmt.format((d['at'] as Timestamp).toDate()),
              if (d['distanceMeters'] != null) '${(d['distanceMeters'] as num).round()} m from hall',
            ].join(' · ')),
            trailing: IconButton(
              tooltip: 'Remove',
              icon: const Icon(Icons.person_remove),
              onPressed: () => _remove(context, d),
            ),
          ),
      ]),
    );
  }
}
