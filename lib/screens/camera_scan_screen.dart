import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../state/order_flow_controller.dart';

/// Pushed by the simulator's camera button. Pops with the scanned barcode
/// string on first successful detection, or null if the user backs out.
/// This is the "real scanner" path — distinct from the cached-value
/// simulator buttons, which skip the camera entirely.
class CameraScanScreen extends StatefulWidget {
  const CameraScanScreen({super.key});

  @override
  State<CameraScanScreen> createState() => _CameraScanScreenState();
}

class _CameraScanScreenState extends State<CameraScanScreen> {
  bool _handled = false;

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    final value = capture.barcodes.isNotEmpty ? capture.barcodes.first.rawValue : null;
    if (value == null || value.isEmpty) return;
    _handled = true;
    Navigator.of(context).pop(value);
  }

  Future<void> _clearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear cart?'),
        content: const Text(
          'This removes every scanned item. Nothing has been placed as an '
          'order yet, so this is safe.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      context.read<OrderFlowController>().clearCart();
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Cart cleared')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Scan with Camera'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: 'Clear All',
            onPressed: _clearAll,
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(onDetect: _onDetect),
          // Purely visual — a dimmed mask with a cut-out square and corner
          // brackets so the customer knows where to aim. Doesn't affect
          // detection at all; mobile_scanner scans the full camera frame
          // regardless of what's drawn on top.
          IgnorePointer(
            child: CustomPaint(
              painter: _ScanFramePainter(),
              child: const SizedBox.expand(),
            ),
          ),
          const Positioned(
            left: 0,
            right: 0,
            bottom: 48,
            child: Text(
              'Align the barcode within the frame',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScanFramePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cutoutSize = size.shortestSide * 0.62;
    final cutoutRect = Rect.fromCenter(
      center: size.center(Offset.zero),
      width: cutoutSize,
      height: cutoutSize,
    );
    final cutoutRRect = RRect.fromRectAndRadius(cutoutRect, const Radius.circular(20));

    final maskPath = Path.combine(
      PathOperation.difference,
      Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height)),
      Path()..addRRect(cutoutRRect),
    );
    canvas.drawPath(maskPath, Paint()..color = Colors.black.withOpacity(0.55));

    canvas.drawRRect(
      cutoutRRect,
      Paint()
        ..color = Colors.white.withOpacity(0.9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    const bracketLen = 26.0;
    final bracketPaint = Paint()
      ..color = Colors.greenAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;

    final r = cutoutRect;
    canvas.drawLine(r.topLeft, r.topLeft.translate(bracketLen, 0), bracketPaint);
    canvas.drawLine(r.topLeft, r.topLeft.translate(0, bracketLen), bracketPaint);
    canvas.drawLine(r.topRight, r.topRight.translate(-bracketLen, 0), bracketPaint);
    canvas.drawLine(r.topRight, r.topRight.translate(0, bracketLen), bracketPaint);
    canvas.drawLine(r.bottomLeft, r.bottomLeft.translate(bracketLen, 0), bracketPaint);
    canvas.drawLine(r.bottomLeft, r.bottomLeft.translate(0, -bracketLen), bracketPaint);
    canvas.drawLine(r.bottomRight, r.bottomRight.translate(-bracketLen, 0), bracketPaint);
    canvas.drawLine(r.bottomRight, r.bottomRight.translate(0, -bracketLen), bracketPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
