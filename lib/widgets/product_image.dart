import 'package:flutter/material.dart';

import '../config/app_config.dart';

class ProductImage extends StatelessWidget {
  final int? imageResourceId;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;

  const ProductImage({
    super.key,
    required this.imageResourceId,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = width  ?? (constraints.hasBoundedWidth  ? constraints.maxWidth  : 80.0);
        final h = height ?? (constraints.hasBoundedHeight ? constraints.maxHeight : 80.0);
        return _build(context, w, h);
      },
    );
  }

  Widget _build(BuildContext context, double w, double h) {
    final scheme     = Theme.of(context).colorScheme;
    final br         = borderRadius ?? BorderRadius.zero;
    final iconSize   = (w * 0.38).clamp(18.0, 40.0);
    final spinnerOut = (w * 0.46).clamp(22.0, 52.0);
    final spinnerIn  = spinnerOut * 0.58;

    // Tinted background shared by placeholder and loading states.
    Widget background = Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.3),
        borderRadius: br,
      ),
    );

    Widget placeholder = Stack(
      alignment: Alignment.center,
      children: [
        background,
        Icon(Icons.image_outlined, size: iconSize,
            color: scheme.primary.withValues(alpha: 0.35)),
      ],
    );

    if (imageResourceId == null) {
      return SizedBox(width: w, height: h, child: placeholder);
    }

    // Two concentric spinning rings — outer: primary, inner: secondary.
    Widget spinner = Stack(
      alignment: Alignment.center,
      children: [
        background,
        SizedBox(
          width: spinnerOut,
          height: spinnerOut,
          child: CircularProgressIndicator(
            strokeWidth: 3,
            color: scheme.primary,
          ),
        ),
        SizedBox(
          width: spinnerIn,
          height: spinnerIn,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: scheme.secondary,
          ),
        ),
      ],
    );

    final url = '${AppConfig.apiBaseUrl}/api/resources/$imageResourceId';

    // Stack the spinner below the image. The image renders opaque once loaded,
    // covering the spinner — no loadingBuilder constraint issues in Flutter web.
    Widget result = SizedBox(
      width: w,
      height: h,
      child: ClipRRect(
        borderRadius: br,
        child: Stack(
          fit: StackFit.expand,
          children: [
            spinner,
            Image.network(
              url,
              width: w,
              height: h,
              fit: fit,
              errorBuilder: (_, __, ___) => placeholder,
            ),
          ],
        ),
      ),
    );

    return result;
  }
}
