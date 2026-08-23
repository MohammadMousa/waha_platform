import 'package:flutter/material.dart';

import '../config/app_config.dart';

/// Displays a product image from `GET /api/images/{id}`.
/// Shows a placeholder icon when id is null or the request fails.
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
    final scheme = Theme.of(context).colorScheme;
    final placeholder = Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.3),
        borderRadius: borderRadius,
      ),
      child: Icon(
        Icons.image_outlined,
        size: (height ?? 80) * 0.5,
        color: scheme.primary.withValues(alpha: 0.35),
      ),
    );

    if (imageResourceId == null) return placeholder;

    final url = '${AppConfig.apiBaseUrl}/api/images/$imageResourceId';
    Widget img = Image.network(
      url,
      width: width,
      height: height,
      fit: fit,
      errorBuilder: (_, __, ___) => placeholder,
      loadingBuilder: (_, child, progress) {
        if (progress == null) return child;
        return Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: borderRadius,
          ),
          child: const Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        );
      },
    );

    if (borderRadius != null) {
      img = ClipRRect(borderRadius: borderRadius!, child: img);
    }
    return img;
  }
}
