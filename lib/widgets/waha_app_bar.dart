import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/generated/app_localizations.dart';
import '../state/browsing_mode_service.dart';
import '../state/locale_service.dart';
import 'profile_sheet.dart';

/// App bar — profile icon for Normal mode, language toggle for Kiosk/Shopping.
/// Pass [extraActions] to prepend additional action widgets (e.g. EditModeToggle).
class WahaAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final List<Widget> extraActions;
  const WahaAppBar({super.key, required this.title, this.extraActions = const []});

  @override
  Widget build(BuildContext context) {
    final mode = context.watch<BrowsingModeService>().mode;
    final isNormal = mode == BrowsingMode.normal;
    final l10n = AppLocalizations.of(context)!;

    return AppBar(
      title: Text(title),
      actions: [
        ...extraActions,
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
        if (!isNormal)
          const _LangToggleButton(),
      ],
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}

/// Compact language toggle for kiosk/shopping — shows the OTHER language
/// so the user immediately knows what they're switching to.
class _LangToggleButton extends StatelessWidget {
  const _LangToggleButton();

  @override
  Widget build(BuildContext context) {
    final locale = context.watch<LocaleService>().locale;
    final isAr = locale.languageCode == 'ar';
    // Show the label of the OTHER language (what they'll switch to)
    final label = isAr ? 'EN' : 'عربي';

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: TextButton(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 36),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        onPressed: () {
          localeService.setLocale(isAr ? const Locale('en') : const Locale('ar'));
        },
        child: Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        ),
      ),
    );
  }
}
