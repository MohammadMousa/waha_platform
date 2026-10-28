import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/locale_service.dart';

/// App bar — language toggle. Pass [extraActions] to prepend additional
/// action widgets.
class WahaAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final List<Widget> extraActions;
  // Off lets a caller swap in its own language control (e.g. Browse uses the
  // plain globe-icon style from cart_screen.dart instead) without also
  // showing this one — keeps the change scoped to that one screen rather
  // than restyling every WahaAppBar user.
  final bool showLangToggle;
  const WahaAppBar({
    super.key,
    required this.title,
    this.extraActions = const [],
    this.showLangToggle = true,
  });

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: Text(title),
      actions: [
        ...extraActions,
        if (showLangToggle) const _LangToggleButton(),
      ],
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}

/// Compact language toggle — shows the OTHER language
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
