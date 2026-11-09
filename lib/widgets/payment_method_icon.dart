import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../data/resources/resource_cache.dart';
import '../data/resources/resource_cache_holder.dart';

/// A payment method's icon. When the method has a picture ([resourceId]) it is
/// shown from the resource cache (saved on the device the first time, from the
/// file after that, also offline). In every other case (no picture, still
/// loading, nothing saved and no server) the fixed local [fallback] icon shows,
/// so the payment screen never has an empty tile.
class PaymentMethodIcon extends StatefulWidget {
  final int? resourceId;
  final IconData fallback;
  final Color color;
  final double size;

  const PaymentMethodIcon({
    super.key,
    required this.resourceId,
    required this.fallback,
    required this.color,
    this.size = 28,
  });

  @override
  State<PaymentMethodIcon> createState() => _PaymentMethodIconState();
}

class _PaymentMethodIconState extends State<PaymentMethodIcon> {
  Future<SavedResource?>? _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(PaymentMethodIcon old) {
    super.didUpdateWidget(old);
    if (old.resourceId != widget.resourceId) _load();
  }

  void _load() {
    final id = widget.resourceId;
    final cache = ResourceCacheHolder.instance;
    _future = (id == null || cache == null || kIsWeb)
        ? null
        : cache.get('/api/resources/$id');
  }

  @override
  Widget build(BuildContext context) {
    final fallback = Icon(widget.fallback, color: widget.color, size: widget.size);
    final id = widget.resourceId;
    if (id == null) return fallback;
    if (kIsWeb) {
      return Image.network(
        '${AppConfig.apiBaseUrl}/api/resources/$id',
        width: widget.size,
        height: widget.size,
        fit: BoxFit.contain,
        loadingBuilder: (_, child, p) => p == null ? child : fallback,
        errorBuilder: (_, __, ___) => fallback,
      );
    }
    final future = _future;
    if (future == null) return fallback;
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0;
    return FutureBuilder<SavedResource?>(
      future: future,
      builder: (_, snap) {
        final saved = snap.data;
        if (snap.connectionState != ConnectionState.done || saved == null) {
          return fallback;
        }
        return Image.file(
          saved.file,
          width: widget.size,
          height: widget.size,
          fit: BoxFit.contain,
          cacheWidth: (widget.size * dpr).round(),
          errorBuilder: (_, __, ___) => fallback,
        );
      },
    );
  }
}
