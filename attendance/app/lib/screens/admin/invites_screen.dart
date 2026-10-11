import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../services/api.dart';

/// Admin creates single-use invite codes and sends them to lecturers (WhatsApp, SMS, e-mail…).
class InvitesScreen extends StatelessWidget {
  const InvitesScreen({super.key});

  static String _message(String code, DateTime expires, String? staffId) =>
      'You are invited to the Class Attendance app as a lecturer.\n\n'
      'Open the app → Register → Lecturer, ${staffId == null ? 'fill in your details' : 'use Staff ID $staffId'} '
      'and enter invite code: $code\n\n'
      'The code works once and expires on ${DateFormat('d MMM yyyy').format(expires)}.';

  static Future<void> share(String code, DateTime expires, String? staffId) =>
      SharePlus.instance.share(ShareParams(text: _message(code, expires, staffId), subject: 'Lecturer invite code'));

  Future<void> _create(BuildContext context) async {
    final staffId = TextEditingController();
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('New invite code'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: note,
            decoration: const InputDecoration(labelText: 'For (name, optional)'),
          ),
          TextField(
            controller: staffId,
            decoration: const InputDecoration(
              labelText: 'Lock to Staff ID (optional)',
              helperText: 'Only this Staff ID will be able to use the code.',
            ),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Create')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      final sid = staffId.text.trim().isEmpty ? null : staffId.text.trim();
      final res = await Api.createInvite(staffId: sid, note: note.text.trim().isEmpty ? null : note.text.trim());
      final code = res['code'] as String;
      final expires = DateTime.fromMillisecondsSinceEpoch((res['expiresAtMs'] as num).toInt());
      if (context.mounted) await _showCode(context, code, expires, sid);
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorText(e))));
    }
  }

  Future<void> _showCode(BuildContext context, String code, DateTime expires, String? staffId) {
    return showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Invite code'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          SelectableText(code,
              style: Theme.of(context).textTheme.displaySmall?.copyWith(letterSpacing: 4, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('Single use · expires ${DateFormat('d MMM yyyy').format(expires)}'),
        ]),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.copy),
            label: const Text('Copy'),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: code));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Code copied.')));
              }
            },
          ),
          FilledButton.icon(
            icon: const Icon(Icons.send),
            label: const Text('Send'),
            onPressed: () => share(code, expires, staffId),
          ),
        ],
      ),
    );
  }

  Future<void> _revoke(BuildContext context, String code) async {
    try {
      await Api.revokeInvite(code);
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorText(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final invites =
        FirebaseFirestore.instance.collection('invites').orderBy('createdAt', descending: true).limit(100).snapshots();
    final fmt = DateFormat('d MMM yyyy');
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('New code'),
        onPressed: () => _create(context),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: invites,
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text('${snap.error}'));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final docs = snap.data!.docs;
          if (docs.isEmpty) {
            return const Center(child: Text('No invite codes yet. Create one and send it to a lecturer.'));
          }
          return ListView(
            padding: const EdgeInsets.only(bottom: 88),
            children: [
              for (final d in docs) _tile(context, d, fmt),
            ],
          );
        },
      ),
    );
  }

  Widget _tile(BuildContext context, QueryDocumentSnapshot<Map<String, dynamic>> d, DateFormat fmt) {
    final data = d.data();
    final expires = (data['expiresAt'] as Timestamp).toDate();
    final usedBy = data['usedBy'] as String?;
    final staffId = data['staffId'] as String?;
    final expired = usedBy == null && DateTime.now().isAfter(expires);
    final status = usedBy != null ? 'Used by $usedBy' : (expired ? 'Expired' : 'Active · expires ${fmt.format(expires)}');
    final who = [if (data['note'] != null) data['note'], if (staffId != null) 'Staff ID $staffId'].join(' · ');
    final active = usedBy == null && !expired;
    return ListTile(
      leading: Icon(
        usedBy != null ? Icons.check_circle : (expired ? Icons.timer_off : Icons.vpn_key),
        color: usedBy != null ? Colors.green : (expired ? Colors.grey : null),
      ),
      title: Text(d.id, style: const TextStyle(fontFamily: 'monospace', letterSpacing: 2)),
      subtitle: Text([if (who.isNotEmpty) who, status].join('\n')),
      isThreeLine: who.isNotEmpty,
      trailing: active
          ? Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(tooltip: 'Send', icon: const Icon(Icons.send), onPressed: () => share(d.id, expires, staffId)),
              IconButton(tooltip: 'Revoke', icon: const Icon(Icons.delete_outline), onPressed: () => _revoke(context, d.id)),
            ])
          : null,
    );
  }
}
