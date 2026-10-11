import 'package:attendance/screens/login_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('emailForId matches the backend mapping (functions/src/roster.ts)', () {
    expect(emailForId(' S1001 '), 's1001@attendance.local');
  });
}
