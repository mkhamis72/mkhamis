import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/api.dart';
import '../../services/device.dart';

class AdminHome extends StatelessWidget {
  const AdminHome({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Admin'),
          actions: [
            IconButton(tooltip: 'Sign out', icon: const Icon(Icons.logout), onPressed: () => FirebaseAuth.instance.signOut()),
          ],
          bottom: const TabBar(tabs: [Tab(text: 'Roster'), Tab(text: 'Halls'), Tab(text: 'Courses')]),
        ),
        body: const TabBarView(children: [_RosterTab(), _HallsTab(), _CoursesTab()]),
      ),
    );
  }
}

void _snack(BuildContext context, String text) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

// ---------------------------------------------------------------------------

class _RosterTab extends StatefulWidget {
  const _RosterTab();

  @override
  State<_RosterTab> createState() => _RosterTabState();
}

class _RosterTabState extends State<_RosterTab> {
  final _csv = TextEditingController();
  final _resetId = TextEditingController();
  String? _result;
  bool _busy = false;

  Future<void> _import() async {
    setState(() => _busy = true);
    try {
      final r = await Api.importRoster(_csv.text);
      final errors = List<String>.from(r['errors'] ?? const []);
      setState(() => _result = 'Created ${r['created']}, updated ${r['updated']}'
          '${errors.isEmpty ? '' : '\n${errors.length} errors:\n${errors.join('\n')}'}');
    } catch (e) {
      setState(() => _result = errorText(e));
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _reset() async {
    try {
      await Api.resetDevice(_resetId.text.trim());
      if (mounted) _snack(context, 'Device reset. The student can sign in on a new phone.');
    } catch (e) {
      if (mounted) _snack(context, errorText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text('Import users (CSV)', style: Theme.of(context).textTheme.titleMedium),
      const Text('One per line: id,name,role,password  (role = student | lecturer | admin). '
          'Existing users are updated; leave password empty to keep it.'),
      const SizedBox(height: 8),
      TextField(
        controller: _csv,
        maxLines: 10,
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
          hintText: 'id,name,role,password\nS1001,Ali Hassan,student,ChangeMe1\nL01,Dr. Sara Adel,lecturer,ChangeMe2',
        ),
      ),
      const SizedBox(height: 8),
      FilledButton(onPressed: _busy ? null : _import, child: const Text('Import')),
      if (_result != null) Padding(padding: const EdgeInsets.only(top: 8), child: SelectableText(_result!)),
      const Divider(height: 40),
      Text('Reset device binding', style: Theme.of(context).textTheme.titleMedium),
      const Text('Use when a student changes or loses their phone.'),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(
          child: TextField(
            controller: _resetId,
            decoration: const InputDecoration(labelText: 'Student ID', border: OutlineInputBorder()),
          ),
        ),
        const SizedBox(width: 8),
        OutlinedButton(onPressed: _reset, child: const Text('Reset')),
      ]),
    ]);
  }
}

// ---------------------------------------------------------------------------

class _HallsTab extends StatelessWidget {
  const _HallsTab();

  @override
  Widget build(BuildContext context) {
    final halls = FirebaseFirestore.instance.collection('halls');
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('Hall'),
        onPressed: () => showDialog(context: context, builder: (_) => const _HallDialog()),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: halls.orderBy('name').snapshots(),
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          return ListView(children: [
            for (final h in snap.data!.docs)
              ListTile(
                leading: const Icon(Icons.meeting_room),
                title: Text('${h['name']}'),
                subtitle: Text('${h['lat']}, ${h['lng']} · radius ${h['radiusMeters']} m'),
                onTap: () => showDialog(context: context, builder: (_) => _HallDialog(doc: h)),
              ),
          ]);
        },
      ),
    );
  }
}

class _HallDialog extends StatefulWidget {
  const _HallDialog({this.doc});
  final DocumentSnapshot<Map<String, dynamic>>? doc;

  @override
  State<_HallDialog> createState() => _HallDialogState();
}

class _HallDialogState extends State<_HallDialog> {
  late final _name = TextEditingController(text: widget.doc?['name'] ?? '');
  late final _lat = TextEditingController(text: '${widget.doc?['lat'] ?? ''}');
  late final _lng = TextEditingController(text: '${widget.doc?['lng'] ?? ''}');
  late final _radius = TextEditingController(text: '${widget.doc?['radiusMeters'] ?? 50}');

  /// Easiest way to capture coordinates: stand in the middle of the hall and tap this.
  Future<void> _useHere() async {
    try {
      final loc = await currentLocation();
      setState(() {
        _lat.text = (loc['lat'] as double).toStringAsFixed(6);
        _lng.text = (loc['lng'] as double).toStringAsFixed(6);
      });
      if (mounted) _snack(context, 'GPS accuracy ±${(loc['accuracy'] as double).round()} m');
    } catch (e) {
      if (mounted) _snack(context, '$e');
    }
  }

  Future<void> _save() async {
    final lat = double.tryParse(_lat.text), lng = double.tryParse(_lng.text), r = int.tryParse(_radius.text);
    if (_name.text.trim().isEmpty || lat == null || lng == null || r == null || r < 10) {
      _snack(context, 'Fill name, valid coordinates and a radius of at least 10 m.');
      return;
    }
    final data = {'name': _name.text.trim(), 'lat': lat, 'lng': lng, 'radiusMeters': r};
    final col = FirebaseFirestore.instance.collection('halls');
    await (widget.doc == null ? col.add(data) : col.doc(widget.doc!.id).set(data));
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.doc == null ? 'New hall' : 'Edit hall'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: _name, decoration: const InputDecoration(labelText: 'Name')),
          TextField(controller: _lat, decoration: const InputDecoration(labelText: 'Latitude'), keyboardType: TextInputType.number),
          TextField(controller: _lng, decoration: const InputDecoration(labelText: 'Longitude'), keyboardType: TextInputType.number),
          TextField(controller: _radius, decoration: const InputDecoration(labelText: 'Radius (m)'), keyboardType: TextInputType.number),
          const SizedBox(height: 8),
          OutlinedButton.icon(icon: const Icon(Icons.my_location), label: const Text('Use my current location'), onPressed: _useHere),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _CoursesTab extends StatelessWidget {
  const _CoursesTab();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('Course'),
        onPressed: () => showDialog(context: context, builder: (_) => const _CourseDialog()),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('courses').orderBy('subject').snapshots(),
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          return ListView(children: [
            for (final c in snap.data!.docs)
              ListTile(
                leading: const Icon(Icons.class_),
                title: Text('${c['subject']}'),
                subtitle: Text('Lecturer ${c.data()['lecturerId'] ?? '-'} · ${(c.data()['studentIds'] as List?)?.length ?? 0} students'),
                onTap: () => showDialog(context: context, builder: (_) => _CourseDialog(doc: c)),
              ),
          ]);
        },
      ),
    );
  }
}

class _CourseDialog extends StatefulWidget {
  const _CourseDialog({this.doc});
  final DocumentSnapshot<Map<String, dynamic>>? doc;

  @override
  State<_CourseDialog> createState() => _CourseDialogState();
}

class _CourseDialogState extends State<_CourseDialog> {
  late final Map<String, dynamic> _d = widget.doc?.data() ?? {};
  late final _subject = TextEditingController(text: _d['subject'] ?? '');
  late final _lecturerId = TextEditingController(text: _d['lecturerId'] ?? '');
  late final _students = TextEditingController(text: List<String>.from(_d['studentIds'] ?? const []).join('\n'));
  late String? _hallId = _d['defaultHallId'] as String?;
  late final Map<String, bool> _defaults = {
    'geofence': _d['defaultSettings']?['geofence'] != false,
    'deviceBinding': _d['defaultSettings']?['deviceBinding'] != false,
    'timeWindow': _d['defaultSettings']?['timeWindow'] != false,
  };

  Future<void> _save() async {
    final db = FirebaseFirestore.instance;
    final lecturer = await db.collection('staff').doc(_lecturerId.text.trim()).get();
    if (!lecturer.exists || lecturer['role'] != 'lecturer') {
      if (mounted) _snack(context, 'Lecturer ID not found. Import the lecturer first.');
      return;
    }
    final ids = _students.text.split(RegExp(r'[\s,;]+')).where((s) => s.isNotEmpty).toSet().toList();
    final data = {
      'subject': _subject.text.trim(),
      'lecturerId': _lecturerId.text.trim(),
      'lecturerUid': lecturer['authUid'],
      'studentIds': ids,
      'defaultHallId': _hallId,
      'defaultSettings': _defaults,
      'defaultWindowMinutes': _d['defaultWindowMinutes'] ?? 15,
    };
    final col = db.collection('courses');
    await (widget.doc == null ? col.add(data) : col.doc(widget.doc!.id).set(data));
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.doc == null ? 'New course' : 'Edit course'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: _subject, decoration: const InputDecoration(labelText: 'Subject')),
            TextField(controller: _lecturerId, decoration: const InputDecoration(labelText: 'Lecturer ID')),
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance.collection('halls').orderBy('name').snapshots(),
              builder: (context, snap) {
                final halls = snap.data?.docs ?? [];
                return DropdownButtonFormField<String>(
                  key: ValueKey(halls.length),
                  initialValue: halls.any((h) => h.id == _hallId) ? _hallId : null,
                  decoration: const InputDecoration(labelText: 'Default hall'),
                  items: [for (final h in halls) DropdownMenuItem(value: h.id, child: Text('${h['name']}'))],
                  onChanged: (v) => setState(() => _hallId = v),
                );
              },
            ),
            TextField(
              controller: _students,
              maxLines: 6,
              decoration: const InputDecoration(labelText: 'Student IDs (one per line or comma separated)'),
            ),
            const SizedBox(height: 8),
            const Align(alignment: Alignment.centerLeft, child: Text('Default anti-cheat settings')),
            for (final key in _defaults.keys)
              SwitchListTile(
                dense: true,
                title: Text(const {'geofence': 'Location (geofence)', 'deviceBinding': 'Device binding', 'timeWindow': 'Time window'}[key]!),
                value: _defaults[key]!,
                onChanged: (v) => setState(() => _defaults[key] = v),
              ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
