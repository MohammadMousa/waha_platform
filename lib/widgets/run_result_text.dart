import 'package:flutter/material.dart';

import '../data/sync/run_result.dart';
import '../l10n/generated/app_localizations.dart';
import '../services/app_messenger.dart';

/// Plain-language text (Arabic or English) for how a pull ended.
String pullResultText(AppLocalizations l, RunResult r) => switch (r.kind) {
      RunKind.done => l.pullDone('${r.count}'),
      RunKind.failed => l.pullFailed(r.detail ?? ''),
      RunKind.noSession => l.pullNoSession,
      RunKind.customerActive => l.pullCustomerActive,
      RunKind.busy => l.pullBusy,
      RunKind.serverBusy => l.pullServerBusy('${r.waitSeconds}'),
      RunKind.authStopped => l.pullAuthStopped,
    };

/// Plain-language text (Arabic or English) for how a send ended.
String sendResultText(AppLocalizations l, RunResult r) => switch (r.kind) {
      RunKind.done when r.count == 0 && r.rejected == 0 => l.sendNothing,
      RunKind.done when r.rejected == 0 => l.sendDone('${r.count}'),
      RunKind.done when r.count == 0 => l.sendRejected('${r.rejected}'),
      RunKind.done => l.sendPartial('${r.count}', '${r.rejected}'),
      RunKind.failed => l.sendFailed(r.detail ?? ''),
      RunKind.noSession => l.sendNoSession,
      RunKind.authStopped => l.sendAuthStopped,
      RunKind.busy => l.sendBusy,
      RunKind.customerActive || RunKind.serverBusy => l.sendFailed(''),
    };

String clockTime(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
}

/// A message at the bottom of the screen, replacing any one still showing.
void showResultToast(String text, {bool problem = false}) {
  final m = rootScaffoldMessengerKey.currentState;
  if (m == null) return;
  m
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(text),
      backgroundColor: problem ? Colors.red.shade700 : null,
      duration: const Duration(seconds: 4),
    ));
}

bool isProblem(RunResult r) =>
    r.kind == RunKind.failed ||
    r.kind == RunKind.authStopped ||
    r.rejected > 0;
