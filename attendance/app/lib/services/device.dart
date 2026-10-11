import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:geolocator/geolocator.dart';
import 'package:uuid/uuid.dart';

/// Stable per-install device id kept in the Keychain / Keystore, used for device binding.
class DeviceId {
  DeviceId._();
  static const _storage = FlutterSecureStorage();
  static const _key = 'attendance_device_id';
  static String? _cached;

  static Future<String> get() async {
    if (_cached != null) return _cached!;
    var id = await _storage.read(key: _key);
    if (id == null) {
      id = const Uuid().v4();
      await _storage.write(key: _key, value: id);
    }
    return _cached = id;
  }
}

class LocationException implements Exception {
  LocationException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Gets a fresh high-accuracy fix in the shape `submitScan` expects.
Future<Map<String, dynamic>> currentLocation() async {
  if (!await Geolocator.isLocationServiceEnabled()) {
    throw LocationException('Turn on location (GPS) to sign attendance.');
  }
  var perm = await Geolocator.checkPermission();
  if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
  if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
    throw LocationException('Location permission is required to sign attendance.');
  }
  final pos = await Geolocator.getCurrentPosition(
    locationSettings: const LocationSettings(accuracy: LocationAccuracy.best, timeLimit: Duration(seconds: 15)),
  );
  return {'lat': pos.latitude, 'lng': pos.longitude, 'accuracy': pos.accuracy, 'isMocked': pos.isMocked};
}
