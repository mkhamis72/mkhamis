import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

String _cell(Object? v) {
  final s = '${v ?? ''}';
  return s.contains(RegExp('[",\n]')) ? '"${s.replaceAll('"', '""')}"' : s;
}

/// Shares attendance records as a CSV file (save, e-mail, etc. via the OS share sheet).
Future<void> shareAttendanceCsv(Iterable<Map<String, dynamic>> records, String filename) async {
  final fmt = DateFormat('yyyy-MM-dd HH:mm:ss');
  final rows = [
    ['student_id', 'name', 'subject', 'hall', 'time', 'distance_m', 'flags'],
    for (final d in records)
      [
        d['studentId'],
        d['studentName'],
        d['subject'],
        d['hallName'],
        d['at'] is Timestamp ? fmt.format((d['at'] as Timestamp).toDate()) : '',
        d['distanceMeters'] is num ? (d['distanceMeters'] as num).round() : '',
        (d['flags'] as List? ?? const []).join(' '),
      ],
  ];
  final csv = rows.map((r) => r.map(_cell).join(',')).join('\n');
  await Printing.sharePdf(bytes: Uint8List.fromList(utf8.encode(csv)), filename: filename);
}
