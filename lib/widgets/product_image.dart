import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../data/resources/resource_cache.dart';
import '../data/resources/resource_cache_holder.dart';

/// A product's picture. Lazy: nothing is downloaded until a screen shows it.
/// It comes from the resource cache (saved on the device the first time, shown
/// from the file after that, also when the server cannot be reached). A
/// replaced image has a NEW resource id, so a saved one never goes stale.
/// While it loads there is a spinner; with nothing saved and no server there
/// is the placeholder.
class ProductImage extends StatefulWidget {
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
  State<ProductImage> createState() => _ProductImageState();
}

class _ProductImageState extends State<ProductImage> {
  Future<SavedResource?>? _future;

  int? get imageResourceId => widget.imageResourceId;
  double? get width => widget.width;
  double? get height => widget.height;
  BoxFit get fit => widget.fit;
  BorderRadius? get borderRadius => widget.borderRadius;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(ProductImage old) {
    super.didUpdateWidget(old);
    if (old.imageResourceId != widget.imageResourceId) _load();
  }

  void _load() {
    final id = widget.imageResourceId;
    final cache = ResourceCacheHolder.instance;
    _future = (id == null || cache == null)
        ? null
        : cache.get('/api/resources/$id');
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // "Fill" (double.infinity) means the space the layout gives, which is
        // a real number; an infinite size cannot be used to size the decode.
        double pick(double? asked, bool bounded, double max) =>
            (asked != null && asked.isFinite)
                ? asked
                : (bounded ? max : 80.0);
        final w = pick(width, constraints.hasBoundedWidth, constraints.maxWidth);
        final h = pick(height, constraints.hasBoundedHeight, constraints.maxHeight);
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

    // The web build has no disk: it loads the picture from the network.
    if (kIsWeb) {
      return SizedBox(
        width: w, height: h,
        child: ClipRRect(
          borderRadius: br,
          child: Image.network(
            '${AppConfig.apiBaseUrl}/api/resources/$imageResourceId',
            width: w, height: h, fit: fit,
            loadingBuilder: (_, child, p) => p == null ? child : loadingWidget,
            errorBuilder: (_, __, ___) => placeholder,
          ),
        ),
      );
    }

    final future = _future;
    if (future == null) return SizedBox(width: w, height: h, child: placeholder);
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0;
    return SizedBox(
      width: w, height: h,
      child: ClipRRect(
        borderRadius: br,
        child: FutureBuilder<SavedResource?>(
          future: future,
          builder: (_, snap) {
            if (snap.connectionState != ConnectionState.done) return loadingWidget;
            final saved = snap.data;
            if (saved == null) return placeholder;
            return Image.file(
              saved.file,
              width: w, height: h, fit: fit,
              // Decode at the size it is shown, not the file's full size.
              cacheWidth: (w * dpr).round(),
              errorBuilder: (_, __, ___) => placeholder,
            );
          },
        ),
      ),
    );
  }
}
