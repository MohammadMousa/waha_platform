import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/generated/app_localizations.dart';
import '../state/browsing_mode_service.dart';
import 'profile_sheet.dart';

/// App bar — profile icon for Normal mode (opens bottom sheet).
class WahaAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  const WahaAppBar({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    final mode = context.watch<BrowsingModeService>().mode;
    final isNormal = mode == BrowsingMode.normal;
    final l10n = AppLocalizations.of(context)!;

    return AppBar(
      title: Text(title),
      actions: [
        if (isNormal)
          IconButton(
            tooltip: l10n.profileTitle,
            icon: const Icon(Icons.person_outline),
            onPressed: () => showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              builder: (_) => const ProfileSheet(),
            ),
          ),
      ],
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
