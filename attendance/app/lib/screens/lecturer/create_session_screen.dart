import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../services/api.dart';
import 'live_session_screen.dart';

/// Lecturer picks hall, QR type (rotating / static) and anti-cheat settings, then starts the session.
class CreateSessionScreen extends StatefulWidget {
  const CreateSessionScreen({super.key, required this.courseId, required this.course});
  final String courseId;
  final Map<String, dynamic> course;

  @override
  State<CreateSessionScreen> createState() => _CreateSessionScreenState();
}

class _CreateSessionScreenState extends State<CreateSessionScreen> {
  String _mode = 'rotating';
  String? _hallId;
  late bool _geofence;
  late bool _deviceBinding;
  late bool _timeWindow;
  late int _windowMinutes;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final d = Map<String, dynamic>.from(widget.course['defaultSettings'] ?? {});
    _geofence = d['geofence'] != false;
    _deviceBinding = d['deviceBinding'] != false;
    _timeWindow = d['timeWindow'] != false;
    _windowMinutes = (widget.course['defaultWindowMinutes'] as num?)?.toInt() ?? 15;
    _hallId = widget.course['defaultHallId'] as String?;
  }

  bool get _isStatic => _mode == 'static';

  Future<void> _start() async {
    if (_hallId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Choose a hall.')));
      return;
    }
    setState(() => _busy = true);
    try {
      final id = await Api.createSession(
        courseId: widget.courseId,
        hallId: _hallId!,
        mode: _mode,
        settings: {
          'geofence': _isStatic || _geofence,
          'deviceBinding': _deviceBinding,
          'timeWindow': _timeWindow,
        },
        windowMinutes: _windowMinutes,
      );
      if (!mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => LiveSessionScreen(sessionId: id)));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorText(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('New QR · ${widget.course['subject']}')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text('Hall', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance.collection('halls').orderBy('name').snapshots(),
          builder: (context, snap) {
            final halls = snap.data?.docs ?? [];
            return DropdownButtonFormField<String>(
              key: ValueKey(halls.length),
              initialValue: halls.any((h) => h.id == _hallId) ? _hallId : null,
              decoration: const InputDecoration(border: OutlineInputBorder()),
              hint: const Text('Choose a hall'),
              items: [for (final h in halls) DropdownMenuItem(value: h.id, child: Text('${h['name']}'))],
              onChanged: (v) => setState(() => _hallId = v),
            );
          },
        ),
        const SizedBox(height: 24),
        Text('QR type', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'rotating', icon: Icon(Icons.autorenew), label: Text('Rotating')),
            ButtonSegment(value: 'static', icon: Icon(Icons.print), label: Text('Static')),
          ],
          selected: {_mode},
          onSelectionChanged: (s) => setState(() => _mode = s.first),
        ),
        const SizedBox(height: 8),
        Text(
          _isStatic
              ? 'Shown once or printed. Works without a live screen. Location check is always on, because a static code can be photographed and shared.'
              : 'Changes every 10 seconds on your screen. Needs internet on this device. A shared screenshot expires almost at once.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 24),
        Text('Anti-cheating settings', style: Theme.of(context).textTheme.titleMedium),
        SwitchListTile(
          title: const Text('Location (geofence)'),
          subtitle: Text(_isStatic ? 'Required for static QR' : 'Student must be inside the hall'),
          value: _isStatic || _geofence,
          onChanged: _isStatic ? null : (v) => setState(() => _geofence = v),
        ),
        SwitchListTile(
          title: const Text('Device binding'),
          subtitle: const Text('One phone per student, one student per phone'),
          value: _deviceBinding,
          onChanged: (v) => setState(() => _deviceBinding = v),
        ),
        SwitchListTile(
          title: const Text('Time window'),
          subtitle: Text('Scans accepted for $_windowMinutes minutes after start'),
          value: _timeWindow,
          onChanged: (v) => setState(() => _timeWindow = v),
        ),
        if (_timeWindow)
          Slider(
            value: _windowMinutes.toDouble(),
            min: 5,
            max: 90,
            divisions: 17,
            label: '$_windowMinutes min',
            onChanged: (v) => setState(() => _windowMinutes = v.round()),
          ),
        const SizedBox(height: 24),
        FilledButton.icon(
          icon: const Icon(Icons.play_arrow),
          label: const Text('Start & show QR'),
          onPressed: _busy ? null : _start,
        ),
      ]),
    );
  }
}
