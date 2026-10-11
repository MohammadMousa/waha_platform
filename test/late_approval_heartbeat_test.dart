import 'package:flutter_test/flutter_test.dart';
import 'package:waha_kiosk/services/heartbeat_service.dart';
import 'package:waha_kiosk/services/late_approval_service.dart';

void main() {
  group('heartbeat_minutes', () {
    test('missing or unusable means off', () {
      expect(HeartbeatService.parseMinutes(null), 0);
      expect(HeartbeatService.parseMinutes(''), 0);
      expect(HeartbeatService.parseMinutes('abc'), 0);
      expect(HeartbeatService.parseMinutes('-5'), 0);
      expect(HeartbeatService.parseMinutes('0'), 0);
    });
    test('valid values are kept, capped at 1440', () {
      expect(HeartbeatService.parseMinutes('5'), 5);
      expect(HeartbeatService.parseMinutes(' 30 '), 30);
      expect(HeartbeatService.parseMinutes('99999'), 1440);
    });
  });

  group('late approval entry', () {
    test('survives being stored and read back', () {
      final e = LateApproval(
          orderId: 'o1', amount: 13.06, rrn: '627812555793', approvalCode: '217757', terminalId: '6499080464990804');
      final back = LateApproval.tryParse(_json(e.withAttempt()));
      expect(back?.orderId, 'o1');
      expect(back?.amount, 13.06);
      expect(back?.rrn, '627812555793');
      expect(back?.attempts, 1);
    });
    test('an entry without an rrn is dropped', () {
      expect(LateApproval.tryParse('{"orderId":"o1","amount":1.0}'), isNull);
      expect(LateApproval.tryParse('not json'), isNull);
    });
  });
}

String _json(LateApproval e) {
  final m = e.toJson();
  return '{${m.entries.map((x) => '"${x.key}":${x.value is String ? '"${x.value}"' : x.value}').join(',')}}';
}
