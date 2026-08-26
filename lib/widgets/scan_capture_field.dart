import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/api_exceptions.dart';
import '../services/scan_sound_service.dart';
import '../state/order_flow_controller.dart';

/// Captures barcode input from a hardware scanner acting as a keyboard
/// (types digits, then Enter). One mechanism, two presentations:
///
/// `visible: true` — a labeled field with inline error notices. Used by
/// ScanScreen (Normal mode's explicit "Scan" entry, also useful for
/// manual entry/testing).
///
/// `visible: false` — collapses to an effectively invisible 1x1 capture
/// point, always focused, no visible chrome, errors reported via
/// SnackBar instead of an inline banner. Used by LandingScreen in Kiosk
/// mode: a real kiosk has a hardware scanner but showing a text box on
/// the home screen would look like a bug, not a feature — the customer
/// should never need to know this field exists.
class ScanCaptureField extends StatefulWidget {
  final bool visible;
  const ScanCaptureField({super.key, this.visible = true});

  @override
  State<ScanCaptureField> createState() => _ScanCaptureFieldState();
}

class _ScanCaptureFieldState extends State<ScanCaptureField> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  String? _notFoundMessage;
  String? _notSellableMessage;

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _submit(String barcode) async {
    if (barcode.trim().isEmpty) return;
    setState(() {
      _notFoundMessage = null;
      _notSellableMessage = null;
    });
    final flow = context.read<OrderFlowController>();
    try {
      await flow.scanBarcode(barcode.trim());
      ScanSoundService.playSuccess();
    } on ProductNotFoundException catch (e) {
      ScanSoundService.playFailure();
      _reportError(e.message, isNotFound: true);
    } on ProductNotSellableException catch (e) {
      ScanSoundService.playFailure();
      _reportError(e.message, isNotFound: false);
    } catch (e) {
      ScanSoundService.playFailure();
      _reportError(e.toString().replaceFirst('Exception: ', ''), isNotFound: false);
    } finally {
      _controller.clear();
      _focusNode.requestFocus();
    }
  }

  void _reportError(String message, {required bool isNotFound}) {
    if (widget.visible) {
      setState(() {
        if (isNotFound) {
          _notFoundMessage = message;
        } else {
          _notSellableMessage = message;
        }
      });
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final field = TextField(
      controller: _controller,
      focusNode: _focusNode,
      autofocus: true,
      // keyboardType.none keeps the hardware-scanner path alive (HID events
      // still land in the TextField) while telling Android not to pop up the
      // soft keyboard. Without this, Android raises the keyboard the moment
      // the invisible field receives focus, causing a 60px overflow on the
      // landing page.
      keyboardType: widget.visible ? null : TextInputType.none,
      decoration: widget.visible
          ? const InputDecoration(
              labelText: 'Scan or enter barcode',
              border: OutlineInputBorder(),
            )
          : const InputDecoration(border: InputBorder.none, isDense: true),
      onSubmitted: _submit,
    );

    if (!widget.visible) {
      // Present in the tree and focused, but not something a customer
      // should ever see or notice.
      return SizedBox(
        width: 1,
        height: 1,
        child: Opacity(opacity: 0, child: field),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        field,
        if (_notFoundMessage != null || _notSellableMessage != null)
          const SizedBox(height: 16),
        if (_notFoundMessage != null)
          _InlineNotice(
            color: Colors.orange,
            icon: Icons.help_outline,
            message: _notFoundMessage!,
          ),
        if (_notSellableMessage != null)
          _InlineNotice(
            color: Colors.red,
            icon: Icons.block,
            message: _notSellableMessage!,
          ),
      ],
    );
  }
}

class _InlineNotice extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String message;

  const _InlineNotice({required this.color, required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(message)),
        ],
      ),
    );
  }
}
