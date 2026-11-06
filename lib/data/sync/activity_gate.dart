import 'dart:async';

/// Tells the background sync when a customer is present. The idle guard calls
/// [touch] on every tap, scan or key press. The pull engine waits for
/// [idleFor] to pass before starting and cancels a request in flight as soon
/// as [touch] fires. Pushing orders (later) ignores this on purpose.
class ActivityGate {
  ActivityGate._();
  static final ActivityGate instance = ActivityGate._();

  DateTime _last = DateTime.now();
  final _controller = StreamController<void>.broadcast();

  /// Fires on every touch.
  Stream<void> get onActivity => _controller.stream;

  void touch() {
    _last = DateTime.now();
    _controller.add(null);
  }

  Duration get idleFor => DateTime.now().difference(_last);
}
