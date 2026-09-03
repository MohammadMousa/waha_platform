import 'package:cached_network_image/cached_network_image.dart';
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
    final scheme    = Theme.of(context).colorScheme;
    final br        = borderRadius ?? BorderRadius.zero;
    final iconSize  = (w * 0.38).clamp(18.0, 40.0);
    final spinnerSz = (w * 0.46).clamp(22.0, 52.0);

    Widget background = Container(
      width: w, height: h,
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

    Widget loadingWidget = Stack(
      alignment: Alignment.center,
      children: [
        background,
        SizedBox(
          width: spinnerSz, height: spinnerSz,
          child: CircularProgressIndicator(strokeWidth: 3, color: scheme.primary),
        ),
        SizedBox(
          width: spinnerSz * 0.58, height: spinnerSz * 0.58,
          child: CircularProgressIndicator(strokeWidth: 2, color: scheme.secondary),
        ),
      ],
    );

    final url = '${AppConfig.apiBaseUrl}/api/resources/$imageResourceId';

    return SizedBox(
      width: w, height: h,
      child: ClipRRect(
        borderRadius: br,
        child: CachedNetworkImage(
          imageUrl: url,
          width: w, height: h,
          fit: fit,
          // Disk + memory cache — survives app restarts
          placeholder: (_, __) => loadingWidget,
          errorWidget: (_, __, ___) => placeholder,
        ),
      ),
    );
  }
}
