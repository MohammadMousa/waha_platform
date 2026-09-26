import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/generated/app_localizations.dart';
import '../router/app_router.dart';
import '../services/api_client.dart';
import '../services/api_exceptions.dart';
import '../state/auth_service.dart';

/// Kiosk mode's only entry point when the device has no active session —
/// a fixed-terminal login (device username + 4-digit PIN, POST
/// /api/kiosk/auth/login), not the customer phone/OTP form in
/// login_screen.dart. The router (see app_router.dart) forces every route
/// to this screen while !authService.isDeviceSession, so there is no
/// anonymous path through Kiosk mode anymore.
class KioskLoginScreen extends StatefulWidget {
  const KioskLoginScreen({super.key});

  @override
  State<KioskLoginScreen> createState() => _KioskLoginScreenState();
}

class _KioskLoginScreenState extends State<KioskLoginScreen> {
  final _username = TextEditingController();
  final _pin = TextEditingController();
  bool _obscure = true;
  bool _submitting = false;
  String? _error;

  // Lockout: while > 0 the form is disabled and the banner ticks down.
  int _lockSecondsLeft = 0;
  Timer? _lockTimer;
  bool get _locked => _lockSecondsLeft > 0;
  String _lockHeadline = 'Account temporarily locked.';

  void _startLock(int seconds) {
    _lockTimer?.cancel();
    setState(() => _lockSecondsLeft = seconds);
    _lockTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() {
        _lockSecondsLeft--;
        if (_lockSecondsLeft <= 0) {
          _lockSecondsLeft = 0;
          _error = null;
          t.cancel();
        }
      });
    });
  }

  @override
  void dispose() {
    _lockTimer?.cancel();
    _username.dispose();
    _pin.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context)!;
    if (_username.text.trim().isEmpty || _pin.text.trim().isEmpty) {
      setState(() => _error = l10n.authRequiredError);
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await authService.loginKiosk(
        context.read<ApiClient>(),
        _username.text.trim(),
        _pin.text.trim(),
      );
      // onGenerateRoute only re-evaluates on navigation, not on
      // AuthService.notifyListeners() — the guard replaced whatever route
      // was originally requested with this screen, so once logged in
      // navigate to a concrete destination rather than relying on a
      // rebuild that will never come.
      if (mounted) {
        Navigator.of(context)
            .pushNamedAndRemoveUntil(Routes.landing, (r) => false);
      }
    } on AccountLockedException catch (e) {
      final wait = e.retryAfterSeconds;
      if (!mounted) return;
      if (wait != null && wait > 0) {
        _lockHeadline = e.headline;
        _startLock(wait);
      } else {
        setState(() => _error = loginFailureText(e));
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = loginFailureText(e));
    } on NetworkException catch (_) {
      // Distinct type from ApiException (see api_exceptions.dart) — a
      // timeout or unreachable server was previously falling through
      // uncaught here, silently resetting the spinner with zero feedback
      // (looked exactly like the login screen was "stuck").
      if (mounted) {
        setState(() => _error =
            'Could not reach the server. Check your connection and try again.');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Something went wrong. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 40,
                  backgroundColor: scheme.primaryContainer,
                  child: Icon(Icons.point_of_sale_outlined,
                      size: 40, color: scheme.onPrimaryContainer),
                ),
                const SizedBox(height: 16),
                Text(
                  l10n.authDeviceLogin,
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.authDeviceLoginSubtitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: scheme.outline),
                ),
                const SizedBox(height: 32),
                Card(
                  elevation: 0,
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20)),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          controller: _username,
                          textInputAction: TextInputAction.next,
                          autocorrect: false,
                          enabled: !_submitting && !_locked,
                          decoration: InputDecoration(
                            labelText: l10n.authUsername,
                            prefixIcon: const Icon(Icons.person_outline),
                            border: const OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _pin,
                          obscureText: _obscure,
                          keyboardType: TextInputType.number,
                          // Backend moved device PINs to 6 digits; existing
                          // devices keep their old 4-digit PIN until reset
                          // (see to_Kiosk_AI_On_Auth_Task), so this only caps
                          // the max — it never required exactly 4.
                          maxLength: 6,
                          textInputAction: TextInputAction.done,
                          enabled: !_submitting && !_locked,
                          onSubmitted: (_) => _submit(),
                          decoration: InputDecoration(
                            labelText: l10n.authPinCode,
                            counterText: '',
                            prefixIcon: const Icon(Icons.key_outlined),
                            border: const OutlineInputBorder(),
                            suffixIcon: IconButton(
                              icon: Icon(_obscure
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined),
                              onPressed: () =>
                                  setState(() => _obscure = !_obscure),
                            ),
                          ),
                        ),
                        if (_locked || _error != null) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: scheme.errorContainer,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                                _locked
                                    ? '$_lockHeadline Try again in ${formatMmSs(_lockSecondsLeft)}'
                                    : _error!,
                                style:
                                    TextStyle(color: scheme.onErrorContainer)),
                          ),
                        ],
                        const SizedBox(height: 20),
                        FilledButton(
                          onPressed: (_submitting || _locked) ? null : _submit,
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          child: _submitting
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2))
                              : Text(l10n.authLoginCta,
                                  style: const TextStyle(fontSize: 16)),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
