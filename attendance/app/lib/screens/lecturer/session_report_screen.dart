import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

import '../../services/api.dart';

/// Present / absent list for one session, flagged scans, manual override and CSV export.
class SessionReportScreen extends StatelessWidget {
  const SessionReportScreen({super.key, required this.sessionId});
  final String sessionId;

  @override
  Widget build(BuildContext context) {
    final db = FirebaseFirestore.instance;
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: db.collection('sessions').doc(sessionId).snapshots(),
      builder: (context, sessionSnap) {
        final s = sessionSnap.data?.data();
        if (s == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
        return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          future: db.collection('courses').doc(s['courseId'] as String).get(),
          builder: (context, courseSnap) {
            final roster = List<String>.from(courseSnap.data?.data()?['studentIds'] ?? const []);
            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: db.collection('attendance').where('sessionId', isEqualTo: sessionId).orderBy('at').snapshots(),
              builder: (context, attSnap) {
                if (!attSnap.hasData || !courseSnap.hasData) {
                  return const Scaffold(body: Center(child: CircularProgressIndicator()));
                }
                final present = {for (final d in attSnap.data!.docs) d['studentId'] as String: d.data()};
                final absent = roster.where((id) => !present.containsKey(id)).toList()..sort();
                return _ReportView(sessionId: sessionId, session: s, present: present, absent: absent);
              },
            );
          },
        );
      },
    );
  }
}

class _ReportView extends StatelessWidget {
  const _ReportView({required this.sessionId, required this.session, required this.present, required this.absent});
  final String sessionId;
  final Map<String, dynamic> session;
  final Map<String, Map<String, dynamic>> present;
  final List<String> absent;

  Future<void> _export() async {
    final fmt = DateFormat('yyyy-MM-dd HH:mm:ss');
    final lines = ['student_id,name,status,time,flags,manual'];
    present.forEach((id, d) {
      final at = (d['at'] as Timestamp?)?.toDate();
      final flags = (d['flags'] as List? ?? const []).join(' ');
      lines.add('$id,"${d['studentName']}",present,${at == null ? '' : fmt.format(at)},$flags,${d['manual'] == true}');
    });
    for (final id in absent) {
      lines.add('$id,,absent,,,');
    }
    await Printing.sharePdf(
      bytes: Uint8List.fromList(utf8.encode(lines.join('\n'))),
      filename: 'attendance-${session['subject']}-$sessionId.csv',
    );
  }

  Future<void> _override(BuildContext context, String studentId, bool markPresent) async {
    try {
      await Api.overrideAttendance(sessionId, studentId, markPresent);
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorText(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('HH:mm:ss');
    final flagged = present.entries.where((e) => (e.value['flags'] as List? ?? const []).isNotEmpty).length;
    return Scaffold(
      appBar: AppBar(
        title: Text('${session['subject']} · ${session['hallName']}'),
        actions: [IconButton(tooltip: 'Export CSV', icon: const Icon(Icons.download), onPressed: _export)],
      ),
      body: ListView(children: [
        ListTile(
          title: Text('${present.length} present · ${absent.length} absent'),
          subtitle: flagged > 0 ? Text('$flagged flagged for review (scanned near the hall edge)') : null,
        ),
        const Divider(),
        for (final e in present.entries)
          ListTile(
            leading: Icon(
              (e.value['flags'] as List? ?? const []).isNotEmpty ? Icons.flag : Icons.check_circle,
              color: (e.value['flags'] as List? ?? const []).isNotEmpty ? Colors.orange : Colors.green,
            ),
            title: Text('${e.value['studentName']} (${e.key})'),
            subtitle: Text([
              if (e.value['at'] != null) fmt.format((e.value['at'] as Timestamp).toDate()),
              if (e.value['distanceMeters'] != null) '${(e.value['distanceMeters'] as num).round()} m from hall',
              if (e.value['manual'] == true) 'marked by lecturer',
            ].join(' · ')),
            trailing: IconButton(
              tooltip: 'Mark absent',
              icon: const Icon(Icons.person_remove),
              onPressed: () => _override(context, e.key, false),
            ),
          ),
        if (absent.isNotEmpty) const Divider(),
        for (final id in absent)
          ListTile(
            leading: const Icon(Icons.radio_button_unchecked),
            title: Text(id),
            subtitle: const Text('Absent'),
            trailing: IconButton(
              tooltip: 'Mark present',
              icon: const Icon(Icons.person_add),
              onPressed: () => _override(context, id, true),
            ),
          ),
      ]),
    );
  }
}

