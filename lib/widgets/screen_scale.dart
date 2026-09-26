import 'package:flutter/widgets.dart';

import '../config/screen_factor.dart';

/// Lays the whole app out on a smaller virtual screen and paints it enlarged,
/// so a big kiosk display shows the same-sized controls as a phone. Sits above
/// the Navigator (dialogs, overlays and touch all follow the scale). Does
/// nothing at a factor of 1.
class ScreenScale extends StatelessWidget {
  final Widget child;
  const ScreenScale({required this.child, super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: screenFactor,
      builder: (context, _) {
        final mq = MediaQuery.of(context);
        final s = screenFactor.scaleFor(mq.size);
        if ((s - 1.0).abs() < 0.01) return child;
        final virtual = Size(mq.size.width / s, mq.size.height / s);
        // OverflowBox lets the virtual screen be LARGER than the real one
        // (factor below 1) instead of being squeezed back to it; touch still
        // maps through the transform.
        return OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: 0,
          maxWidth: double.infinity,
          minHeight: 0,
          maxHeight: double.infinity,
          child: Transform.scale(
            scale: s,
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: virtual.width,
              height: virtual.height,
              child: MediaQuery(
                data: mq.copyWith(
                  size: virtual,
                  padding: mq.padding / s,
                  viewPadding: mq.viewPadding / s,
                  viewInsets: mq.viewInsets / s,
                  systemGestureInsets: mq.systemGestureInsets / s,
                ),
                child: child,
              ),
            ),
          ),
        );
      },
    );
  }
}
