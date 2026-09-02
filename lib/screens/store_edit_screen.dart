import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/store.dart';
import '../services/api_client.dart';
import '../state/auth_service.dart';
import '../widgets/product_image.dart';
import '../widgets/resource_picker_sheet.dart';

/// Unified create / edit screen for stores.
/// Pass [store] = null to open in create mode.
class StoreEditScreen extends StatefulWidget {
  final Store? store;
  const StoreEditScreen({super.key, required this.store});

  @override
  State<StoreEditScreen> createState() => _StoreEditScreenState();
}

class _StoreEditScreenState extends State<StoreEditScreen> {
  bool get _isCreate => widget.store == null;

  late final TextEditingController _nameArCtrl;
  late final TextEditingController _nameEnCtrl;
  late final TextEditingController _slugCtrl;
  late final TextEditingController _currencyCtrl;

  int? _imageResourceId;

  bool _active = true;
  bool _isPublic = true;

  // Create mode: parent store picker
  List<Store> _parentStores = [];
  int? _parentStoreId;   // null → backend picks admin root

  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final s = widget.store;
    _nameArCtrl  = TextEditingController(text: s?.displayName?['ar'] ?? '');
    _nameEnCtrl  = TextEditingController(text: s?.displayName?['en'] ?? '');
    _slugCtrl    = TextEditingController(text: s?.name ?? '');
    _currencyCtrl = TextEditingController(text: s?.currency ?? '');
    _imageResourceId = s?.imageResourceId;
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _nameArCtrl.dispose();
    _nameEnCtrl.dispose();
    _slugCtrl.dispose();
    _currencyCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final token = authService.token;
    if (token == null) { setState(() => _loading = false); return; }
    final api = context.read<ApiClient>();

    try {
      if (_isCreate) {
        // Load admin stores so the user can pick a parent.
        final stores = await api.getAdminStores(token);
        if (mounted) setState(() { _parentStores = stores; _loading = false; });
      } else {
        // Load full detail: active/public flags + current imageResourceId.
        final details = await api.getStoreAdminDetails(widget.store!.id, token: token);
        if (mounted && details != null) {
          setState(() {
            _slugCtrl.text    = details['name'] as String? ?? _slugCtrl.text;
            _currencyCtrl.text = details['currency'] as String? ?? _currencyCtrl.text;
            _active   = details['active'] as bool? ?? true;
            _isPublic = details['publicFlag'] as bool? ?? true;
            final imgId = details['imageResourceId'];
            if (imgId != null) _imageResourceId = imgId as int;
            _loading = false;
          });
        } else if (mounted) {
          setState(() => _loading = false);
        }
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickImage() async {
    final result = await showResourcePickerSheet(context);
    if (result == null || !mounted) return;
    setState(() => _imageResourceId = result.resourceId);
  }

  Future<void> _save() async {
    final token = authService.token;
    if (token == null) return;
    final slug = _slugCtrl.text.trim();
    if (slug.isEmpty) {
      setState(() => _error = 'Slug is required.');
      return;
    }
    setState(() { _saving = true; _error = null; });
    final api = context.read<ApiClient>();
    try {
      if (_isCreate) {
        // POST to create the store, then PATCH for image if one was picked.
        final body = <String, dynamic>{
          'name': slug,
          'displayName': {'ar': _nameArCtrl.text.trim(), 'en': _nameEnCtrl.text.trim()},
          if (_currencyCtrl.text.trim().isNotEmpty)
            'currency': _currencyCtrl.text.trim().toUpperCase(),
          if (_parentStoreId != null) 'parentStoreId': _parentStoreId,
        };
        final newId = await api.createStore(body, token: token);
        // Patch active/public/image now that we have an id.
        final patchBody = <String, dynamic>{
          'active': _active,
          'public': _isPublic,
          if (_imageResourceId != null) 'imageResourceId': _imageResourceId,
        };
        await api.patchStore(newId, patchBody, token: token);
      } else {
        final body = <String, dynamic>{
          'displayName': {'ar': _nameArCtrl.text.trim(), 'en': _nameEnCtrl.text.trim()},
          'active': _active,
          'public': _isPublic,
          if (_imageResourceId != null) 'imageResourceId': _imageResourceId,
        };
        if (slug.isNotEmpty) body['name'] = slug;
        final currency = _currencyCtrl.text.trim();
        if (currency.isNotEmpty) body['currency'] = currency.toUpperCase();
        await api.patchStore(widget.store!.id, body, token: token);
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
        title: Text(_isCreate ? 'New Store' : 'Edit Store'),
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
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                // ── Avatar ───────────────────────────────────────────────
                Center(
                  child: GestureDetector(
                    onTap: _pickImage,
                    child: Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(52),
                          child: _imageResourceId != null
                              ? ProductImage(
                                  imageResourceId: _imageResourceId,
                                  width: 104,
                                  height: 104,
                                )
                              : Container(
                                  width: 104,
                                  height: 104,
                                  color: scheme.surfaceContainerHighest,
                                  child: Icon(Icons.storefront_outlined,
                                      size: 40, color: scheme.onSurfaceVariant),
                                ),
                        ),
                        Positioned(
                          bottom: 0, right: 0,
                          child: CircleAvatar(
                            radius: 16,
                            backgroundColor: scheme.primary,
                            child: Icon(Icons.edit, size: 16, color: scheme.onPrimary),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 28),

                // ── Display name ─────────────────────────────────────────
                Text('Display Name', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                TextField(
                  controller: _nameArCtrl,
                  textDirection: TextDirection.rtl,
                  decoration: const InputDecoration(
                    labelText: 'Arabic (عربي)', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _nameEnCtrl,
                  decoration: const InputDecoration(
                    labelText: 'English', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 20),

                // ── Slug ─────────────────────────────────────────────────
                Text('Store Identifier (slug)',
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(
                  _isCreate
                      ? 'URL-safe name, letters/digits/hyphens only.'
                      : 'Changing this may break integrations.',
                  style: TextStyle(color: scheme.outline, fontSize: 12),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _slugCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Slug (e.g. main-store)',
                    border: OutlineInputBorder()),
                ),
                const SizedBox(height: 20),

                // ── Currency ─────────────────────────────────────────────
                Text('Currency', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                TextField(
                  controller: _currencyCtrl,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'ISO code (e.g. SAR, USD)',
                    border: OutlineInputBorder()),
                ),
                const SizedBox(height: 20),

                // ── Parent store (create only) ────────────────────────────
                if (_isCreate && _parentStores.isNotEmpty) ...[
                  Text('Parent Store', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Text(
                    'Leave blank to create under your root store.',
                    style: TextStyle(color: scheme.outline, fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<int?>(
                    value: _parentStoreId,
                    decoration: const InputDecoration(border: OutlineInputBorder()),
                    items: [
                      const DropdownMenuItem<int?>(
                          value: null, child: Text('— Default (admin root) —')),
                      ..._parentStores.map((s) => DropdownMenuItem<int?>(
                            value: s.id,
                            child: Text(s.label('en'),
                                overflow: TextOverflow.ellipsis),
                          )),
                    ],
                    onChanged: (v) => setState(() => _parentStoreId = v),
                  ),
                  const SizedBox(height: 20),
                ],

                // ── Visibility ───────────────────────────────────────────
                Text('Visibility', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 4),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Active'),
                  subtitle:
                      const Text('Inactive stores are hidden from all queries'),
                  value: _active,
                  onChanged: (v) => setState(() => _active = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Public'),
                  subtitle: const Text(
                      'Public stores appear in the customer store picker'),
                  value: _isPublic,
                  onChanged: (v) => setState(() => _isPublic = v),
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
