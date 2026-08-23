import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/category.dart';
import '../router/app_router.dart';
import '../services/api_client.dart';
import '../state/auth_service.dart';
import '../state/store_config_service.dart';
import '../utils/locale_name.dart';
import '../widgets/product_image.dart';
import '../widgets/waha_app_bar.dart';
import '../widgets/waha_bottom_nav.dart';

class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({super.key});

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  List<Category>? _categories;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final storeId = authService.sessionStoreId ?? storeConfigService.storeId;
    if (storeId == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final cats = await context.read<ApiClient>().getCategories(storeId: storeId);
      if (mounted) setState(() => _categories = cats);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final lang = Localizations.localeOf(context).languageCode;

    Widget body;
    if (_loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_error != null) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.wifi_off_outlined,
                  size: 56, color: scheme.outline.withValues(alpha: 0.5)),
              const SizedBox(height: 16),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: _load, child: Text(l10n.browseRetry)),
            ],
          ),
        ),
      );
    } else if (_categories == null || _categories!.isEmpty) {
      body = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.category_outlined,
                size: 72, color: scheme.outline.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            Text(l10n.browseEmpty, style: TextStyle(color: scheme.outline)),
          ],
        ),
      );
    } else {
      body = GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 1.1,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: _categories!.length,
        itemBuilder: (context, i) {
          final cat = _categories![i];
          final name = localeName(cat.name, lang);
          return _CategoryCard(
            name: name,
            imageResourceId: cat.imageResourceId,
            onTap: () => Navigator.of(context).pushNamed(
              Routes.browse,
              arguments: {'categoryId': cat.id, 'title': name},
            ),
          );
        },
      );
    }

    return Scaffold(
      appBar: WahaAppBar(title: l10n.categoriesTitle),
      bottomNavigationBar:
          const WahaBottomNav(current: BottomNavTab.categories),
      body: body,
    );
  }
}

class _CategoryCard extends StatelessWidget {
  final String name;
  final int? imageResourceId;
  final VoidCallback onTap;

  const _CategoryCard({
    required this.name,
    required this.imageResourceId,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Background image
            ProductImage(
              imageResourceId: imageResourceId,
              fit: BoxFit.cover,
            ),
            // Gradient overlay
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.6),
                  ],
                ),
              ),
            ),
            // Category name
            Positioned(
              bottom: 12,
              left: 12,
              right: 12,
              child: Text(
                name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  shadows: [
                    Shadow(blurRadius: 4, color: Colors.black54),
                  ],
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
