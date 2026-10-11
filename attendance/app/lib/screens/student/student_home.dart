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
  /// False when this account is bound to a different phone.
  bool _thisPhone = true;
  bool _rebinding = false;

  @override
  void initState() {
    super.initState();
    _checkDevice();
  }

  Future<void> _checkDevice() async {
    try {
      final res = await Api.deviceStatus(await DeviceId.get());
      if (mounted) setState(() => _thisPhone = res['matches'] == true);
    } catch (_) {
      // Offline: the server checks the device again on every scan.
    }
  }

  /// Moves the account to this phone. Works from the next class, not one that already started.
  Future<void> _useThisPhone() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Use this phone?'),
        content: const Text('Your old phone stops working for attendance.\n\n'
            'This phone can sign classes that start after now. A class that has already started cannot be signed with it.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Use this phone')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _rebinding = true);
    try {
      await Api.rebindDevice(await DeviceId.get());
      if (!mounted) return;
      setState(() => _thisPhone = true);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('This phone is now your attendance phone.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorText(e))));
    } finally {
      if (mounted) setState(() => _rebinding = false);
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
        if (!_thisPhone)
          MaterialBanner(
            content: const Text('Your account is set to another phone. Scans from this phone will be rejected.'),
            leading: const Icon(Icons.phonelink_lock),
            actions: [
              TextButton(onPressed: _rebinding ? null : _useThisPhone, child: const Text('Use this phone')),
            ],
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
