import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'approvals_screen.dart';
import 'invites_screen.dart';

/// Admin: approve lecturers who registered without a code, and send invite codes.
class AdminHome extends StatelessWidget {
  const AdminHome({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text('Admin · ${FirebaseAuth.instance.currentUser?.displayName ?? ''}'),
          actions: [
            IconButton(tooltip: 'Sign out', icon: const Icon(Icons.logout), onPressed: () => FirebaseAuth.instance.signOut()),
          ],
          bottom: const TabBar(tabs: [Tab(text: 'Approvals'), Tab(text: 'Invite codes')]),
        ),
        body: const TabBarView(children: [ApprovalsScreen(), InvitesScreen()]),
      ),
    );
  }
}
