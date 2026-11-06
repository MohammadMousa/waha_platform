/// Exact decimal numbers for money. No binary doubles anywhere: the server
/// checks totals to the cent, so a 0.01 drift would be a TOTALS_MISMATCH.
/// Non-negative values only (prices, quantities, tax rates).
class Dec {
  final BigInt unscaled;
  final int scale; // digits after the point

  const Dec._(this.unscaled, this.scale);

  static Dec parse(String text) {
    final s = text.trim();
    if (!RegExp(r'^\d+(\.\d+)?$').hasMatch(s)) {
      throw FormatException('Not a plain decimal number: "$text"');
    }
    final dot = s.indexOf('.');
    if (dot < 0) return Dec._(BigInt.parse(s), 0);
    final digits = s.replaceFirst('.', '');
    return Dec._(BigInt.parse(digits), s.length - dot - 1);
  }

  static Dec fromInt(int v) => Dec._(BigInt.from(v), 0);

  Dec operator *(Dec o) => Dec._(unscaled * o.unscaled, scale + o.scale);

  Dec operator +(Dec o) {
    final s = scale > o.scale ? scale : o.scale;
    return Dec._(_up(s) + o._up(s), s);
  }

  BigInt _up(int s) => unscaled * BigInt.from(10).pow(s - scale);

  /// Rounds half-up to [digits] places (exactly the server's rule).
  Dec roundHalfUp(int digits) {
    if (scale <= digits) return Dec._(_up(digits), digits);
    final drop = BigInt.from(10).pow(scale - digits);
    final half = drop ~/ BigInt.two;
    return Dec._((unscaled + half) ~/ drop, digits);
  }

  /// Plain text with exactly [digits] places (rounded half-up if longer).
  String toFixed(int digits) {
    final r = roundHalfUp(digits);
    var s = r.unscaled.toString();
    if (digits == 0) return s;
    s = s.padLeft(digits + 1, '0');
    return '${s.substring(0, s.length - digits)}.${s.substring(s.length - digits)}';
  }

  @override
  String toString() => toFixed(scale);
}
