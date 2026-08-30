import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_config.dart';
import '../models/store.dart';
import '../services/api_client.dart';
import '../state/auth_service.dart';
import '../widgets/resource_picker_sheet.dart';

class StoreEditScreen extends StatefulWidget {
  final Store store;
  const StoreEditScreen({super.key, required this.store});

  @override
  State<StoreEditScreen> createState() => _StoreEditScreenState();
}

class _StoreEditScreenState extends State<StoreEditScreen> {
  // display name
  late final TextEditingController _nameArCtrl;
  late final TextEditingController _nameEnCtrl;
  // slug / internal name
  late final TextEditingController _slugCtrl;
  // currency
  late final TextEditingController _currencyCtrl;
  // image
  int? _imageResourceId;
  String? _imageUrl;
  // flags
  bool _active = true;
  bool _isPublic = true;
  // state
  bool _loadingDetails = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final s = widget.store;
    _nameArCtrl = TextEditingController(text: s.displayName?['ar'] ?? '');
    _nameEnCtrl = TextEditingController(text: s.displayName?['en'] ?? '');
    _slugCtrl = TextEditingController(text: s.name);
    _currencyCtrl = TextEditingController(text: s.currency ?? '');
    _imageResourceId = s.imageResourceId;
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadDetails());
  }

  @override
  void dispose() {
    _nameArCtrl.dispose();
    _nameEnCtrl.dispose();
    _slugCtrl.dispose();
    _currencyCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadDetails() async {
    final token = authService.token;
    if (token == null) { setState(() => _loadingDetails = false); return; }
    try {
      final details = await context
          .read<ApiClient>()
          .getStoreAdminDetails(widget.store.id, token: token);
      if (mounted && details != null) {
        setState(() {
          // Only overwrite slug/currency/flags from the server — display name
          // and image were already set from the Store object passed in.
          _slugCtrl.text = details['name'] as String? ?? _slugCtrl.text;
          _currencyCtrl.text = details['currency'] as String? ?? _currencyCtrl.text;
          _active = details['active'] as bool? ?? true;
          _isPublic = details['publicFlag'] as bool? ?? true;
          _loadingDetails = false;
        });
      } else if (mounted) {
        setState(() => _loadingDetails = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loadingDetails = false);
    }
  }

  Future<void> _pickImage() async {
    final result = await showResourcePickerSheet(context);
    if (result == null || !mounted) return;
    setState(() {
      _imageResourceId = result.resourceId;
      _imageUrl = result.publicUrl;
    });
  }

  Future<void> _save() async {
    final token = authService.token;
    if (token == null) return;
    setState(() { _saving = true; _error = null; });
    try {
      final body = <String, dynamic>{
        'displayName': {'ar': _nameArCtrl.text.trim(), 'en': _nameEnCtrl.text.trim()},
        if (_imageResourceId != null) 'imageResourceId': _imageResourceId,
        'active': _active,
        'public': _isPublic,
      };
      final slug = _slugCtrl.text.trim();
      if (slug.isNotEmpty) body['name'] = slug;
      final currency = _currencyCtrl.text.trim();
      if (currency.isNotEmpty) body['currency'] = currency;

      await context.read<ApiClient>().patchStore(widget.store.id, body, token: token);
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
        title: const Text('Edit Store'),
        actions: [
          if (!_loadingDetails)
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
      body: _loadingDetails
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                // Store image avatar
                Center(
                  child: GestureDetector(
                    onTap: _pickImage,
                    child: Stack(
                      children: [
                        CircleAvatar(
                          radius: 52,
                          backgroundColor: scheme.surfaceContainerHighest,
                          backgroundImage: _imageUrl != null
                              ? NetworkImage('${AppConfig.apiBaseUrl}$_imageUrl')
                              : null,
                          child: _imageUrl == null
                              ? Icon(Icons.storefront_outlined,
                                  size: 40, color: scheme.onSurfaceVariant)
                              : null,
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

                // Display name
                Text('Display Name', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                TextField(
                  controller: _nameArCtrl,
                  textDirection: TextDirection.rtl,
                  decoration: const InputDecoration(
                    labelText: 'Arabic (عربي)',
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

                // Slug / internal name
                Text('Store Identifier (slug)', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(
                  'URL-safe name used in API paths. Changing this may break integrations.',
                  style: TextStyle(color: scheme.outline, fontSize: 12),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _slugCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Slug (e.g. main-store)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 20),

                // Currency
                Text('Currency', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                TextField(
                  controller: _currencyCtrl,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'ISO code (e.g. SAR, USD)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 20),

                // Flags
                Text('Visibility', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 4),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Active'),
                  subtitle: const Text('Inactive stores are hidden from all queries'),
                  value: _active,
                  onChanged: (v) => setState(() => _active = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Public'),
                  subtitle: const Text('Public stores appear in the customer store picker'),
                  value: _isPublic,
                  onChanged: (v) => setState(() => _isPublic = v),
                ),

                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
                ],
                const SizedBox(height: 32),
              ],
            ),
    );
  }
}
