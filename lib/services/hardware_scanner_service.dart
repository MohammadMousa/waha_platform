import 'package:flutter/services.dart';

typedef HardwareScanCallback = void Function(String barcode);

/// Captures input from a hardware barcode scanner acting as a keyboard
/// (USB/BT "keyboard wedge": types the barcode's digits, then Enter).
///
/// Listens at the [HardwareKeyboard] level instead of through a focused
/// TextField, so a scan works on any screen regardless of what currently
/// has focus — including screens with no text field at all (Cart,
/// Checkout, Browse...). This is what makes scanning "just always work":
/// there's no invisible field to lose when the customer navigates away
/// from Landing, and no focus-stealing to fight with other widgets.
///
/// A scanner's keystrokes arrive far faster than a human can type (single
/// digit-milliseconds apart, vs 100ms+ between real keypresses), so a scan
/// burst is told apart from normal typing purely by inter-key timing: any
/// gap longer than [_maxKeyGap] resets the buffer. Listeners here never
/// consume events (the handler always returns false for anything but a
/// recognized scan's own Enter), so a person typing into a real focused
/// TextField elsewhere is completely unaffected — their keystrokes still
/// reach that field normally; they just also pass through this buffer,
/// which won't assemble into anything (each keystroke resets it).
///
/// Listeners form a stack, not a broadcast group: with ordinary
/// `pushNamed` navigation, a screen lower in the Navigator's route stack
/// stays mounted (just offstage) under the current one, so several
/// `HardwareScanListener`s can be registered at once. Only the most
/// recently registered (i.e. the screen actually on top) should act on a
/// scan — notifying every registered listener would add the same scan to
/// the cart once per screen still sitting underneath.
class HardwareScannerService {
  HardwareScannerService._();
  static final HardwareScannerService instance = HardwareScannerService._();

  static const _maxKeyGap = Duration(milliseconds: 100);
  static const _minLength = 3;
  static const _maxLength = 64;

  final _buffer = StringBuffer();
  DateTime? _lastKeyTime;
  bool _attached = false;

  final _listeners = <HardwareScanCallback>[];

  void addListener(HardwareScanCallback callback) {
    _listeners.add(callback);
    if (!_attached) {
      _attached = true;
      HardwareKeyboard.instance.addHandler(_handleKeyEvent);
    }
  }

  void removeListener(HardwareScanCallback callback) {
    _listeners.remove(callback);
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent || _listeners.isEmpty) return false;

    final now = DateTime.now();
    if (_lastKeyTime == null || now.difference(_lastKeyTime!) > _maxKeyGap) {
      _buffer.clear();
    }
    _lastKeyTime = now;

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) {
      final code = _buffer.toString();
      _buffer.clear();
      if (code.length < _minLength) return false;
      _listeners.last(code);
      // Swallow only a recognized scan's own Enter, so it can't also
      // trigger whatever (if anything) happens to be focused underneath.
      return true;
    }

    final char = event.character;
    if (char != null && char.length == 1 && char.codeUnitAt(0) >= 0x20) {
      if (_buffer.length < _maxLength) _buffer.write(char);
    }
    return false;
  }
}
