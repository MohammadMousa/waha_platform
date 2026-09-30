import 'package:flutter/material.dart';

import '../screens/settings_screen.dart' show showCopyableTextDialog;
import '../services/geidea_terminal_bridge.dart';

/// The single place every scan — hardware scanner or camera — passes
/// through before `scan_actions.dart` treats it as a product barcode. A
/// `cmd=` prefix marks a kiosk command instead of a product code: e.g. a QR
/// sticker (content `cmd=upload-logs`) the client can scan to self-report
/// diagnostics without hunting for the Settings PIN. Add a new command only
/// to [_commands] below — nothing else needs to change as the list grows.
///
/// Commands here must stay read-only/diagnostic (nothing that changes kiosk
/// state) — a `cmd=` code is just printed text, anyone could scan it. A
/// command that ever needs to change something should go through the
/// existing Settings PIN confirmation instead of being added here.
class ScannerManager {
  ScannerManager._();
  static final ScannerManager instance = ScannerManager._();

  static const _prefix = 'cmd=';

  final Map<String, Future<void> Function(BuildContext)> _commands = {
    'upload-logs': _uploadLogs,
  };

  /// True when [code] was a command — handled, or simply not recognized —
  /// either way the caller must NOT also treat it as a product barcode.
  /// False means "not mine," i.e. a normal barcode: proceed as usual.
  Future<bool> handle(BuildContext context, String code) async {
    if (!code.startsWith(_prefix)) return false;
    final command = _commands[code.substring(_prefix.length)];
    if (command != null) await command(context);
    return true;
  }

  static Future<void> _uploadLogs(BuildContext context) async {
    final result = await GeideaTerminalBridge.instance.uploadLog();
    if (!context.mounted) return;
    // Same result dialog Settings' "Upload log" button already shows.
    await showCopyableTextDialog(
      context,
      'Upload log',
      GeideaTerminalBridge.describeUploadLogResult(result),
    );
  }
}
