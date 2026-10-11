import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../services/api.dart';
import '../../services/device.dart';

/// Camera → read QR → GPS fix → `submitScan` → show the result.
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

enum _Stage { scanning, locating, submitting, done }

class _ScanScreenState extends State<ScanScreen> {
  final _controller = MobileScannerController(formats: [BarcodeFormat.qrCode]);
  _Stage _stage = _Stage.scanning;
  bool _ok = false;
  String _title = '';
  String _detail = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_stage != _Stage.scanning) return;
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null || !_looksLikeOurQr(raw)) return;
    setState(() => _stage = _Stage.locating);
    await _controller.stop();

    // Location is sent whenever we can get it; the server decides whether the session needs it.
    Map<String, dynamic>? location;
    String? locationProblem;
    try {
      location = await currentLocation();
    } catch (e) {
      locationProblem = '$e';
    }

    setState(() => _stage = _Stage.submitting);
    try {
      final res = await Api.submitScan(qr: raw, deviceId: await DeviceId.get(), location: location);
      if (res['ok'] == true) {
        _finish(true, res['alreadyRecorded'] == true ? 'Already recorded' : 'Attendance recorded',
            '${res['subject']} · ${res['hallName']}');
      } else {
        final needsLocation = '${res['reason']}'.startsWith('location_') && locationProblem != null;
        _finish(false, 'Not recorded', needsLocation ? locationProblem : '${res['message']}');
      }
    } catch (e) {
      _finish(false, 'Could not reach the server', '${errorText(e)}\nCheck your internet connection and scan again.');
    }
  }

  bool _looksLikeOurQr(String raw) {
    try {
      final p = jsonDecode(raw);
      return p is Map && p['v'] == 1 && p['sid'] is String;
    } catch (_) {
      return false;
    }
  }

  void _finish(bool ok, String title, String detail) {
    if (!mounted) return;
    setState(() {
      _stage = _Stage.done;
      _ok = ok;
      _title = title;
      _detail = detail;
    });
  }

  Future<void> _retry() async {
    setState(() => _stage = _Stage.scanning);
    await _controller.start();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan QR')),
      body: switch (_stage) {
        _Stage.scanning => Stack(children: [
            MobileScanner(controller: _controller, onDetect: _onDetect),
            Center(
              child: Container(
                width: 260,
                height: 260,
                decoration: BoxDecoration(border: Border.all(color: Colors.white, width: 3), borderRadius: BorderRadius.circular(16)),
              ),
            ),
            const Positioned(
              left: 0,
              right: 0,
              bottom: 40,
              child: Text('Point the camera at the QR code on the screen',
                  textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 16)),
            ),
          ]),
        _Stage.locating => const _Progress('Checking your location…'),
        _Stage.submitting => const _Progress('Recording attendance…'),
        _Stage.done => Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(_ok ? Icons.check_circle : Icons.cancel, size: 96, color: _ok ? Colors.green : Colors.red),
                const SizedBox(height: 16),
                Text(_title, style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 8),
                Text(_detail, textAlign: TextAlign.center),
                const SizedBox(height: 32),
                if (_ok)
                  FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Done'))
                else
                  FilledButton(onPressed: _retry, child: const Text('Scan again')),
              ]),
            ),
          ),
      },
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(text),
        ]),
      );
}
