import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/api_client.dart';
import 'resource_picker_sheet.dart';

class SaveResourceDialog extends StatefulWidget {
  final XFile file;
  final String storeSlug;
  final String token;
  final ApiClient client;

  const SaveResourceDialog({
    super.key,
    required this.file,
    required this.storeSlug,
    required this.token,
    required this.client,
  });

  @override
  State<SaveResourceDialog> createState() => _SaveResourceDialogState();
}

class _SaveResourceDialogState extends State<SaveResourceDialog> {
  List<ResourceDirectory>? _dirs;
  ResourceDirectory? _selectedDir;
  late TextEditingController _nameCtrl;
  bool _loadingDirs = true;
  bool _creating = false;
  bool _uploading = false;
  String? _error;

  bool _showNewDir = false;
  final _newDirCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.file.name);
    _loadDirs();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _newDirCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadDirs() async {
    try {
      final dirs = await widget.client.getDirectories(widget.storeSlug, widget.token);
      if (!mounted) return;
      setState(() {
        _dirs = dirs;
        _selectedDir = dirs.isNotEmpty ? dirs.first : null;
        _loadingDirs = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loadingDirs = false; });
    }
  }

  Future<void> _createDir() async {
    final name = _newDirCtrl.text.trim();
    if (name.isEmpty) return;
    setState(() => _creating = true);
    try {
      final dir = await widget.client.createDirectory(widget.storeSlug, name, widget.token);
      if (!mounted) return;
      setState(() {
        _dirs = [...(_dirs ?? []), dir];
        _selectedDir = dir;
        _showNewDir = false;
        _newDirCtrl.clear();
        _creating = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _creating = false; });
    }
  }

  Future<void> _upload() async {
    final dir = _selectedDir;
    final name = _nameCtrl.text.trim();
    if (dir == null || name.isEmpty) return;
    setState(() { _uploading = true; _error = null; });
    try {
      final bytes = await widget.file.readAsBytes();
      final mimeType = _mimeFromPath(widget.file.path);
      final asset = await widget.client.uploadAsset(
        widget.storeSlug, dir.name, bytes, widget.file.name, mimeType, widget.token,
        nameOverride: name,
      );
      if (!mounted) return;
      Navigator.of(context).pop(PickedResource(
        resourceId: asset.id,
        publicUrl: asset.publicUrl(widget.storeSlug, dir.name),
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _uploading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('Save Image'),
      content: SizedBox(
        width: 340,
        child: _loadingDirs
            ? const SizedBox(height: 80, child: Center(child: CircularProgressIndicator()))
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: (_dirs == null || _dirs!.isEmpty)
                            ? Text(
                                'No directories yet — create one',
                                style: TextStyle(color: scheme.outline, fontSize: 13),
                              )
                            : InputDecorator(
                                decoration: const InputDecoration(
                                  labelText: 'Directory',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                ),
                                child: DropdownButton<ResourceDirectory>(
                                  value: _selectedDir,
                                  isDense: true,
                                  isExpanded: true,
                                  underline: const SizedBox.shrink(),
                                  items: (_dirs ?? [])
                                      .map((d) => DropdownMenuItem(
                                          value: d, child: Text(d.name)))
                                      .toList(),
                                  onChanged: (d) => setState(() => _selectedDir = d),
                                ),
                              ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.outlined(
                        tooltip: 'New directory',
                        icon: const Icon(Icons.create_new_folder_outlined, size: 20),
                        onPressed: () => setState(() => _showNewDir = !_showNewDir),
                      ),
                    ],
                  ),
                  if (_showNewDir) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _newDirCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Folder name',
                              border: OutlineInputBorder(),
                              isDense: true,
                              hintText: 'e.g. avatars',
                            ),
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => _createDir(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _creating
                            ? const SizedBox(
                                width: 24, height: 24,
                                child: CircularProgressIndicator(strokeWidth: 2))
                            : IconButton(
                                icon: const Icon(Icons.check),
                                onPressed: _createDir,
                              ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 14),
                  TextField(
                    controller: _nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Filename',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(_error!,
                        style: const TextStyle(color: Colors.red, fontSize: 12)),
                  ],
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: _uploading ? null : () => Navigator.of(context).pop(null),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: (_uploading || _loadingDirs || _selectedDir == null) ? null : _upload,
          child: _uploading
              ? const SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Save'),
        ),
      ],
    );
  }
}

String _mimeFromPath(String path) {
  final ext = path.split('.').last.toLowerCase();
  return switch (ext) {
    'jpg' || 'jpeg' => 'image/jpeg',
    'png' => 'image/png',
    'gif' => 'image/gif',
    'webp' => 'image/webp',
    _ => 'application/octet-stream',
  };
}
