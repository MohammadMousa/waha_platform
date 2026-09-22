import 'package:flutter_test/flutter_test.dart';
import 'package:waha_kiosk/services/geidea_terminal_bridge.dart';

/// Mirrors the checks in Geidea pos-comm-sdk-ksa 1.3.0
/// TerminalResponder.initiatePurchaseTransaction: spaces stripped, then
/// `^[a-zA-Z0-9]+$` and length <= 25 — otherwise the SDK answers error 16
/// locally. Plus the real wire limit: the ECR field (tag DF8110) is 16 bytes.
bool sdkAccepts(String ref) {
  final r = ref.replaceAll(' ', '').trim();
  return r.length <= 25 && RegExp(r'^[a-zA-Z0-9]+$').hasMatch(r);
}

void main() {
  // Order ids taken from the client's trace logs (both failed with error 16).
  const clientOrderIds = [
    '01a0c2c8-4418-75e3-be6b-ba5018595534',
    '01a0c2c8-f3a8-759a-8be1-3126d20cc34b',
  ];

  test('the raw order ids were rejected by the SDK check', () {
    for (final id in clientOrderIds) {
      expect(sdkAccepts(id), isFalse, reason: id);
    }
  });

  test('derived reference passes the SDK check and fits the 16-byte ECR field', () {
    for (final id in clientOrderIds) {
      final ref = GeideaTerminalBridge.ecrReferenceFor(id);
      expect(sdkAccepts(ref), isTrue, reason: ref);
      expect(ref.length, lessThanOrEqualTo(GeideaTerminalBridge.ecrReferenceMaxLength));
      expect(ref, id.replaceAll('-', '').substring(0, 16));
    }
  });

  test('deterministic, and different orders give different references', () {
    final a = GeideaTerminalBridge.ecrReferenceFor(clientOrderIds[0]);
    final b = GeideaTerminalBridge.ecrReferenceFor(clientOrderIds[1]);
    expect(GeideaTerminalBridge.ecrReferenceFor(clientOrderIds[0]), a);
    expect(a, isNot(b));
  });

  test('short ids are only stripped, never padded or cut', () {
    expect(GeideaTerminalBridge.ecrReferenceFor('ab-12 cd'), 'ab12cd');
    expect(GeideaTerminalBridge.ecrReferenceFor('A1B2C3D4E5F6G7H8'), 'A1B2C3D4E5F6G7H8');
  });
}
