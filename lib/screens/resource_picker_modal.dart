import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../services/api_client.dart';
import '../widgets/batch_upload_dialog.dart';
import '../widgets/resource_picker_sheet.dart';

/// Modal dialog for selecting an existing resource asset.
/// Tap any asset to confirm selection and return a [PickedResource].
class ResourcePickerModal extends StatefulWidget {
  final String storeSlug;
  final String token;
  final bool imagesOnly;

  const ResourcePickerModal({
    super.key,
    required this.storeSlug,
    required this.token,
    this.imagesOnly = false,
  });

  @override
  State<ResourcePickerModal> createState() => _ResourcePickerModalState();
}

class _ResourcePickerModalState extends State<ResourcePickerModal> {
  List<ResourceDirectory>? _dirs;
  ResourceDirectory? _selectedDir;
  List<ResourceAsset>? _assets;
  bool _loadingDirs = true;
  bool _loadingAssets = false;
  String? _error;

  ApiClient get _client => ApiClient();

  @override
  void initState() {
    super.initState();
    _loadDirs();
  }

  Future<void> _loadDirs() async {
    try {
      final dirs = await _client.getDirectories(widget.storeSlug, widget.token);
      if (!mounted) return;
      setState(() {
        _dirs = dirs;
        _loadingDirs = false;
      });
      if (dirs.isNotEmpty) _selectDir(dirs.first);
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loadingDirs = false; });
    }
  }

  Future<void> _selectDir(ResourceDirectory dir) async {
    setState(() { _selectedDir = dir; _assets = null; _loadingAssets = true; });
    try {
      final assets = await _client.getAssets(widget.storeSlug, dir.name, widget.token);
      if (!mounted) return;
      setState(() { _assets = assets; _loadingAssets = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loadingAssets = false; });
    }
  }

  void _pick(ResourceAsset asset) {
    Navigator.of(context).pop(PickedResource(
      resourceId: asset.id,
      publicUrl: asset.publicUrl(widget.storeSlug, _selectedDir!.name),
    ));
  }

  // ---- Single file upload ------------------------------------------------

  Future<void> _uploadSingleFile() async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: false);
    if (result == null || result.files.isEmpty || !mounted) return;
    final pf = result.files.first;
    if (pf.path == null) return;

    final nameCtrl = TextEditingController(text: pf.name);
    bool uploading = false;
    String? uploadError;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => PopScope(
          canPop: !uploading,
          child: AlertDialog(
            title: const Text('Upload file'),
            content: SizedBox(
              width: 320,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'To: ${_selectedDir!.name}',
                    style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(ctx).colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: nameCtrl,
                    enabled: !uploading,
                    decoration: const InputDecoration(
                      labelText: 'Filename',
                      border: OutlineInputBorder(),
                    ),
                    autofocus: true,
                  ),
                  if (uploadError != null) ...[
                    const SizedBox(height: 10),
                    Text(uploadError!,
                        style: const TextStyle(color: Colors.red, fontSize: 12)),
                  ],
                  if (uploading) ...[
                    const SizedBox(height: 16),
                    const LinearProgressIndicator(),
                  ],
                ],
              ),
            ),
            actions: uploading
                ? null
                : [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () async {
                        setSt(() { uploading = true; uploadError = null; });
                        try {
                          final name = nameCtrl.text.trim().isEmpty ? pf.name : nameCtrl.text.trim();
                          final bytes = await File(pf.path!).readAsBytes();
                          await _client.uploadAsset(
                            widget.storeSlug, _selectedDir!.name,
                            bytes, name, mimeForFilename(name), widget.token,
                          );
                          if (ctx.mounted) Navigator.pop(ctx, true);
                        } catch (e) {
                          setSt(() { uploading = false; uploadError = e.toString(); });
                        }
                      },
                      child: const Text('Upload'),
                    ),
                  ],
          ),
        ),
      ),
    );

    nameCtrl.dispose();
    if (confirmed == true && mounted && _selectedDir != null) {
      _selectDir(_selectedDir!);
    }
  }

  // ---- Multi-file / folder upload ----------------------------------------

  Future<void> _uploadMultiple() async {
    if (!mounted) return;

    // Step 1: source picker
    final source = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.file_copy_outlined),
              title: const Text('Pick files'),
              subtitle: const Text('Choose one or more files'),
              onTap: () => Navigator.pop(context, 'files'),
            ),
            ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: const Text('Pick folder'),
              subtitle: const Text('Upload all files in a directory'),
              onTap: () => Navigator.pop(context, 'folder'),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;

    // Step 2: collect items
    List<UploadItem> items;
    if (source == 'files') {
      final result = await FilePicker.platform
          .pickFiles(allowMultiple: true, type: FileType.any);
      if (result == null || result.files.isEmpty || !mounted) return;
      items = result.files
          .where((f) => f.path != null)
          .map((f) => (path: f.path!, name: f.name))
          .toList();
    } else {
      final dirPath = await FilePicker.platform.getDirectoryPath();
      if (dirPath == null || !mounted) return;
      final entities = await Directory(dirPath)
          .list(recursive: true, followLinks: false)
          .toList();
      items = entities.whereType<File>().map((f) {
        final name = f.path.split(Platform.pathSeparator).last;
        return (path: f.path, name: name);
      }).toList();
    }

    if (items.isEmpty || !mounted) return;

    // Step 3: destination picker (defaults to current dir)
    ResourceDirectory? dest = _selectedDir;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: Text('Upload ${items.length} file${items.length == 1 ? '' : 's'}'),
          content: SizedBox(
            width: 300,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Destination directory:',
                    style: TextStyle(fontSize: 13)),
                const SizedBox(height: 8),
                InputDecorator(
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  child: DropdownButton<ResourceDirectory>(
                    value: dest,
                    isDense: true,
                    isExpanded: true,
                    underline: const SizedBox.shrink(),
                    items: (_dirs ?? [])
                        .map((d) => DropdownMenuItem(value: d, child: Text(d.name)))
                        .toList(),
                    onChanged: (d) => setSt(() => dest = d),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: dest == null ? null : () => Navigator.pop(ctx, true),
              child: const Text('Start upload'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || dest == null || !mounted) return;

    // Step 4: batch progress dialog
    final done = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => BatchUploadDialog(
        items: items,
        destinationDir: dest!.name,
        storeSlug: widget.storeSlug,
        token: widget.token,
        client: _client,
      ),
    );

    if (done == true && mounted) {
      _selectDir(dest!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 520),
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
              child: Row(
                children: [
                  Icon(Icons.folder_open_outlined, color: scheme.primary, size: 20),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text('Select Resource',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.upload_file_outlined),
                    tooltip: _selectedDir == null
                        ? 'Select a directory first'
                        : 'Upload file',
                    onPressed: _loadingDirs || _selectedDir == null
                        ? null
                        : _uploadSingleFile,
                  ),
                  IconButton(
                    icon: const Icon(Icons.drive_folder_upload_outlined),
                    tooltip: _selectedDir == null
                        ? 'Select a directory first'
                        : 'Upload files or folder',
                    onPressed: _loadingDirs || _selectedDir == null
                        ? null
                        : _uploadMultiple,
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(null),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _loadingDirs
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
                      : Row(
                          children: [
                            // Directory list
                            SizedBox(
                              width: 160,
                              child: ListView.builder(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                itemCount: _dirs?.length ?? 0,
                                itemBuilder: (ctx, i) {
                                  final dir = _dirs![i];
                                  final selected = _selectedDir?.id == dir.id;
                                  return ListTile(
                                    dense: true,
                                    selected: selected,
                                    selectedTileColor: scheme.primaryContainer,
                                    leading: Icon(
                                      Icons.folder_outlined,
                                      size: 18,
                                      color: selected ? scheme.primary : scheme.onSurfaceVariant,
                                    ),
                                    title: Text(dir.name,
                                        style: const TextStyle(fontSize: 13)),
                                    onTap: () => _selectDir(dir),
                                  );
                                },
                              ),
                            ),
                            const VerticalDivider(width: 1),
                            // Asset grid
                            Expanded(
                              child: _loadingAssets
                                  ? const Center(child: CircularProgressIndicator())
                                  : _assets == null || _assets!.isEmpty
                                      ? Center(
                                          child: Text('No assets',
                                              style: TextStyle(color: scheme.outline)),
                                        )
                                      : Builder(builder: (ctx) {
                                          final visible = widget.imagesOnly
                                              ? _assets!.where((a) => a.isImage).toList()
                                              : _assets!;
                                          if (visible.isEmpty) {
                                            return Center(
                                              child: Text(
                                                widget.imagesOnly
                                                    ? 'No images in this directory'
                                                    : 'No assets',
                                                style: TextStyle(color: Theme.of(ctx).colorScheme.outline),
                                              ),
                                            );
                                          }
                                          return GridView.builder(
                                            padding: const EdgeInsets.all(12),
                                            gridDelegate:
                                                const SliverGridDelegateWithFixedCrossAxisCount(
                                              crossAxisCount: 3,
                                              crossAxisSpacing: 8,
                                              mainAxisSpacing: 8,
                                            ),
                                            itemCount: visible.length,
                                            itemBuilder: (ctx, i) {
                                              final asset = visible[i];
                                              return _AssetTile(
                                                asset: asset,
                                                storeSlug: widget.storeSlug,
                                                dirName: _selectedDir!.name,
                                                onTap: () => _pick(asset),
                                              );
                                            },
                                          );
                                        }),
                            ),
                          ],
                        ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(null),
                  child: const Text('Cancel'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AssetTile extends StatelessWidget {
  final ResourceAsset asset;
  final String storeSlug;
  final String dirName;
  final VoidCallback onTap;

  const _AssetTile({
    required this.asset,
    required this.storeSlug,
    required this.dirName,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final url = asset.publicUrl(storeSlug, dirName);

    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (asset.isImage)
              Image.network(
                '${AppConfig.apiBaseUrl}$url',
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _fallbackIcon(scheme),
              )
            else
              _fallbackIcon(scheme),
            // Name overlay
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: Container(
                color: Colors.black54,
                padding: const EdgeInsets.all(4),
                child: Text(
                  asset.name,
                  style: const TextStyle(color: Colors.white, fontSize: 10),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fallbackIcon(ColorScheme scheme) => Container(
        color: scheme.surfaceContainerHighest,
        child: Icon(Icons.insert_drive_file_outlined,
            color: scheme.onSurfaceVariant, size: 32),
      );
}
