import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/api.dart';

/// Admin tab: approve or reject lecturer accounts waiting for confirmation.
class ApprovalsScreen extends StatelessWidget {
  const ApprovalsScreen({super.key});

  Future<void> _decide(BuildContext context, String staffId, String name, bool approve) async {
    if (!approve) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Reject lecturer?'),
          content: Text('The account of $name ($staffId) will be deleted.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Reject')),
          ],
        ),
      );
      if (ok != true) return;
    }
    try {
      await Api.approveLecturer(staffId, approve);
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorText(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final pending = FirebaseFirestore.instance.collection('staff').where('status', isEqualTo: 'pending').snapshots();
    final fmt = DateFormat('d MMM yyyy, HH:mm');
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: pending,
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Text('${snap.error}'));
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final docs = snap.data!.docs;
        if (docs.isEmpty) return const Center(child: Text('No lecturers waiting for approval.'));
        return ListView(
          padding: const EdgeInsets.only(bottom: 88),
          children: [
            for (final d in docs)
              ListTile(
                leading: const Icon(Icons.person_outline),
                title: Text('${d['name']} (${d.id})'),
                subtitle: d.data()['createdAt'] is Timestamp
                    ? Text('Registered ${fmt.format((d['createdAt'] as Timestamp).toDate())}')
                    : null,
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(
                    tooltip: 'Reject',
                    icon: const Icon(Icons.close, color: Colors.red),
                    onPressed: () => _decide(context, d.id, '${d['name']}', false),
                  ),
                  IconButton(
                    tooltip: 'Approve',
                    icon: const Icon(Icons.check, color: Colors.green),
                    onPressed: () => _decide(context, d.id, '${d['name']}', true),
                  ),
                ]),
              ),
          ],
        );
      },
    );
  }
}
