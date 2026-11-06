/// Order reference: `<prefix>-<deviceNo 2 digits>-<serial>`, e.g. WH-01-0233.
/// The serial counts up per device and wraps from [maxSerial] to 0. One
/// constant sets the width (3 or 4 digits); the server accepts either.
const int kReferenceSerialDigits = 4;
final int kReferenceMaxSerial = _pow10(kReferenceSerialDigits) - 1;

int _pow10(int n) {
  var v = 1;
  for (var i = 0; i < n; i++) {
    v *= 10;
  }
  return v;
}

/// The serial after [last]; null (no order yet) starts at 1.
int nextSerial(int? last) {
  if (last == null) return 1;
  return last >= kReferenceMaxSerial ? 0 : last + 1;
}

/// Builds the reference. [shortCode] wins; an empty one falls back to the
/// store id. The result only uses letters, digits, dot, dash and underscore
/// and is at most 30 characters.
String buildReference({
  required String? shortCode,
  required int storeId,
  required int deviceNo,
  required int serial,
}) {
  final cleaned = (shortCode ?? '').replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '');
  final prefix = cleaned.isEmpty ? '$storeId' : cleaned;
  final ref = '$prefix-${deviceNo.toString().padLeft(2, '0')}-'
      '${serial.toString().padLeft(kReferenceSerialDigits, '0')}';
  return ref.length > 30 ? ref.substring(ref.length - 30) : ref;
}
