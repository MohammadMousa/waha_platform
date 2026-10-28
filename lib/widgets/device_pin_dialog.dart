import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/generated/app_localizations.dart';
import '../services/api_client.dart';
import '../state/auth_service.dart';

// Device PIN gate — the way into Settings (and the `cmd=profile` scan) from Kiosk mode.
// Checked by the backend (POST /api/kiosk/auth/pin/verify, with the device's
// own session token) — the PIN is never stored or compared on the device.
// Pops `true` only once the server says the PIN matches.

class DevicePinDialog extends StatefulWidget {
  const DevicePinDialog();

  @override
  State<DevicePinDialog> createState() => _DevicePinDialogState();
}

class _DevicePinDialogState extends State<DevicePinDialog> {
  final _pinController = TextEditingController();
  String? _error;
  bool _checking = false;

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_checking) return;
    final entered = _pinController.text.trim();
    final token = authService.token;
    if (token == null) {
      setState(() => _error = 'Not signed in — restart the app and sign in again');
      return;
    }
    setState(() {
      _checking = true;
      _error = null;
    });
    final problem = await context.read<ApiClient>().verifyKioskPin(token, entered);
    if (!mounted) return;
    if (problem == null) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _checking = false;
        _error = problem;
      });
      _pinController.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final username = authService.username ?? '—';

    return AlertDialog(
      icon: Icon(Icons.admin_panel_settings_outlined, color: scheme.primary, size: 32),
      title: Text(l10n.devicePinDialogTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.devicePinSignedInAs,
              style: TextStyle(fontSize: 12, color: scheme.outline)),
          Text(username,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 16),
          TextField(
            controller: _pinController,
            obscureText: true,
            keyboardType: TextInputType.number,
            autofocus: true,
            maxLength: 12,
            decoration: InputDecoration(
              labelText: l10n.devicePinLabel,
              border: const OutlineInputBorder(),
              errorText: _error,
              counterText: '',
            ),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          onPressed: _checking ? null : _submit,
          child: Text(l10n.devicePinUnlock),
        ),
      ],
    );
  }
}
