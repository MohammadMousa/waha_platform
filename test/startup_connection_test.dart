import 'package:flutter_test/flutter_test.dart';
import 'package:waha_kiosk/state/startup_connection.dart';

void main() {
  test('retry wait doubles 10, 20, 40, 80 … and is capped at 300 s', () {
    expect([for (var i = 1; i <= 8; i++) retryDelaySeconds(i)],
        [10, 20, 40, 80, 160, 300, 300, 300]);
  });
}
