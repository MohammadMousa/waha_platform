import 'package:flutter/material.dart';

/// (i) button that opens the full explanation, so tiles and sections can keep
/// to one major line and one minor line.
class InfoButton extends StatelessWidget {
  final String title;
  final String text;
  const InfoButton({required this.title, required this.text, super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.info_outline, size: 18),
      tooltip: 'More info',
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      onPressed: () => showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(child: Text(text)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tile title followed by an (i) button — for switches/checkboxes, whose
/// trailing slot is taken by the control itself.
class TitleWithInfo extends StatelessWidget {
  final String title;
  final String info;
  const TitleWithInfo(this.title, this.info, {super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Flexible(
          child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        InfoButton(title: title, text: info),
      ],
    );
  }
}

/// Section heading (one line) followed by an (i) button.
class HeaderWithInfo extends StatelessWidget {
  final String title;
  final String info;
  final TextStyle? style;
  const HeaderWithInfo(this.title, this.info, {this.style, super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Flexible(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style ?? const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        InfoButton(title: title, text: info),
      ],
    );
  }
}

/// Trailing (i) button, plus the chevron for tiles that open something.
class InfoTrailing extends StatelessWidget {
  final String title;
  final String text;
  final bool chevron;
  const InfoTrailing(
      {required this.title,
      required this.text,
      required this.chevron,
      super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        InfoButton(title: title, text: text),
        if (chevron) const Icon(Icons.chevron_right),
      ],
    );
  }
}
