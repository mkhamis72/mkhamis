import 'package:cloud_functions/cloud_functions.dart';

/// Thin wrappers over the Cloud Functions in `functions/src/index.ts`.
class Api {
  Api._();
  static final _fn = FirebaseFunctions.instance;

  static Future<Map<String, dynamic>> _call(String name, [Map<String, dynamic>? data]) async {
    final res = await _fn.httpsCallable(name).call<Map<String, dynamic>>(data);
    return Map<String, dynamic>.from(res.data);
  }

  // Registration
  static Future<void> registerStudent({
    required String studentId,
    required String name,
    required String password,
    required String deviceId,
  }) =>
      _call('registerStudent', {'studentId': studentId, 'name': name, 'password': password, 'deviceId': deviceId});

  static Future<void> registerLecturer({required String staffId, required String name, required String password}) =>
      _call('registerLecturer', {'staffId': staffId, 'name': name, 'password': password});

  // Student
  static Future<Map<String, dynamic>> deviceStatus(String deviceId) => _call('deviceStatus', {'deviceId': deviceId});

  static Future<void> rebindDevice(String deviceId) => _call('rebindDevice', {'deviceId': deviceId});

  static Future<Map<String, dynamic>> submitScan({
    required String qr,
    required String deviceId,
    Map<String, dynamic>? location,
  }) =>
      _call('submitScan', {'qr': qr, 'deviceId': deviceId, 'location': location});

  // Lecturer
  static Future<String> createSession({
    required String subject,
    required String hallName,
    required double lat,
    required double lng,
    required int radiusMeters,
    required String mode, // 'rotating' | 'static'
    required Map<String, bool> settings,
    required int windowMinutes,
  }) async {
    final res = await _call('createSession', {
      'subject': subject,
      'hallName': hallName,
      'lat': lat,
      'lng': lng,
      'radiusMeters': radiusMeters,
      'mode': mode,
      'settings': settings,
      'windowMinutes': windowMinutes,
    });
    return res['sessionId'] as String;
  }

  static Future<Map<String, dynamic>> getQrToken(String sessionId) => _call('getQrToken', {'sessionId': sessionId});

  /// action: pause | resume | end | regenerate | extend
  static Future<void> updateSession(String sessionId, String action, {int? minutes}) =>
      _call('updateSession', {'sessionId': sessionId, 'action': action, 'minutes': minutes});

  static Future<void> removeAttendance(String sessionId, String studentId) =>
      _call('removeAttendance', {'sessionId': sessionId, 'studentId': studentId});
}

/// Readable text for a failed callable.
String errorText(Object e) => e is FirebaseFunctionsException ? (e.message ?? e.code) : '$e';
