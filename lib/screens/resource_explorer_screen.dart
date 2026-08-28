import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../config/app_config.dart';
import '../services/api_client.dart';
import '../state/auth_service.dart';
import '../state/store_config_service.dart';

// ── Layout modes ───────────────────────────────────────────────────────────────

enum _AssetLayout { list, listThumb, grid }

// ── Preview layout modes ───────────────────────────────────────────────────────

enum _PreviewLayout { fullscreen, fitHeight, fitWidth }

// ── Screen ─────────────────────────────────────────────────────────────────────

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

  // Per-directory layout preference (keyed by directory id).
  final Map<int, _AssetLayout> _layoutPrefs = {};
  _AssetLayout get _layout => _layoutPrefs[_selectedDir?.id] ?? _AssetLayout.list;

  String get _storeSlug => storeConfigService.storeSlug ?? '';
  String get _storeDisplayName => storeConfigService.storeName ?? _storeSlug;

  @override
  void initState() {
    super.initState();
    _loadDirs();
  }

  String get _token => authService.token ?? '';

  Future<void> _loadDirs() async {
    if (_storeSlug.isEmpty) {
      setState(() { _error = 'Store not configured'; _loadingDirs = false; });
      return;
    }
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
      await client.uploadAsset(_storeSlug, dir.name, file.bytes!, file.name, mimeType, _token);
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

  void _setLayout(_AssetLayout layout) {
    final dir = _selectedDir;
    if (dir == null) return;
    setState(() => _layoutPrefs[dir.id] = layout);
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
                    dirs: _dirs, selected: _selectedDir,
                    loading: _loadingDirs, onSelect: _selectDir, onNew: _createDir,
                  )),
                  const VerticalDivider(width: 1),
                  Expanded(child: _AssetPanel(
                    dir: _selectedDir, assets: _assets, loading: _loadingAssets,
                    onUpload: _upload, onDelete: _delete, onCopyUrl: _copyUrl,
                    storeName: _storeSlug, layout: _layout, onLayoutChange: _setLayout,
                  )),
                ])
              : _selectedDir == null
                  ? _DirectoryPanel(
                      dirs: _dirs, selected: null, loading: _loadingDirs,
                      onSelect: _selectDir, onNew: _createDir,
                    )
                  : Column(children: [
                      ListTile(
                        leading: const Icon(Icons.arrow_back),
                        title: Text(_selectedDir!.name),
                        onTap: () => setState(() { _selectedDir = null; _assets = []; }),
                      ),
                      const Divider(height: 1),
                      Expanded(child: _AssetPanel(
                        dir: _selectedDir, assets: _assets, loading: _loadingAssets,
                        onUpload: _upload, onDelete: _delete, onCopyUrl: _copyUrl,
                        storeName: _storeSlug, layout: _layout, onLayoutChange: _setLayout,
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
                  ? Center(child: Text('No directories yet', style: TextStyle(color: scheme.outline)))
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
  final _AssetLayout layout;
  final ValueChanged<_AssetLayout> onLayoutChange;

  const _AssetPanel({
    required this.dir, required this.assets, required this.loading,
    required this.onUpload, required this.onDelete, required this.onCopyUrl,
    required this.storeName, required this.layout, required this.onLayoutChange,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (dir == null) {
      return Center(child: Text('Select a directory', style: TextStyle(color: scheme.outline)));
    }

    return Column(
      children: [
        // ── Toolbar ──────────────────────────────────────────────────────────
        Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5))),
          ),
          child: Row(
            children: [
              // Layout toggle
              _LayoutToggle(current: layout, onChange: onLayoutChange),
              const Spacer(),
              // Upload
              TextButton.icon(
                icon: const Icon(Icons.upload_file_outlined, size: 16),
                label: const Text('Upload'),
                onPressed: onUpload,
                style: TextButton.styleFrom(
                  foregroundColor: scheme.primary,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
        ),

        // ── Content ──────────────────────────────────────────────────────────
        Expanded(
          child: loading
              ? const Center(child: CircularProgressIndicator())
              : assets.isEmpty
                  ? Center(child: Text('No files in ${dir!.name}', style: TextStyle(color: scheme.outline)))
                  : switch (layout) {
                      _AssetLayout.list      => _buildList(context),
                      _AssetLayout.listThumb => _buildListThumb(context),
                      _AssetLayout.grid      => _buildGrid(context),
                    },
        ),
      ],
    );
  }

  Widget _buildList(BuildContext context) => ListView.builder(
    itemCount: assets.length,
    itemBuilder: (_, i) => _AssetRow(
      asset: assets[i], dir: dir!, storeName: storeName,
      showThumb: false,
      onDelete: () => onDelete(assets[i]),
      onCopyUrl: () => onCopyUrl(assets[i]),
    ),
  );

  Widget _buildListThumb(BuildContext context) => ListView.builder(
    itemCount: assets.length,
    itemBuilder: (_, i) => _AssetRow(
      asset: assets[i], dir: dir!, storeName: storeName,
      showThumb: true,
      onDelete: () => onDelete(assets[i]),
      onCopyUrl: () => onCopyUrl(assets[i]),
    ),
  );

  Widget _buildGrid(BuildContext context) => GridView.builder(
    padding: const EdgeInsets.all(12),
    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: 160,
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 0.82,
    ),
    itemCount: assets.length,
    itemBuilder: (_, i) => _AssetCard(
      asset: assets[i], dir: dir!, storeName: storeName,
      onDelete: () => onDelete(assets[i]),
      onCopyUrl: () => onCopyUrl(assets[i]),
    ),
  );
}

// ── Layout toggle ──────────────────────────────────────────────────────────────

class _LayoutToggle extends StatelessWidget {
  final _AssetLayout current;
  final ValueChanged<_AssetLayout> onChange;

  const _LayoutToggle({required this.current, required this.onChange});

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<_AssetLayout>(
      style: SegmentedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        iconSize: 16,
      ),
      segments: const [
        ButtonSegment(value: _AssetLayout.list,      icon: Icon(Icons.view_list_outlined)),
        ButtonSegment(value: _AssetLayout.listThumb, icon: Icon(Icons.view_agenda_outlined)),
        ButtonSegment(value: _AssetLayout.grid,      icon: Icon(Icons.grid_view_outlined)),
      ],
      selected: {current},
      onSelectionChanged: (s) => onChange(s.first),
      showSelectedIcon: false,
    );
  }
}

// ── Asset row (list + listThumb modes) ────────────────────────────────────────

class _AssetRow extends StatelessWidget {
  final ResourceAsset asset;
  final ResourceDirectory dir;
  final String storeName;
  final bool showThumb;
  final VoidCallback onDelete;
  final VoidCallback onCopyUrl;

  const _AssetRow({
    required this.asset, required this.dir, required this.storeName,
    required this.showThumb, required this.onDelete, required this.onCopyUrl,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    Widget leading;
    if (showThumb) {
      leading = _AssetThumb(
        asset: asset, storeName: storeName, dirName: dir.name, size: 52,
      );
    } else {
      leading = Icon(
        _typeIcon(asset),
        color: scheme.primary,
        size: 22,
      );
    }

    return ListTile(
      leading: leading,
      title: Text(asset.name, overflow: TextOverflow.ellipsis),
      subtitle: Text('${_fmtSize(asset.sizeBytes)} · ${asset.mimeType}',
          style: TextStyle(color: scheme.outline, fontSize: 11)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(icon: const Icon(Icons.copy_outlined, size: 18), tooltip: 'Copy URL', onPressed: onCopyUrl),
          IconButton(icon: Icon(Icons.delete_outline, size: 18, color: scheme.error), tooltip: 'Delete', onPressed: onDelete),
        ],
      ),
      onTap: () => _openPreview(context, asset, dir, storeName),
    );
  }
}

// ── Asset card (grid mode) ─────────────────────────────────────────────────────

class _AssetCard extends StatelessWidget {
  final ResourceAsset asset;
  final ResourceDirectory dir;
  final String storeName;
  final VoidCallback onDelete;
  final VoidCallback onCopyUrl;

  const _AssetCard({
    required this.asset, required this.dir, required this.storeName,
    required this.onDelete, required this.onCopyUrl,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () => _openPreview(context, asset, dir, storeName),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
              child: Container(
                color: scheme.surfaceContainerHighest,
                child: _AssetThumb(
                  asset: asset, storeName: storeName, dirName: dir.name,
                  size: 140, fit: BoxFit.cover,
                ),
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: scheme.surface,
              border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(asset.name,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11)),
                ),
                GestureDetector(
                  onTap: onCopyUrl,
                  child: Icon(Icons.copy_outlined, size: 13, color: scheme.outline),
                ),
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: onDelete,
                  child: Icon(Icons.delete_outline, size: 13, color: scheme.error),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Asset thumbnail ────────────────────────────────────────────────────────────

Widget _assetFallbackIcon(ResourceAsset asset, ColorScheme scheme, double size) {
  Color bg;
  Color fg;
  IconData icon;
  if (asset.isHtml) {
    bg = scheme.primaryContainer;
    fg = scheme.primary;
    icon = Icons.html_outlined;
  } else if (asset.mimeType.startsWith('video/')) {
    bg = scheme.secondaryContainer;
    fg = scheme.secondary;
    icon = Icons.videocam_outlined;
  } else if (asset.mimeType == 'application/pdf') {
    bg = scheme.errorContainer;
    fg = scheme.error;
    icon = Icons.picture_as_pdf_outlined;
  } else {
    bg = scheme.surfaceContainerHighest;
    fg = scheme.outline;
    icon = Icons.insert_drive_file_outlined;
  }
  return Container(
    width: size, height: size,
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
    child: Icon(icon, color: fg, size: size * 0.5),
  );
}

class _AssetThumb extends StatelessWidget {
  final ResourceAsset asset;
  final String storeName;
  final String dirName;
  final double size;
  final BoxFit fit;

  const _AssetThumb({
    required this.asset, required this.storeName, required this.dirName,
    this.size = 40, this.fit = BoxFit.cover,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (asset.isImage) {
      final url = '${AppConfig.apiBaseUrl}${asset.publicUrl(storeName, dirName)}';
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.network(
          url,
          width: size, height: size, fit: fit,
          errorBuilder: (_, __, ___) => _assetFallbackIcon(asset, scheme, size),
        ),
      );
    }

    return _assetFallbackIcon(asset, scheme, size);
  }
}

// ── Preview dialog ─────────────────────────────────────────────────────────────

void _openPreview(BuildContext context, ResourceAsset asset,
    ResourceDirectory dir, String storeName) {
  showDialog<void>(
    context: context,
    builder: (_) => _PreviewDialog(asset: asset, dir: dir, storeName: storeName),
  );
}

class _PreviewDialog extends StatefulWidget {
  final ResourceAsset asset;
  final ResourceDirectory dir;
  final String storeName;

  const _PreviewDialog({
    required this.asset, required this.dir, required this.storeName,
  });

  @override
  State<_PreviewDialog> createState() => _PreviewDialogState();
}

class _PreviewDialogState extends State<_PreviewDialog> {
  _PreviewLayout _layout = _PreviewLayout.fitWidth;

  String get _url =>
      '${AppConfig.apiBaseUrl}${widget.asset.publicUrl(widget.storeName, widget.dir.name)}';

  void _copyUrl() {
    Clipboard.setData(ClipboardData(text: _url));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Copied: $_url')),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final screen = MediaQuery.of(context).size;

    // Dialog dimensions based on layout mode.
    double? dialogWidth;
    double? dialogHeight;
    switch (_layout) {
      case _PreviewLayout.fullscreen:
        dialogWidth  = screen.width  - 16;
        dialogHeight = screen.height - 16;
      case _PreviewLayout.fitHeight:
        dialogHeight = screen.height * 0.85;
        dialogWidth  = null; // will shrink-wrap or expand
      case _PreviewLayout.fitWidth:
        dialogWidth  = screen.width  * 0.88;
        dialogHeight = null;
    }

    return Dialog(
      insetPadding: const EdgeInsets.all(8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width:  dialogWidth,
          height: dialogHeight,
          child: Column(
            mainAxisSize: _layout == _PreviewLayout.fitWidth ? MainAxisSize.min : MainAxisSize.max,
            children: [
              // Toolbar
              Container(
                color: scheme.surfaceContainerHighest,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(widget.asset.name,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    ),
                    const SizedBox(width: 8),
                    _PreviewLayoutToggle(
                      current: _layout,
                      onChange: (l) => setState(() => _layout = l),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.copy_outlined, size: 18),
                      tooltip: 'Copy URL',
                      visualDensity: VisualDensity.compact,
                      onPressed: _copyUrl,
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      tooltip: 'Close',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),

              // Content
              if (widget.asset.isImage)
                _ImageContent(url: _url, layout: _layout, height: dialogHeight)
              else
                _FileContent(asset: widget.asset, url: _url),

              // URL bar
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                color: scheme.surfaceContainerLowest,
                child: SelectableText(_url,
                    style: TextStyle(
                        fontFamily: 'monospace', fontSize: 11, color: scheme.outline)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ImageContent extends StatelessWidget {
  final String url;
  final _PreviewLayout layout;
  final double? height;

  const _ImageContent({required this.url, required this.layout, this.height});

  @override
  Widget build(BuildContext context) {
    final isExpanded = layout != _PreviewLayout.fitWidth;
    final imgWidget = InteractiveViewer(
      minScale: 0.5,
      maxScale: 4.0,
      child: Image.network(
        url,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) =>
            const Center(child: Text('Image unavailable')),
      ),
    );

    return isExpanded
        ? Expanded(child: imgWidget)
        : ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.6,
            ),
            child: imgWidget,
          );
  }
}

class _FileContent extends StatelessWidget {
  final ResourceAsset asset;
  final String url;

  const _FileContent({required this.asset, required this.url});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _assetFallbackIcon(asset, scheme, 80),
          const SizedBox(height: 16),
          Text(asset.name,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
          const SizedBox(height: 4),
          Text('${_fmtSize(asset.sizeBytes)} · ${asset.mimeType}',
              style: TextStyle(color: scheme.outline, fontSize: 12)),
        ],
      ),
    );
  }
}

class _PreviewLayoutToggle extends StatelessWidget {
  final _PreviewLayout current;
  final ValueChanged<_PreviewLayout> onChange;

  const _PreviewLayoutToggle({required this.current, required this.onChange});

  @override
  Widget build(BuildContext context) => SegmentedButton<_PreviewLayout>(
    style: SegmentedButton.styleFrom(
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      iconSize: 14,
    ),
    segments: const [
      ButtonSegment(value: _PreviewLayout.fitWidth,    icon: Icon(Icons.fit_screen_outlined),    tooltip: 'Fit width'),
      ButtonSegment(value: _PreviewLayout.fitHeight,   icon: Icon(Icons.height_outlined),         tooltip: 'Fit height'),
      ButtonSegment(value: _PreviewLayout.fullscreen,  icon: Icon(Icons.fullscreen_outlined),     tooltip: 'Full screen'),
    ],
    selected: {current},
    onSelectionChanged: (s) => onChange(s.first),
    showSelectedIcon: false,
  );
}

// ── Helpers ────────────────────────────────────────────────────────────────────

IconData _typeIcon(ResourceAsset asset) {
  if (asset.isImage) return Icons.image_outlined;
  if (asset.isHtml) return Icons.html_outlined;
  if (asset.mimeType.startsWith('video/')) return Icons.videocam_outlined;
  if (asset.mimeType == 'application/pdf') return Icons.picture_as_pdf_outlined;
  return Icons.insert_drive_file_outlined;
}

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
    'png'           => 'image/png',
    'gif'           => 'image/gif',
    'webp'          => 'image/webp',
    'svg'           => 'image/svg+xml',
    'html' || 'htm' => 'text/html',
    'css'           => 'text/css',
    'js'            => 'application/javascript',
    'pdf'           => 'application/pdf',
    'mp4'           => 'video/mp4',
    _               => 'application/octet-stream',
  };
}
