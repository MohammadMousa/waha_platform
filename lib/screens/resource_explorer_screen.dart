import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../services/api_client.dart';
import '../state/auth_service.dart';
import '../state/store_config_service.dart';

// Two-panel resource explorer: directories on the left, assets on the right.
// Adaptive: side-by-side on wide screens, master-detail on narrow ones.
class ResourceExplorerScreen extends StatefulWidget {
  const ResourceExplorerScreen({super.key});

  @override
  State<ResourceExplorerScreen> createState() => _ResourceExplorerScreenState();
}

class _ResourceExplorerScreenState extends State<ResourceExplorerScreen> {
  List<ResourceDirectory> _dirs = [];
  ResourceDirectory? _selectedDir;
  List<ResourceAsset> _assets = [];
  bool _loadingDirs = false;
  bool _loadingAssets = false;
  String? _error;

  String get _storeSlug => storeConfigService.storeSlug ?? '';
  String get _storeDisplayName => storeConfigService.storeName ?? _storeSlug;

  @override
  void initState() {
    super.initState();
    _loadDirs();
  }

  String get _token => authService.token ?? '';

  Future<void> _loadDirs() async {
    if (_storeSlug.isEmpty) { setState(() { _error = 'Store not configured'; _loadingDirs = false; }); return; }
    setState(() { _loadingDirs = true; _error = null; });
    try {
      final dirs = await context.read<ApiClient>().getDirectories(_storeSlug, _token);
      if (mounted) {
        setState(() { _dirs = dirs; _loadingDirs = false; });
        if (_selectedDir != null) {
          final still = dirs.where((d) => d.id == _selectedDir!.id);
          if (still.isNotEmpty) {
            _selectedDir = still.first;
          } else {
            _selectedDir = null;
            _assets = [];
          }
        }
      }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loadingDirs = false; });
    }
  }

  Future<void> _selectDir(ResourceDirectory dir) async {
    setState(() { _selectedDir = dir; _loadingAssets = true; _assets = []; });
    try {
      final assets = await context.read<ApiClient>().getAssets(_storeSlug, dir.name, _token);
      if (mounted) setState(() { _assets = assets; _loadingAssets = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loadingAssets = false; });
    }
  }

  Future<void> _createDir() async {
    final client = context.read<ApiClient>();
    final name = await _showNameDialog(context, title: 'New Directory',
        hint: 'e.g. landing, products');
    if (name == null || name.isEmpty) return;
    try {
      await client.createDirectory(_storeSlug, name, _token);
      await _loadDirs();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _upload() async {
    final dir = _selectedDir;
    if (dir == null) return;
    final client = context.read<ApiClient>();
    final result = await FilePicker.platform.pickFiles(withData: true);
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.bytes == null) return;

    final mimeType = _guessMime(file.name);
    setState(() => _loadingAssets = true);
    try {
      await client.uploadAsset(
        _storeSlug, dir.name, file.bytes!, file.name, mimeType, _token);
      if (mounted) await _selectDir(dir);
    } catch (e) {
      if (mounted) {
        setState(() => _loadingAssets = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _delete(ResourceAsset asset) async {
    final dir = _selectedDir;
    if (dir == null) return;
    final client = context.read<ApiClient>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete asset?'),
        content: Text('Delete "${asset.name}" from ${dir.name}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await client.deleteAsset(_storeSlug, dir.name, asset.name, _token);
      if (mounted) await _selectDir(dir);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Delete failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _copyUrl(ResourceAsset asset) {
    final dir = _selectedDir;
    if (dir == null) return;
    final url = asset.publicUrl(_storeSlug, dir.name);
    Clipboard.setData(ClipboardData(text: url));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Copied: $url')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width > 600;
    return Scaffold(
      appBar: AppBar(
        title: Text('Resource Explorer${_storeDisplayName.isNotEmpty ? ' — $_storeDisplayName' : ''}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_outlined),
            tooltip: 'Refresh',
            onPressed: () async {
              await _loadDirs();
              if (_selectedDir != null) await _selectDir(_selectedDir!);
            },
          ),
        ],
      ),
      body: _error != null && _dirs.isEmpty
          ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(_error!, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 12),
              OutlinedButton(onPressed: _loadDirs, child: const Text('Retry')),
            ]))
          : wide
              ? Row(children: [
                  SizedBox(width: 220, child: _DirectoryPanel(
                    dirs: _dirs,
                    selected: _selectedDir,
                    loading: _loadingDirs,
                    onSelect: _selectDir,
                    onNew: _createDir,
                  )),
                  const VerticalDivider(width: 1),
                  Expanded(child: _AssetPanel(
                    dir: _selectedDir,
                    assets: _assets,
                    loading: _loadingAssets,
                    onUpload: _upload,
                    onDelete: _delete,
                    onCopyUrl: _copyUrl,
                    storeName: _storeSlug,
                  )),
                ])
              : _selectedDir == null
                  ? _DirectoryPanel(
                      dirs: _dirs,
                      selected: null,
                      loading: _loadingDirs,
                      onSelect: _selectDir,
                      onNew: _createDir,
                    )
                  : Column(children: [
                      ListTile(
                        leading: const Icon(Icons.arrow_back),
                        title: Text(_selectedDir!.name),
                        onTap: () => setState(() { _selectedDir = null; _assets = []; }),
                      ),
                      const Divider(height: 1),
                      Expanded(child: _AssetPanel(
                        dir: _selectedDir,
                        assets: _assets,
                        loading: _loadingAssets,
                        onUpload: _upload,
                        onDelete: _delete,
                        onCopyUrl: _copyUrl,
                        storeName: _storeSlug,
                      )),
                    ]),
    );
  }
}

// ── Directory panel ────────────────────────────────────────────────────────────

class _DirectoryPanel extends StatelessWidget {
  final List<ResourceDirectory> dirs;
  final ResourceDirectory? selected;
  final bool loading;
  final ValueChanged<ResourceDirectory> onSelect;
  final VoidCallback onNew;

  const _DirectoryPanel({
    required this.dirs, required this.selected, required this.loading,
    required this.onSelect, required this.onNew,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Expanded(
          child: loading
              ? const Center(child: CircularProgressIndicator())
              : dirs.isEmpty
                  ? Center(
                      child: Text('No directories yet',
                          style: TextStyle(color: scheme.outline)),
                    )
                  : ListView.builder(
                      itemCount: dirs.length,
                      itemBuilder: (_, i) {
                        final d = dirs[i];
                        final isSelected = selected?.id == d.id;
                        return ListTile(
                          leading: Icon(Icons.folder_outlined,
                              color: isSelected ? scheme.primary : scheme.outline),
                          title: Text(d.name),
                          selected: isSelected,
                          selectedTileColor: scheme.primaryContainer.withValues(alpha: 0.3),
                          onTap: () => onSelect(d),
                        );
                      },
                    ),
        ),
        const Divider(height: 1),
        ListTile(
          leading: Icon(Icons.create_new_folder_outlined, color: scheme.primary),
          title: const Text('New Directory'),
          onTap: onNew,
        ),
      ],
    );
  }
}

// ── Asset panel ────────────────────────────────────────────────────────────────

class _AssetPanel extends StatelessWidget {
  final ResourceDirectory? dir;
  final List<ResourceAsset> assets;
  final bool loading;
  final VoidCallback onUpload;
  final ValueChanged<ResourceAsset> onDelete;
  final ValueChanged<ResourceAsset> onCopyUrl;
  final String storeName;

  const _AssetPanel({
    required this.dir, required this.assets, required this.loading,
    required this.onUpload, required this.onDelete, required this.onCopyUrl,
    required this.storeName,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (dir == null) {
      return Center(
        child: Text('Select a directory', style: TextStyle(color: scheme.outline)),
      );
    }

    return Column(
      children: [
        Expanded(
          child: loading
              ? const Center(child: CircularProgressIndicator())
              : assets.isEmpty
                  ? Center(
                      child: Text('No files in ${dir!.name}',
                          style: TextStyle(color: scheme.outline)),
                    )
                  : ListView.builder(
                      itemCount: assets.length,
                      itemBuilder: (_, i) => _AssetTile(
                        asset: assets[i],
                        dir: dir!,
                        storeName: storeName,
                        onDelete: () => onDelete(assets[i]),
                        onCopyUrl: () => onCopyUrl(assets[i]),
                      ),
                    ),
        ),
        const Divider(height: 1),
        ListTile(
          leading: Icon(Icons.upload_file_outlined, color: scheme.primary),
          title: const Text('Upload File'),
          onTap: onUpload,
        ),
      ],
    );
  }
}

class _AssetTile extends StatelessWidget {
  final ResourceAsset asset;
  final ResourceDirectory dir;
  final String storeName;
  final VoidCallback onDelete;
  final VoidCallback onCopyUrl;

  const _AssetTile({
    required this.asset, required this.dir, required this.storeName,
    required this.onDelete, required this.onCopyUrl,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final size = _fmtSize(asset.sizeBytes);

    return ListTile(
      leading: Icon(
        asset.isImage
            ? Icons.image_outlined
            : asset.isHtml
                ? Icons.html_outlined
                : Icons.insert_drive_file_outlined,
        color: scheme.primary,
      ),
      title: Text(asset.name, overflow: TextOverflow.ellipsis),
      subtitle: Text('$size · ${asset.mimeType}',
          style: TextStyle(color: scheme.outline, fontSize: 11)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.copy_outlined, size: 18),
            tooltip: 'Copy URL',
            onPressed: onCopyUrl,
          ),
          IconButton(
            icon: Icon(Icons.delete_outline, size: 18, color: scheme.error),
            tooltip: 'Delete',
            onPressed: onDelete,
          ),
        ],
      ),
      onTap: () => _showPreview(context, asset, dir, storeName),
    );
  }
}

void _showPreview(BuildContext context, ResourceAsset asset,
    ResourceDirectory dir, String storeName) {
  final url = asset.publicUrl(storeName, dir.name);
  showDialog(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(asset.name, overflow: TextOverflow.ellipsis),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (asset.isImage) ...[
            Image.network(url, errorBuilder: (_, __, ___) =>
                const Text('Image preview unavailable')),
            const SizedBox(height: 8),
          ],
          SelectableText(url, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
          const SizedBox(height: 4),
          Text('${_fmtSize(asset.sizeBytes)} · ${asset.mimeType}',
              style: TextStyle(color: Theme.of(context).colorScheme.outline, fontSize: 11)),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        FilledButton.icon(
          icon: const Icon(Icons.copy_outlined, size: 16),
          label: const Text('Copy URL'),
          onPressed: () {
            Clipboard.setData(ClipboardData(text: url));
            Navigator.pop(context);
          },
        ),
      ],
    ),
  );
}

// ── Helpers ────────────────────────────────────────────────────────────────────

Future<String?> _showNameDialog(BuildContext context,
    {required String title, String hint = ''}) {
  final ctrl = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        decoration: InputDecoration(hintText: hint, border: const OutlineInputBorder()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(context, ctrl.text.trim()),
          child: const Text('Create'),
        ),
      ],
    ),
  );
}

String _fmtSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
}

String _guessMime(String filename) {
  final ext = filename.split('.').last.toLowerCase();
  return switch (ext) {
    'jpg' || 'jpeg' => 'image/jpeg',
    'png' => 'image/png',
    'gif' => 'image/gif',
    'webp' => 'image/webp',
    'svg' => 'image/svg+xml',
    'html' || 'htm' => 'text/html',
    'css' => 'text/css',
    'js' => 'application/javascript',
    'pdf' => 'application/pdf',
    'mp4' => 'video/mp4',
    _ => 'application/octet-stream',
  };
}
