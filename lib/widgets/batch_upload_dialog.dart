import 'dart:io';

import 'package:flutter/material.dart';

import '../services/api_client.dart';

typedef UploadItem = ({String path, String name});

String mimeForFilename(String name) {
  final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
  const map = {
    'jpg': 'image/jpeg', 'jpeg': 'image/jpeg', 'png': 'image/png',
    'gif': 'image/gif', 'webp': 'image/webp', 'svg': 'image/svg+xml',
    'pdf': 'application/pdf',
    'mp4': 'video/mp4', 'mov': 'video/quicktime',
    'mp3': 'audio/mpeg', 'wav': 'audio/wav',
  };
  return map[ext] ?? 'application/octet-stream';
}

/// Blocking progress dialog for batch uploads.
/// Cannot be dismissed while uploading. Returns `true` on completion.
class BatchUploadDialog extends StatefulWidget {
  final List<UploadItem> items;
  final String destinationDir;
  final String storeSlug;
  final String token;
  final ApiClient client;

  const BatchUploadDialog({
    super.key,
    required this.items,
    required this.destinationDir,
    required this.storeSlug,
    required this.token,
    required this.client,
  });

  @override
  State<BatchUploadDialog> createState() => _BatchUploadDialogState();
}

class _BatchUploadDialogState extends State<BatchUploadDialog> {
  int _done = 0;
  int _failed = 0;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    final items = widget.items;
    for (int i = 0; i < items.length; i++) {
      final item = items[i];
      try {
        final bytes = await File(item.path).readAsBytes();
        await widget.client.uploadAsset(
          widget.storeSlug,
          widget.destinationDir,
          bytes,
          item.name,
          mimeForFilename(item.name),
          widget.token,
        );
      } catch (_) {
        if (mounted) setState(() => _failed++);
      }
      if (mounted) setState(() => _done++);
    }
    if (mounted) setState(() => _finished = true);
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.items.length;
    final scheme = Theme.of(context).colorScheme;

    final inProgress = !_finished && _done < total;
    final currentName = inProgress ? widget.items[_done].name : '';

    return PopScope(
      canPop: _finished,
      child: AlertDialog(
        title: Text(_finished ? 'Upload complete' : 'Uploading…'),
        content: SizedBox(
          width: 320,
          child: _finished ? _buildDone(total, scheme) : _buildProgress(total, currentName, scheme),
        ),
        actions: _finished
            ? [
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Done'),
                ),
              ]
            : null,
      ),
    );
  }

  Widget _buildProgress(int total, String currentName, ColorScheme scheme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        LinearProgressIndicator(
          value: total > 0 ? _done / total : null,
          backgroundColor: scheme.surfaceContainerHighest,
        ),
        const SizedBox(height: 24),
        Text(
          '$_done / $total',
          style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          currentName,
          style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        const CircularProgressIndicator(),
      ],
    );
  }

  Widget _buildDone(int total, ColorScheme scheme) {
    final success = total - _failed;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          _failed == 0 ? Icons.check_circle_outlined : Icons.warning_amber_outlined,
          size: 52,
          color: _failed == 0 ? Colors.green : scheme.error,
        ),
        const SizedBox(height: 12),
        Text(
          _failed == 0
              ? '$total file${total == 1 ? '' : 's'} uploaded successfully'
              : '$success uploaded · $_failed failed',
          style: const TextStyle(fontSize: 15),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
