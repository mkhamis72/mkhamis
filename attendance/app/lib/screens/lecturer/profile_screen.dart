import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/api.dart';

/// Lecturer views and edits their name, university, mobile and email.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _name = TextEditingController();
  final _university = TextEditingController();
  final _mobile = TextEditingController();
  final _email = TextEditingController();
  String? _staffId;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final Map<String, dynamic> d;
    final String staffId;
    try {
      final token = await FirebaseAuth.instance.currentUser!.getIdTokenResult();
      staffId = '${token.claims?['personId'] ?? ''}';
      d = (await FirebaseFirestore.instance.collection('staff').doc(staffId).get()).data() ?? {};
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not load your details: $e')));
      Navigator.pop(context);
      return;
    }
    if (!mounted) return;
    setState(() {
      _staffId = staffId;
      _name.text = '${d['name'] ?? ''}';
      _university.text = '${d['university'] ?? ''}';
      _mobile.text = '${d['mobile'] ?? ''}';
      _email.text = '${d['email'] ?? ''}';
      _loading = false;
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await Api.updateLecturerProfile(
        name: _name.text.trim(),
        university: _university.text.trim(),
        mobile: _mobile.text.trim(),
        email: _email.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Details saved.')));
      Navigator.pop(context);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorText(e))));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My details')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(16), children: [
              ListTile(contentPadding: EdgeInsets.zero, title: const Text('Staff ID'), subtitle: Text(_staffId ?? '')),
              const SizedBox(height: 8),
              TextField(controller: _name, decoration: const InputDecoration(labelText: 'Full name', border: OutlineInputBorder())),
              const SizedBox(height: 12),
              TextField(
                controller: _university,
                decoration: const InputDecoration(labelText: 'University', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _mobile,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Mobile', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 24),
              FilledButton(onPressed: _saving ? null : _save, child: const Text('Save')),
            ]),
    );
  }
}
