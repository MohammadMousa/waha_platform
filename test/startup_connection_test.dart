import 'package:flutter_test/flutter_test.dart';
import 'package:waha_kiosk/state/startup_connection.dart';

void main() {
  test('retry wait grows 10, 20, 30 … and is capped at 60 s', () {
    expect([for (var i = 1; i <= 8; i++) retryDelaySeconds(i)],
        [10, 20, 30, 40, 50, 60, 60, 60]);
  });
}
