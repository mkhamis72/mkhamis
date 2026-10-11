import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../services/api.dart';
import 'session_report_screen.dart';

/// Full-screen QR for the projector / lecturer phone, with a live count and session controls.
class LiveSessionScreen extends StatefulWidget {
  const LiveSessionScreen({super.key, required this.sessionId});
  final String sessionId;

  @override
  State<LiveSessionScreen> createState() => _LiveSessionScreenState();
}

class _LiveSessionScreenState extends State<LiveSessionScreen> {
  String? _qr;
  String? _error;
  Timer? _timer;
  String? _lastStatus;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// Rotating: fetch, then schedule the next fetch for when the slot changes. Static: fetch once.
  Future<void> _refreshQr() async {
    _timer?.cancel();
    try {
      final res = await Api.getQrToken(widget.sessionId);
      if (!mounted) return;
      setState(() {
        _qr = res['qr'] as String;
        _error = null;
      });
      final refreshAt = res['refreshAtMs'] as num?;
      if (refreshAt != null) {
        final wait = Duration(milliseconds: refreshAt.toInt() - DateTime.now().millisecondsSinceEpoch + 200);
        _timer = Timer(wait.isNegative ? Duration.zero : wait, _refreshQr);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Connection problem. Retrying… (${errorText(e)})');
      _timer = Timer(const Duration(seconds: 3), _refreshQr);
    }
  }

  void _onStatus(String status) {
    if (status == _lastStatus) return;
    _lastStatus = status;
    if (status == 'open') {
      _refreshQr();
    } else {
      _timer?.cancel();
    }
  }

  Future<void> _action(String action, {int? minutes}) async {
    try {
      await Api.updateSession(widget.sessionId, action, minutes: minutes);
      if (action == 'regenerate') await _refreshQr();
      if (action == 'end' && mounted) {
        Navigator.pushReplacement(
            context, MaterialPageRoute(builder: (_) => SessionReportScreen(sessionId: widget.sessionId)));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorText(e))));
    }
  }

  Future<void> _confirmEnd() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('End session?'),
        content: const Text('Students will no longer be able to sign in.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('End')),
        ],
      ),
    );
    if (ok == true) await _action('end');
  }

  Future<void> _printStatic(Map<String, dynamic> s) async {
    final qr = _qr;
    if (qr == null) return;
    final doc = pw.Document()
      ..addPage(pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (_) => pw.Center(
          child: pw.Column(mainAxisSize: pw.MainAxisSize.min, children: [
            pw.Text('${s['subject']}', style: const pw.TextStyle(fontSize: 32, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 8),
            pw.Text('${s['hallName']}', style: const pw.TextStyle(fontSize: 22)),
            pw.SizedBox(height: 32),
            pw.BarcodeWidget(barcode: pw.Barcode.qrCode(), data: qr, width: 380, height: 380),
            pw.SizedBox(height: 24),
            pw.Text('Scan with the Attendance app. You must be inside the hall.'),
          ]),
        ),
      ));
    await Printing.layoutPdf(name: 'attendance-${s['subject']}-${s['hallName']}', onLayout: (_) => doc.save());
  }

  @override
  Widget build(BuildContext context) {
    final sessionRef = FirebaseFirestore.instance.collection('sessions').doc(widget.sessionId);
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: sessionRef.snapshots(),
      builder: (context, snap) {
        final s = snap.data?.data();
        if (s == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
        final status = s['status'] as String;
        WidgetsBinding.instance.addPostFrameCallback((_) => _onStatus(status));
        final rotating = s['mode'] == 'rotating';
        final settings = Map<String, dynamic>.from(s['settings'] ?? {});

        return Scaffold(
          appBar: AppBar(
            title: Text('${s['subject']} · ${s['hallName']}'),
            actions: [
              IconButton(
                tooltip: 'Attendees',
                icon: const Icon(Icons.people),
                onPressed: () => Navigator.push(
                    context, MaterialPageRoute(builder: (_) => SessionReportScreen(sessionId: widget.sessionId))),
              ),
              PopupMenuButton<String>(
                onSelected: (v) => v == 'extend' ? _action('extend', minutes: 5) : _action(v),
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'regenerate', child: Text('Regenerate QR (old codes stop working)')),
                  if (settings['timeWindow'] == true) const PopupMenuItem(value: 'extend', child: Text('Extend time by 5 min')),
                ],
              ),
            ],
          ),
          body: LayoutBuilder(builder: (context, box) {
            final size = (box.biggest.shortestSide - 140).clamp(160.0, 720.0);
            return Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('${s['attendeeCount'] ?? 0} present',
                    style: Theme.of(context).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                if (status != 'open')
                  SizedBox(
                    width: size,
                    height: size,
                    child: Center(child: Text(status == 'paused' ? 'Paused' : 'Ended', style: Theme.of(context).textTheme.headlineMedium)),
                  )
                else if (_qr == null)
                  SizedBox(width: size, height: size, child: const Center(child: CircularProgressIndicator()))
                else
                  Container(
                    color: Colors.white,
                    padding: const EdgeInsets.all(16),
                    child: QrImageView(data: _qr!, size: size, backgroundColor: Colors.white),
                  ),
                const SizedBox(height: 8),
                Text(rotating ? 'Code refreshes every 10 seconds' : 'Static code · location check on'),
                if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ]),
            );
          }),
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(alignment: WrapAlignment.center, spacing: 12, runSpacing: 8, children: [
                if (status == 'open')
                  OutlinedButton.icon(icon: const Icon(Icons.pause), label: const Text('Pause'), onPressed: () => _action('pause'))
                else if (status == 'paused')
                  OutlinedButton.icon(icon: const Icon(Icons.play_arrow), label: const Text('Resume'), onPressed: () => _action('resume')),
                if (!rotating && status == 'open')
                  OutlinedButton.icon(icon: const Icon(Icons.print), label: const Text('Print / PDF'), onPressed: () => _printStatic(s)),
                if (status != 'ended')
                  FilledButton.icon(icon: const Icon(Icons.stop), label: const Text('End session'), onPressed: _confirmEnd),
              ]),
            ),
          ),
        );
      },
    );
  }
}
