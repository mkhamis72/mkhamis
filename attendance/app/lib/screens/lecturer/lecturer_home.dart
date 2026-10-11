import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'attendance_list_screen.dart';
import 'create_session_screen.dart';
import 'live_session_screen.dart';
import '../profile_screen.dart';
import 'session_report_screen.dart';

class LecturerHome extends StatelessWidget {
  const LecturerHome({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final sessions = FirebaseFirestore.instance
        .collection('sessions')
        .where('lecturerUid', isEqualTo: uid)
        .orderBy('startsAt', descending: true)
        .limit(50)
        .snapshots();

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(FirebaseAuth.instance.currentUser?.displayName ?? 'Lecturer'),
          actions: [
            IconButton(
              tooltip: 'My details',
              icon: const Icon(Icons.account_circle),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen(student: false))),
            ),
            IconButton(tooltip: 'Sign out', icon: const Icon(Icons.logout), onPressed: () => FirebaseAuth.instance.signOut()),
          ],
          bottom: const TabBar(tabs: [Tab(text: 'Sessions'), Tab(text: 'Attended students')]),
        ),
        floatingActionButton: FloatingActionButton.extended(
          icon: const Icon(Icons.qr_code_2),
          label: const Text('New QR'),
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateSessionScreen())),
        ),
        body: TabBarView(children: [
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: sessions,
            builder: (context, snap) {
              if (snap.hasError) return Center(child: Text('${snap.error}'));
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());
              final docs = snap.data!.docs;
              if (docs.isEmpty) return const Center(child: Text('No sessions yet. Tap "New QR" to start one.'));
              final fmt = DateFormat('EEE d MMM, HH:mm');
              return ListView(
                padding: const EdgeInsets.only(bottom: 88),
                children: [
                  for (final s in docs)
                    ListTile(
                      leading: Icon(s['mode'] == 'rotating' ? Icons.autorenew : Icons.print),
                      title: Text('${s['subject']} · ${s['hallName']}'),
                      subtitle: Text(
                          '${fmt.format((s['startsAt'] as Timestamp).toDate())} · ${s['attendeeCount']} present · ${s['status']}'),
                      trailing: s['status'] == 'ended' ? const Icon(Icons.chevron_right) : const Chip(label: Text('LIVE')),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => s['status'] == 'ended'
                              ? SessionReportScreen(sessionId: s.id)
                              : LiveSessionScreen(sessionId: s.id),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          const AttendanceListScreen(),
        ]),
      ),
    );
  }
}
