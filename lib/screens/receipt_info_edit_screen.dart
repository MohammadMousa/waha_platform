import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_config.dart';
import '../services/api_client.dart';
import '../state/auth_service.dart';
import '../state/store_config_service.dart';
import '../widgets/resource_picker_sheet.dart';

class ReceiptInfoEditScreen extends StatefulWidget {
  const ReceiptInfoEditScreen({super.key});

  @override
  State<ReceiptInfoEditScreen> createState() => _ReceiptInfoEditScreenState();
}

class _ReceiptInfoEditScreenState extends State<ReceiptInfoEditScreen> {
  bool _loading = true;
  bool _saving = false;
  String? _error;

  final _nameArCtrl = TextEditingController();
  final _nameEnCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _vatCtrl = TextEditingController();
  final _crCtrl = TextEditingController();
  final _unpaidTitleCtrl = TextEditingController();
  final _paidTitleCtrl = TextEditingController();
  int? _logoResourceId;
  String? _logoUrl;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameArCtrl.dispose();
    _nameEnCtrl.dispose();
    _addressCtrl.dispose();
    _vatCtrl.dispose();
    _crCtrl.dispose();
    _unpaidTitleCtrl.dispose();
    _paidTitleCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final storeId = authService.sessionStoreId ?? storeConfigService.storeId;
    try {
      final info = await context.read<ApiClient>().getReceiptInfo(
            storeId: storeId,
            token: authService.token,
          );
      if (!mounted) return;
      if (info != null) {
        _nameArCtrl.text = info.nameAr ?? '';
        _nameEnCtrl.text = info.nameEn ?? '';
        _addressCtrl.text = info.addressText ?? '';
        _vatCtrl.text = info.vatNumber ?? '';
        _crCtrl.text = info.crNumber ?? '';
        _unpaidTitleCtrl.text = info.unpaidInvoiceTitle ?? '';
        _paidTitleCtrl.text = info.paidInvoiceTitle ?? '';
        _logoResourceId = info.logoResourceId;
      }
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _pickLogo() async {
    final result = await showResourcePickerSheet(context);
    if (result == null || !mounted) return;
    setState(() {
      _logoResourceId = result.resourceId;
      _logoUrl = result.publicUrl;
    });
  }

  Future<void> _save() async {
    final token = authService.token;
    if (token == null) return;
    setState(() { _saving = true; _error = null; });
    try {
      await context.read<ApiClient>().patchReceiptInfo(
        {
          'nameAr': _nameArCtrl.text.trim(),
          'nameEn': _nameEnCtrl.text.trim(),
          'addressText': _addressCtrl.text.trim(),
          'vatNumber': _vatCtrl.text.trim(),
          'crNumber': _crCtrl.text.trim(),
          'unpaidInvoiceTitle': _unpaidTitleCtrl.text.trim(),
          'paidInvoiceTitle': _paidTitleCtrl.text.trim(),
          if (_logoResourceId != null) 'logoResourceId': _logoResourceId,
        },
        token: token,
      );
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
        title: const Text('Edit Receipt Info'),
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
                // Logo
                Center(
                  child: GestureDetector(
                    onTap: _pickLogo,
                    child: Stack(
                      children: [
                        Container(
                          width: 104,
                          height: 104,
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: _logoUrl != null
                              ? Image.network(
                                  '${AppConfig.apiBaseUrl}$_logoUrl',
                                  fit: BoxFit.contain,
                                )
                              : Icon(Icons.store_outlined,
                                  size: 48, color: scheme.onSurfaceVariant),
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

                const _Section(title: 'Store Name'),
                const SizedBox(height: 8),
                _Field(ctrl: _nameArCtrl, label: 'Arabic', rtl: true),
                const SizedBox(height: 10),
                _Field(ctrl: _nameEnCtrl, label: 'English'),

                const SizedBox(height: 20),
                const _Section(title: 'Address'),
                const SizedBox(height: 8),
                _Field(ctrl: _addressCtrl, label: 'Address text', maxLines: 3),

                const SizedBox(height: 20),
                const _Section(title: 'VAT & CR Numbers'),
                const SizedBox(height: 8),
                _Field(ctrl: _vatCtrl, label: 'VAT number'),
                const SizedBox(height: 10),
                _Field(ctrl: _crCtrl, label: 'CR number'),

                const SizedBox(height: 20),
                const _Section(title: 'Invoice Titles'),
                const SizedBox(height: 8),
                _Field(ctrl: _unpaidTitleCtrl, label: 'Unpaid invoice title'),
                const SizedBox(height: 10),
                _Field(ctrl: _paidTitleCtrl, label: 'Paid invoice title'),

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

class _Section extends StatelessWidget {
  final String title;
  const _Section({required this.title});
  @override
  Widget build(BuildContext context) =>
      Text(title, style: Theme.of(context).textTheme.titleSmall);
}

class _Field extends StatelessWidget {
  final TextEditingController ctrl;
  final String label;
  final bool rtl;
  final int maxLines;
  const _Field({required this.ctrl, required this.label, this.rtl = false, this.maxLines = 1});

  @override
  Widget build(BuildContext context) => TextField(
        controller: ctrl,
        textDirection: rtl ? TextDirection.rtl : null,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          alignLabelWithHint: maxLines > 1,
        ),
      );
}
