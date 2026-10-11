import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/api.dart';
import '../../services/device.dart';
import 'live_session_screen.dart';

/// Lecturer sets Subject, Hall Name, GPS location and QR type (Rotating / Static), then starts the session.
class CreateSessionScreen extends StatefulWidget {
  const CreateSessionScreen({super.key});

  @override
  State<CreateSessionScreen> createState() => _CreateSessionScreenState();
}

class _CreateSessionScreenState extends State<CreateSessionScreen> {
  final _subject = TextEditingController();
  final _hall = TextEditingController();
  double? _lat;
  double? _lng;
  double? _accuracy;
  int _radius = 50;
  String _mode = 'rotating';
  bool _geofence = true;
  bool _deviceBinding = true;
  bool _timeWindow = true;
  int _windowMinutes = 15;
  bool _locating = false;
  bool _busy = false;

  bool get _isStatic => _mode == 'static';

  Future<void> _useCurrentLocation() async {
    setState(() => _locating = true);
    try {
      final loc = await currentLocation();
      setState(() {
        _lat = loc['lat'] as double;
        _lng = loc['lng'] as double;
        _accuracy = loc['accuracy'] as double;
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _applyRecent(Map<String, dynamic> p) {
    setState(() {
      _subject.text = '${p['subject']}';
      _hall.text = '${p['hallName']}';
      _lat = (p['lat'] as num).toDouble();
      _lng = (p['lng'] as num).toDouble();
      _accuracy = null;
      _radius = (p['radiusMeters'] as num?)?.toInt() ?? 50;
    });
  }

  Future<void> _start() async {
    final problem = _subject.text.trim().isEmpty
        ? 'Enter the subject.'
        : _hall.text.trim().isEmpty
            ? 'Enter the hall name.'
            : (_lat == null ? 'Set the hall GPS location (stand in the hall and tap "Use my current location").' : null);
    if (problem != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(problem)));
      return;
    }
    setState(() => _busy = true);
    try {
      final id = await Api.createSession(
        subject: _subject.text.trim(),
        hallName: _hall.text.trim(),
        lat: _lat!,
        lng: _lng!,
        radiusMeters: _radius,
        mode: _mode,
        settings: {'geofence': _isStatic || _geofence, 'deviceBinding': _deviceBinding, 'timeWindow': _timeWindow},
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
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('New attendance QR')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        _RecentPlaces(onPick: _applyRecent),
        TextField(
          controller: _subject,
          decoration: const InputDecoration(labelText: 'Subject', border: OutlineInputBorder()),
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _hall,
          decoration: const InputDecoration(labelText: 'Hall name', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 24),
        Text('Hall GPS location', style: text.titleMedium),
        const SizedBox(height: 8),
        Card(
          child: ListTile(
            leading: Icon(_lat == null ? Icons.location_off : Icons.location_on),
            title: Text(_lat == null ? 'Not set' : '${_lat!.toStringAsFixed(6)}, ${_lng!.toStringAsFixed(6)}'),
            subtitle: Text(_accuracy == null
                ? 'Stand inside the hall and tap the button'
                : 'GPS accuracy ±${_accuracy!.round()} m'),
            trailing: _locating
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                : null,
          ),
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.my_location),
          label: const Text('Use my current location'),
          onPressed: _locating ? null : _useCurrentLocation,
        ),
        const SizedBox(height: 8),
        Text('Allowed radius: $_radius m'),
        Slider(
          value: _radius.toDouble(),
          min: 20,
          max: 200,
          divisions: 18,
          label: '$_radius m',
          onChanged: (v) => setState(() => _radius = v.round()),
        ),
        const SizedBox(height: 16),
        Text('QR type', style: text.titleMedium),
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
          style: text.bodySmall,
        ),
        const SizedBox(height: 24),
        Text('Anti-cheating settings', style: text.titleMedium),
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

/// Quick picks from the lecturer's last sessions (saved by `createSession`).
class _RecentPlaces extends StatelessWidget {
  const _RecentPlaces({required this.onPick});
  final void Function(Map<String, dynamic>) onPick;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<IdTokenResult>(
      future: FirebaseAuth.instance.currentUser!.getIdTokenResult(),
      builder: (context, token) {
        final staffId = token.data?.claims?['personId'];
        if (staffId == null) return const SizedBox.shrink();
        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance.collection('staff').doc('$staffId').snapshots(),
          builder: (context, snap) {
            final recent = List<Map<String, dynamic>>.from(
                (snap.data?.data()?['recentPlaces'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)));
            if (recent.isEmpty) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Recent', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 4),
                Wrap(spacing: 8, runSpacing: 4, children: [
                  for (final p in recent)
                    ActionChip(
                      avatar: const Icon(Icons.history, size: 18),
                      label: Text('${p['subject']} · ${p['hallName']}'),
                      onPressed: () => onPick(p),
                    ),
                ]),
              ]),
            );
          },
        );
      },
    );
  }
}
