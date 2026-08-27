import 'package:flutter/material.dart';

/// Ninja-style quantity stepper.
///
/// Collapsed (qty == 0): single teal circle with a + icon.
/// Expanded (qty > 0): white pill — [−|count|+] — where the minus button
/// turns red with a trash icon when qty == 1 (next tap removes the item).
///
/// Use [size] to control the height of the pill / diameter of the collapsed
/// circle (default 32). Set [fullWidth] for the product-detail full-row style.
class QuantityStepper extends StatelessWidget {
  final int qty;
  final VoidCallback? onAdd;
  final VoidCallback? onRemove;
  final bool active;
  final double size;
  final bool fullWidth;

  const QuantityStepper({
    super.key,
    required this.qty,
    required this.onAdd,
    required this.onRemove,
    this.active = true,
    this.size = 32,
    this.fullWidth = false,
  });

  @override
  Widget build(BuildContext context) {
    final teal = Theme.of(context).colorScheme.primary;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      transitionBuilder: (child, anim) =>
          ScaleTransition(scale: anim, child: child),
      child: qty > 0
          ? (fullWidth ? _expandedFull(context, teal) : _expanded(teal))
          : _collapsed(teal),
    );
  }

  // ── Collapsed: single teal + circle ──────────────────────────────────────

  Widget _collapsed(Color teal) {
    return GestureDetector(
      key: const ValueKey('collapsed'),
      onTap: active ? onAdd : null,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: active ? teal : Colors.grey[300],
          shape: BoxShape.circle,
          boxShadow: const [
            BoxShadow(color: Color(0x22000000), blurRadius: 6, offset: Offset(0, 2)),
          ],
        ),
        child: Icon(Icons.add, size: size * 0.55, color: Colors.white),
      ),
    );
  }

  // ── Expanded compact: pill overlay on product card ────────────────────────

  Widget _expanded(Color teal) {
    final bool last = qty == 1;
    return Container(
      key: const ValueKey('expanded'),
      height: size,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(size / 2),
        boxShadow: const [
          BoxShadow(color: Color(0x22000000), blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      // Pinned LTR: a stepper is a numeric control, not reading-order
      // content — minus stays on the left and plus on the right regardless
      // of the app's locale/text direction (Arabic included).
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _circleBtn(
              icon: last ? Icons.delete_outline : Icons.remove,
              color: last ? const Color(0xFFE53935) : const Color(0xFFEEEEEE),
              iconColor: last ? Colors.white : Colors.grey[700]!,
              onTap: onRemove,
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: size * 0.28),
              child: Text(
                '$qty',
                style: TextStyle(
                  fontSize: size * 0.44,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[800],
                ),
              ),
            ),
            _circleBtn(
              icon: Icons.add,
              color: active ? teal : Colors.grey[300]!,
              iconColor: Colors.white,
              onTap: active ? onAdd : null,
            ),
          ],
        ),
      ),
    );
  }

  // ── Expanded full-width: for product-detail bottom bar ────────────────────

  Widget _expandedFull(BuildContext context, Color teal) {
    final bool last = qty == 1;
    return Container(
      key: const ValueKey('expandedFull'),
      height: size,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(size / 2),
        boxShadow: const [
          BoxShadow(color: Color(0x22000000), blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      // Pinned LTR — see _expanded for why.
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Row(
          children: [
            _circleBtn(
              icon: last ? Icons.delete_outline : Icons.remove,
              color: last ? const Color(0xFFE53935) : const Color(0xFFEEEEEE),
              iconColor: last ? Colors.white : Colors.grey[700]!,
              onTap: onRemove,
            ),
            Expanded(
              child: Text(
                '$qty',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: size * 0.42,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[800],
                ),
              ),
            ),
            _circleBtn(
              icon: Icons.add,
              color: active ? teal : Colors.grey[300]!,
              iconColor: Colors.white,
              onTap: active ? onAdd : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _circleBtn({
    required IconData icon,
    required Color color,
    required Color iconColor,
    required VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        child: Icon(icon, size: size * 0.5, color: iconColor),
      ),
    );
  }
}
