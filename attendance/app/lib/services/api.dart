import 'package:cloud_functions/cloud_functions.dart';

/// Thin wrappers over the Cloud Functions in `functions/src/index.ts`.
class Api {
  Api._();
  static final _fn = FirebaseFunctions.instance;

  static Future<Map<String, dynamic>> _call(String name, [Map<String, dynamic>? data]) async {
    final res = await _fn.httpsCallable(name).call<Map<String, dynamic>>(data);
    return Map<String, dynamic>.from(res.data);
  }

  // Student
  static Future<Map<String, dynamic>> registerDevice(String deviceId) =>
      _call('registerDevice', {'deviceId': deviceId});

  static Future<Map<String, dynamic>> submitScan({
    required String qr,
    required String deviceId,
    Map<String, dynamic>? location,
  }) =>
      _call('submitScan', {'qr': qr, 'deviceId': deviceId, 'location': location});

  // Lecturer
  static Future<String> createSession({
    required String courseId,
    required String hallId,
    required String mode, // 'rotating' | 'static'
    required Map<String, bool> settings,
    required int windowMinutes,
  }) async {
    final res = await _call('createSession', {
      'courseId': courseId,
      'hallId': hallId,
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

  static Future<void> overrideAttendance(String sessionId, String studentId, bool present) =>
      _call('overrideAttendance', {'sessionId': sessionId, 'studentId': studentId, 'present': present});

  // Admin
  static Future<Map<String, dynamic>> importRoster(String csv) => _call('importRoster', {'csv': csv});

  static Future<void> resetDevice(String studentId) => _call('resetDevice', {'studentId': studentId});
}

/// Readable text for a failed callable.
String errorText(Object e) => e is FirebaseFunctionsException ? (e.message ?? e.code) : '$e';
