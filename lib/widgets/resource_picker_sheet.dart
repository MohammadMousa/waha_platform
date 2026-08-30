import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../screens/resource_picker_modal.dart';
import '../services/api_client.dart';
import '../state/auth_service.dart';
import '../state/store_config_service.dart';
import 'save_resource_dialog.dart';

class PickedResource {
  final int resourceId;
  final String publicUrl;
  const PickedResource({required this.resourceId, required this.publicUrl});
}

/// Opens a bottom sheet with Camera / Gallery / Resource Manager options.
/// Returns the selected [PickedResource], or null if the user cancels.
Future<PickedResource?> showResourcePickerSheet(BuildContext context) async {
  final slug = context.read<StoreConfigService>().storeSlug;
  final token = authService.token;
  if (slug == null || token == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No active store — select a store first.')),
    );
    return null;
  }

  return showModalBottomSheet<PickedResource>(
    context: context,
    builder: (ctx) => _Sheet(storeSlug: slug, token: token),
  );
}

class _Sheet extends StatelessWidget {
  final String storeSlug;
  final String token;
  const _Sheet({required this.storeSlug, required this.token});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            _Tile(
              icon: Icons.camera_alt_outlined,
              label: 'Camera',
              onTap: () => _pick(context, ImageSource.camera),
            ),
            _Tile(
              icon: Icons.photo_library_outlined,
              label: 'Gallery',
              onTap: () => _pick(context, ImageSource.gallery),
            ),
            _Tile(
              icon: Icons.folder_open_outlined,
              label: 'Resource Manager',
              onTap: () => _pickFromResources(context),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _pick(BuildContext context, ImageSource source) async {
    final nav = Navigator.of(context);
    final client = context.read<ApiClient>();

    final xfile = await ImagePicker().pickImage(source: source, imageQuality: 85);
    if (xfile == null) { nav.pop(null); return; }
    if (!context.mounted) { nav.pop(null); return; }

    final result = await showDialog<PickedResource>(
      context: context,
      builder: (_) => SaveResourceDialog(
        file: xfile,
        storeSlug: storeSlug,
        token: token,
        client: client,
      ),
    );
    nav.pop(result);
  }

  Future<void> _pickFromResources(BuildContext context) async {
    final nav = Navigator.of(context);
    final result = await showDialog<PickedResource>(
      context: context,
      builder: (_) => ResourcePickerModal(storeSlug: storeSlug, token: token),
    );
    nav.pop(result);
  }
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _Tile({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
      title: Text(label),
      onTap: onTap,
    );
  }
}
