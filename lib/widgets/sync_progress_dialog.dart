import 'dart:async';

import 'package:flutter/material.dart';

import '../data/sync/run_result.dart';
import '../data/sync/sync_service.dart';
import '../l10n/generated/app_localizations.dart';
import 'run_result_text.dart';

/// Shown by the `cmd=sync-pull` scan command: starts a pull (or follows the
/// one already running in the background) and shows its progress. Nothing
/// waits on the admin: when the pull ends the dialog closes by itself and the
/// outcome shows as a toast, and a tap outside closes the dialog at any time
/// (the pull carries on and the toast still appears). A manual pull is not
/// stopped by screen activity.
Future<void> showSyncProgressDialog(BuildContext context) async {
  final l = AppLocalizations.of(context)!;
  final svc = SyncService.instance;
  BuildContext? dialogContext;
  var open = true;

  showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) {
      dialogContext = ctx;
      return _SyncProgressDialog(svc.progress, l);
    },
  ).whenComplete(() => open = false);

  final RunResult result;
  if (svc.running) {
    // A background pull is already going: wait for it, then report it.
    final done = Completer<void>();
    void listener() {
      if (!svc.running && !done.isCompleted) done.complete();
    }

    svc.addListener(listener);
    await done.future;
    svc.removeListener(listener);
    result = svc.lastResult ?? const RunResult(RunKind.done);
  } else {
    result = await svc.runOnce(manual: true);
  }

  final ctx = dialogContext;
  if (open && ctx != null && ctx.mounted) Navigator.of(ctx).pop();
  showResultToast(pullResultText(l, result), problem: isProblem(result));
}

class _SyncProgressDialog extends StatelessWidget {
  final ValueNotifier<SyncProgress?> progress;
  final AppLocalizations l;
  const _SyncProgressDialog(this.progress, this.l);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: const Icon(Icons.sync),
      title: Text(l.offlineDataTitle),
      content: SizedBox(
        width: 320,
        child: ValueListenableBuilder<SyncProgress?>(
          valueListenable: progress,
          builder: (_, p, __) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.offlinePulling),
              const SizedBox(height: 12),
              LinearProgressIndicator(value: p == null ? null : p.done / p.total),
              if (p != null) ...[
                const SizedBox(height: 8),
                Text('${p.step}  (${p.done}/${p.total})',
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
