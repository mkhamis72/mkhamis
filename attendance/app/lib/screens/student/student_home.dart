import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/api.dart';
import '../../services/device.dart';
import 'scan_screen.dart';

class StudentHome extends StatefulWidget {
  const StudentHome({super.key, required this.studentId});
  final String studentId;

  @override
  State<StudentHome> createState() => _StudentHomeState();
}

class _StudentHomeState extends State<StudentHome> {
  String? _deviceWarning;

  @override
  void initState() {
    super.initState();
    _registerDevice();
  }

  /// Binds this account to this phone on first login, and warns if it is bound elsewhere.
  Future<void> _registerDevice() async {
    try {
      final res = await Api.registerDevice(await DeviceId.get());
      if (mounted && res['matches'] == false) {
        setState(() => _deviceWarning =
            'Your account is registered to another phone. Scans from this phone will be rejected. Ask the admin to reset it.');
      }
    } catch (_) {
      // Offline: the server checks the device again on every scan.
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser!;
    final history = FirebaseFirestore.instance
        .collection('attendance')
        .where('studentUid', isEqualTo: user.uid)
        .orderBy('at', descending: true)
        .limit(100)
        .snapshots();

    return Scaffold(
      appBar: AppBar(
        title: Text(user.displayName ?? widget.studentId),
        actions: [
          IconButton(tooltip: 'Sign out', icon: const Icon(Icons.logout), onPressed: () => FirebaseAuth.instance.signOut()),
        ],
      ),
      body: Column(children: [
        if (_deviceWarning != null)
          MaterialBanner(
            content: Text(_deviceWarning!),
            leading: const Icon(Icons.phonelink_lock),
            actions: [TextButton(onPressed: () => setState(() => _deviceWarning = null), child: const Text('OK'))],
          ),
        Padding(
          padding: const EdgeInsets.all(24),
          child: Column(children: [
            Text('ID: ${widget.studentId}', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 72,
              child: FilledButton.icon(
                icon: const Icon(Icons.qr_code_scanner, size: 32),
                label: const Text('Scan attendance QR', style: TextStyle(fontSize: 18)),
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ScanScreen())),
              ),
            ),
          ]),
        ),
        const Divider(height: 1),
        const ListTile(title: Text('My attendance')),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: history,
            builder: (context, snap) {
              if (snap.hasError) return Center(child: Text('${snap.error}'));
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());
              final docs = snap.data!.docs;
              if (docs.isEmpty) return const Center(child: Text('No attendance yet.'));
              final fmt = DateFormat('EEE d MMM, HH:mm');
              return ListView.builder(
                itemCount: docs.length,
                itemBuilder: (_, i) {
                  final d = docs[i].data();
                  final at = (d['at'] as Timestamp?)?.toDate();
                  return ListTile(
                    leading: const Icon(Icons.check_circle, color: Colors.green),
                    title: Text('${d['subject']}'),
                    subtitle: Text('${d['hallName']} · ${at == null ? '' : fmt.format(at)}'),
                  );
                },
              );
            },
          ),
        ),
      ]),
    );
  }
}
