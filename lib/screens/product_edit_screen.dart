import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_config.dart';
import '../services/api_client.dart';
import '../state/auth_service.dart';
import '../widgets/product_image.dart';
import '../widgets/resource_picker_sheet.dart';

class ProductEditScreen extends StatefulWidget {
  final int productId;
  const ProductEditScreen({super.key, required this.productId});

  @override
  State<ProductEditScreen> createState() => _ProductEditScreenState();
}

class _ProductEditScreenState extends State<ProductEditScreen> {
  bool _loading = true;
  bool _saving = false;
  String? _error;

  final _nameArCtrl = TextEditingController();
  final _nameEnCtrl = TextEditingController();
  final _descArCtrl = TextEditingController();
  final _descEnCtrl = TextEditingController();
  final _tagInputCtrl = TextEditingController();
  int? _imageResourceId;
  bool _removeAvatar = false;
  List<int> _galleryIds = [];
  List<String> _tags = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameArCtrl.dispose();
    _nameEnCtrl.dispose();
    _descArCtrl.dispose();
    _descEnCtrl.dispose();
    _tagInputCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final product = await context.read<ApiClient>().getProductDetail(widget.productId);
      if (!mounted) return;
      setState(() {
        _nameArCtrl.text = product.name['ar'] as String? ?? '';
        _nameEnCtrl.text = product.name['en'] as String? ?? '';
        _descArCtrl.text = (product.description?['ar'] as String?) ?? '';
        _descEnCtrl.text = (product.description?['en'] as String?) ?? '';
        _imageResourceId = product.imageResourceId;
        _galleryIds = List<int>.from(product.imageResourceIds);
        _tags = List<String>.from(product.tags);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _pickAvatar() async {
    final result = await showResourcePickerSheet(context);
    if (result == null || !mounted) return;
    setState(() {
      _imageResourceId = result.resourceId;
      _removeAvatar = false;
    });
  }

  Future<void> _addGalleryImage() async {
    final result = await showResourcePickerSheet(context);
    if (result == null || !mounted) return;
    setState(() => _galleryIds.add(result.resourceId));
  }

  void _addTag() {
    final tag = _tagInputCtrl.text.trim();
    if (tag.isEmpty || _tags.contains(tag)) return;
    setState(() {
      _tags.add(tag);
      _tagInputCtrl.clear();
    });
  }

  Future<void> _save() async {
    final token = authService.token;
    if (token == null) return;
    setState(() { _saving = true; _error = null; });
    final api = context.read<ApiClient>();
    try {
      // Save core fields
      await api.patchProduct(
        widget.productId,
        {
          'name': {'ar': _nameArCtrl.text.trim(), 'en': _nameEnCtrl.text.trim()},
          'description': {'ar': _descArCtrl.text.trim(), 'en': _descEnCtrl.text.trim()},
          if (_removeAvatar) 'imageResourceId': null
          else if (_imageResourceId != null) 'imageResourceId': _imageResourceId,
          'tags': _tags,
        },
        token: token,
      );
      // Sync gallery: fetch current server list, add/remove as needed
      if (!mounted) return;
      final fresh = await api.getProductDetail(widget.productId);
      if (!mounted) return;
      final serverIds = fresh.imageResourceIds.toSet();
      final localIds  = _galleryIds.toSet();
      for (final id in localIds.difference(serverIds)) {
        await api.addProductGalleryImage(widget.productId, id, token: token);
      }
      for (final id in serverIds.difference(localIds)) {
        await api.removeProductGalleryImage(widget.productId, id, token: token);
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _saving = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Product'),
        actions: [
          if (!_loading)
            TextButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Save'),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _loading == false && _nameArCtrl.text.isEmpty
              ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
              : ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    // Avatar
                    Center(
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          GestureDetector(
                            onTap: _pickAvatar,
                            child: CircleAvatar(
                              radius: 52,
                              backgroundColor: scheme.surfaceContainerHighest,
                              child: ClipOval(
                                child: (_imageResourceId != null && !_removeAvatar)
                                    ? ProductImage(
                                        imageResourceId: _imageResourceId,
                                        width: 104,
                                        height: 104,
                                      )
                                    : Icon(Icons.add_a_photo_outlined,
                                        size: 36, color: scheme.onSurfaceVariant),
                              ),
                            ),
                          ),
                          Positioned(
                            bottom: 0, right: 0,
                            child: GestureDetector(
                              onTap: _pickAvatar,
                              child: CircleAvatar(
                                radius: 16,
                                backgroundColor: scheme.primary,
                                child: Icon(Icons.edit, size: 16, color: scheme.onPrimary),
                              ),
                            ),
                          ),
                          if (_imageResourceId != null && !_removeAvatar)
                            Positioned(
                              top: -4, right: -4,
                              child: GestureDetector(
                                onTap: () => setState(() => _removeAvatar = true),
                                child: CircleAvatar(
                                  radius: 12,
                                  backgroundColor: scheme.error,
                                  child: Icon(Icons.close, size: 14, color: scheme.onError),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),

                    // Gallery images
                    if (_galleryIds.isNotEmpty || true) ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Gallery', style: Theme.of(context).textTheme.titleSmall),
                          TextButton.icon(
                            onPressed: _addGalleryImage,
                            icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
                            label: const Text('Add'),
                          ),
                        ],
                      ),
                      if (_galleryIds.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text('No gallery images yet',
                              style: TextStyle(color: scheme.outline, fontSize: 13)),
                        )
                      else
                        SizedBox(
                          height: 90,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: _galleryIds.length,
                            separatorBuilder: (_, __) => const SizedBox(width: 8),
                            itemBuilder: (_, i) {
                              final rid = _galleryIds[i];
                              return Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: ProductImage(
                                      imageResourceId: rid,
                                      width: 80,
                                      height: 80,
                                    ),
                                  ),
                                  Positioned(
                                    top: -6, right: -6,
                                    child: GestureDetector(
                                      onTap: () => setState(() => _galleryIds.removeAt(i)),
                                      child: CircleAvatar(
                                        radius: 11,
                                        backgroundColor: scheme.error,
                                        child: Icon(Icons.close, size: 12, color: scheme.onError),
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                      const SizedBox(height: 8),
                    ],

                    // Name
                    Text('Name', style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _nameArCtrl,
                      textDirection: TextDirection.rtl,
                      decoration: const InputDecoration(
                        labelText: 'Arabic',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _nameEnCtrl,
                      decoration: const InputDecoration(
                        labelText: 'English',
                        border: OutlineInputBorder(),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Description
                    Text('Description', style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _descArCtrl,
                      textDirection: TextDirection.rtl,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Arabic',
                        border: OutlineInputBorder(),
                        alignLabelWithHint: true,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _descEnCtrl,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'English',
                        border: OutlineInputBorder(),
                        alignLabelWithHint: true,
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Tags
                    Text('Tags', style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        for (final tag in _tags)
                          Chip(
                            label: Text(tag),
                            onDeleted: () => setState(() => _tags.remove(tag)),
                            deleteIconColor: scheme.onSurface.withAlpha(150),
                            visualDensity: VisualDensity.compact,
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _tagInputCtrl,
                            textCapitalization: TextCapitalization.words,
                            decoration: const InputDecoration(
                              hintText: 'Add a tag…',
                              border: OutlineInputBorder(),
                              isDense: true,
                              contentPadding:
                                  EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            ),
                            onSubmitted: (_) => _addTag(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filled(
                          icon: const Icon(Icons.add),
                          tooltip: 'Add tag',
                          onPressed: _addTag,
                        ),
                      ],
                    ),

                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Text(_error!,
                          style: const TextStyle(color: Colors.red, fontSize: 13)),
                    ],
                    const SizedBox(height: 32),
                  ],
                ),
    );
  }
}
