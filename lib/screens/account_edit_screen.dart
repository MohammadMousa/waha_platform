import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/account_user.dart';
import '../models/store.dart';
import '../services/api_client.dart';
import '../services/api_exceptions.dart';
import '../state/auth_service.dart';

class AccountEditScreen extends StatefulWidget {
  final AccountUser? account; // null = create
  const AccountEditScreen({super.key, this.account});

  @override
  State<AccountEditScreen> createState() => _AccountEditScreenState();
}

class _AccountEditScreenState extends State<AccountEditScreen> {
  bool get _isCreate => widget.account == null;

  final _username = TextEditingController();
  final _password = TextEditingController();
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _phone = TextEditingController();

  String _accountType = 'HUMAN';
  String _role = 'CASHIER';
  bool _enabled = true;
  bool _obscurePass = true;

  List<Store>? _stores;
  int? _selectedStoreId;
  bool _loadingStores = true;
  bool _saving = false;
  String? _error;

  static const _roles = ['CASHIER', 'OPERATOR', 'ADMIN', 'SUPER_ADMIN', 'REGISTERED', 'ANONYMOUS'];
  static const _types = ['HUMAN', 'KIOSK'];

  @override
  void initState() {
    super.initState();
    final u = widget.account;
    if (u != null) {
      _username.text = u.username;
      _firstName.text = u.firstName ?? '';
      _lastName.text = u.lastName ?? '';
      _phone.text = u.phone ?? '';
      _accountType = u.accountType;
      _role = u.roleName ?? 'CASHIER';
      _enabled = u.enabled;
      _selectedStoreId = u.storeId;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadStores());
  }

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _firstName.dispose();
    _lastName.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _loadStores() async {
    final api = context.read<ApiClient>();
    final token = authService.token;
    if (token == null) { setState(() => _loadingStores = false); return; }
    try {
      final stores = await api.getAdminStores(token);
      if (mounted) setState(() { _stores = stores; _loadingStores = false; });
    } catch (_) {
      if (mounted) setState(() => _loadingStores = false);
    }
  }

  Future<void> _save() async {
    final username = _username.text.trim();
    if (username.isEmpty) { setState(() => _error = 'Username is required.'); return; }
    if (_isCreate && _password.text.trim().isEmpty) {
      setState(() => _error = 'Password is required for new accounts.');
      return;
    }

    setState(() { _saving = true; _error = null; });
    final api = context.read<ApiClient>();
    final token = authService.token;
    if (token == null) { setState(() { _saving = false; _error = 'Not logged in.'; }); return; }

    try {
      if (_isCreate) {
        final body = <String, dynamic>{
          'username': username,
          'password': _password.text.trim(),
          'accountType': _accountType,
          'enabled': _enabled,
          if (_firstName.text.trim().isNotEmpty) 'firstName': _firstName.text.trim(),
          if (_lastName.text.trim().isNotEmpty) 'lastName': _lastName.text.trim(),
          if (_phone.text.trim().isNotEmpty) 'phone': _phone.text.trim(),
          if (_selectedStoreId != null) 'storeId': _selectedStoreId,
          'role': _role,
        };
        await api.createAdminAccount(body, token: token);
      } else {
        final body = <String, dynamic>{
          'accountType': _accountType,
          'enabled': _enabled,
          'firstName': _firstName.text.trim().isNotEmpty ? _firstName.text.trim() : null,
          'lastName': _lastName.text.trim().isNotEmpty ? _lastName.text.trim() : null,
          'phone': _phone.text.trim().isNotEmpty ? _phone.text.trim() : null,
          if (_password.text.trim().isNotEmpty) 'password': _password.text.trim(),
          if (_selectedStoreId != null) ...{
            'storeId': _selectedStoreId,
            'role': _role,
          },
        };
        await api.patchAdminAccount(widget.account!.id, body, token: token);
      }
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) setState(() { _error = e.message; _saving = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isCreate ? 'New Account' : 'Edit Account'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Save'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // ── Account type ────────────────────────────────────────────────
          _Label('Account Type'),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: _types
                .map((t) => ButtonSegment(value: t, label: Text(t)))
                .toList(),
            selected: {_accountType},
            onSelectionChanged: (s) => setState(() => _accountType = s.first),
          ),

          const SizedBox(height: 20),

          // ── Credentials ─────────────────────────────────────────────────
          _Label('Credentials'),
          const SizedBox(height: 8),
          TextField(
            controller: _username,
            enabled: _isCreate,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Username *',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.person_outline),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _password,
            obscureText: _obscurePass,
            decoration: InputDecoration(
              labelText: _isCreate ? 'Password *' : 'New password (leave blank to keep)',
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.key_outlined),
              suffixIcon: IconButton(
                icon: Icon(_obscurePass ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                onPressed: () => setState(() => _obscurePass = !_obscurePass),
              ),
            ),
          ),

          const SizedBox(height: 20),

          // ── Status ──────────────────────────────────────────────────────
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Enabled'),
            subtitle: Text(_enabled ? 'Account can log in' : 'Account is disabled'),
            value: _enabled,
            onChanged: (v) => setState(() => _enabled = v),
          ),

          const Divider(height: 32),

          // ── Role & Store ────────────────────────────────────────────────
          _Label('Role & Store'),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _roles.contains(_role) ? _role : _roles.first,
            decoration: const InputDecoration(
              labelText: 'Role',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.badge_outlined),
            ),
            items: _roles
                .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                .toList(),
            onChanged: (v) { if (v != null) setState(() => _role = v); },
          ),
          const SizedBox(height: 12),
          _loadingStores
              ? const Center(child: CircularProgressIndicator())
              : DropdownButtonFormField<int?>(
                  value: _selectedStoreId,
                  decoration: const InputDecoration(
                    labelText: 'Store',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.store_outlined),
                  ),
                  items: [
                    const DropdownMenuItem<int?>(value: null, child: Text('— none —')),
                    ...(_stores ?? []).map((s) => DropdownMenuItem<int?>(
                        value: s.id,
                        child: Text(s.name))),
                  ],
                  onChanged: (v) => setState(() => _selectedStoreId = v),
                ),

          // ── Personal info (HUMAN only) ──────────────────────────────────
          if (_accountType == 'HUMAN') ...[
            const Divider(height: 32),
            _Label('Personal Info'),
            const SizedBox(height: 12),
            TextField(
              controller: _firstName,
              decoration: const InputDecoration(
                labelText: 'First name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _lastName,
              decoration: const InputDecoration(
                labelText: 'Last name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Phone',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.phone_outlined),
              ),
            ),
          ],

          // ── Error ───────────────────────────────────────────────────────
          if (_error != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.errorContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(_error!, style: TextStyle(color: scheme.onErrorContainer)),
            ),
          ],

          const SizedBox(height: 40),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
      );
}
