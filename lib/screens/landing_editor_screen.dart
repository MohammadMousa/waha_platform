import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../config/app_config.dart';
import '../services/api_client.dart';
import '../state/auth_service.dart';
import '../state/store_config_service.dart';
import '../widgets/product_image.dart';
import '../widgets/resource_picker_sheet.dart';

/// Template type — only Screensaver for now; more to follow.
enum _Template { screensaver }

class LandingEditorScreen extends StatefulWidget {
  const LandingEditorScreen({super.key});

  @override
  State<LandingEditorScreen> createState() => _LandingEditorScreenState();
}

class _LandingEditorScreenState extends State<LandingEditorScreen> {
  final _template = _Template.screensaver;

  // Each slide: resourceId (for thumbnail) + publicUrl (embedded in HTML)
  final List<_Slide> _slides = [];

  int _slideSec = 5;
  bool _initializing = true;  // loading spinner on first open
  bool _existingLoaded = false; // true when we successfully parsed an existing page
  bool _saving = false;
  String? _error;
  String? _savedMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadExisting());
  }

  // ── Load existing page ────────────────────────────────────────────────────

  Future<void> _loadExisting() async {
    final slug = storeConfigService.storeSlug;
    if (slug == null) { if (mounted) setState(() => _initializing = false); return; }

    try {
      final uri = Uri.parse('${AppConfig.apiBaseUrl}/resource/$slug/$_pagesDir/$_filename');
      final resp = await http.get(uri);
      if (resp.statusCode == 200) {
        _parseExistingHtml(utf8.decode(resp.bodyBytes));
        _existingLoaded = true;
      }
    } catch (_) {}

    if (mounted) setState(() => _initializing = false);
  }

  void _parseExistingHtml(String html) {
    // Restore slide-sec setting
    final secM = RegExp(r'data-slide-sec="(\d+)"').firstMatch(html);
    if (secM != null) _slideSec = int.tryParse(secM.group(1)!) ?? _slideSec;

    // Each slide: <div class="slide" data-rid="123"><img src="..." ...>
    final slideRe = RegExp(r'<div class="slide" data-rid="(\d+)"><img src="([^"]+)"');
    for (final m in slideRe.allMatches(html)) {
      final rid = int.tryParse(m.group(1)!);
      final src = m.group(2)!;
      if (rid != null) _slides.add(_Slide(resourceId: rid, publicUrl: src));
    }
  }

  // ── Add slide ─────────────────────────────────────────────────────────────

  Future<void> _addSlide() async {
    final picked = await showResourcePickerSheet(context);
    if (picked == null || !mounted) return;
    setState(() => _slides.add(_Slide(
          resourceId: picked.resourceId,
          publicUrl: picked.publicUrl,
        )));
  }

  // ── Generate HTML ─────────────────────────────────────────────────────────

  String _buildHtml(String storeSlug) {
    final slideHtml = _slides.map((s) {
      final src = s.publicUrl.isNotEmpty
          ? s.publicUrl
          : '${AppConfig.apiBaseUrl}/api/resources/${s.resourceId}';
      // data-rid lets the editor reload and reconstruct the slide list
      return '  <div class="slide" data-rid="${s.resourceId}"><img src="$src" loading="eager" alt=""></div>';
    }).join('\n');

    final slideSec = _slideSec;

    return '''<!DOCTYPE html>
<html lang="ar">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1,user-scalable=no">
<title>$storeSlug</title>
<style>
*{margin:0;padding:0;box-sizing:border-box}
html,body{width:100%;height:100%;overflow:hidden;background:#000;touch-action:none}
.slide{position:absolute;inset:0;transform:translateX(100%)}
.slide img{width:100%;height:100%;object-fit:cover;display:block}
.tap{position:fixed;inset:0;z-index:99;cursor:pointer;-webkit-tap-highlight-color:transparent}
</style>
</head>
<body>
<div id="reel" data-slide-sec="$slideSec" style="position:relative;width:100%;height:100%">
$slideHtml
</div>
<a class="tap" href="/screen?name=browse_screen"></a>
<script>
(function(){
  var slides=Array.from(document.querySelectorAll('.slide'));
  if(!slides.length)return;
  var dur=parseInt(document.getElementById('reel').dataset.slideSec||'5',10)*1000;
  var t=700;
  var cur=0;
  slides[0].style.transform='translateX(0)';
  function advance(){
    var nxt=(cur+1)%slides.length;
    var old=cur;
    // snap next into position off-screen right (no animation)
    slides[nxt].style.transition='none';
    slides[nxt].style.transform='translateX(100%)';
    // force reflow so the snap takes effect before we re-enable transition
    slides[nxt].getBoundingClientRect();
    // slide both simultaneously
    slides[old].style.transition='transform '+t+'ms ease-in-out';
    slides[nxt].style.transition='transform '+t+'ms ease-in-out';
    slides[old].style.transform='translateX(-100%)';
    slides[nxt].style.transform='translateX(0)';
    cur=nxt;
    // after transition, park old slide off-screen right so it's ready next cycle
    setTimeout(function(){
      slides[old].style.transition='none';
      slides[old].style.transform='translateX(100%)';
    },t+50);
    setTimeout(advance,dur);
  }
  setTimeout(advance,dur);
})();
</script>
</body>
</html>''';
  }

  // ── Save to backend ────────────────────────────────────────────────────────

  static const _pagesDir = 'pages';
  static const _filename = 'KIOSK_LANDING.html';

  Future<void> _save() async {
    if (_slides.isEmpty) {
      setState(() => _error = 'Add at least one image first.');
      return;
    }
    final slug = storeConfigService.storeSlug;
    final token = authService.token;
    if (slug == null || token == null) {
      setState(() => _error = 'No active store selected.');
      return;
    }

    // If the user started fresh (didn't load an existing page), check whether
    // one already exists on the server and ask before overwriting.
    if (!_existingLoaded) {
      final exists = await _pageExistsOnServer(slug);
      if (!mounted) return;
      if (exists) {
        final overwrite = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Replace existing page?'),
            content: const Text(
                'A landing page already exists. Saving will replace it permanently.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Replace')),
            ],
          ),
        );
        if (overwrite != true || !mounted) return;
      }
    }

    setState(() { _saving = true; _error = null; _savedMessage = null; });
    final api = context.read<ApiClient>();

    try {
      try { await api.createDirectory(slug, _pagesDir, token); } catch (_) {}

      final html = _buildHtml(slug);
      final bytes = utf8.encode(html);
      await api.uploadAsset(slug, _pagesDir, bytes, _filename, 'text/html', token,
          nameOverride: _filename);

      if (!mounted) return;
      // After a successful save the page is "loaded" — no confirm on next save.
      setState(() {
        _existingLoaded = true;
        _savedMessage = 'Saved — reload the kiosk landing screen to see changes.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool> _pageExistsOnServer(String slug) async {
    try {
      final uri = Uri.parse('${AppConfig.apiBaseUrl}/resource/$slug/$_pagesDir/$_filename');
      final resp = await http.head(uri);
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // ── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(_existingLoaded ? 'Edit Landing Page' : 'Landing Page Editor'),
        actions: [
          if (!_initializing)
            TextButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Save'),
            ),
        ],
      ),
      body: _initializing
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
        children: [
          // ── Template chip (only one for now) ──────────────────────────
          _SectionLabel('Template'),
          const SizedBox(height: 8),
          _TemplateCard(
            icon: Icons.slideshow_outlined,
            title: 'Image Screensaver',
            subtitle: 'Full-screen image loop — tap anywhere to start shopping',
            selected: _template == _Template.screensaver,
          ),
          const SizedBox(height: 24),

          // ── Slides list ───────────────────────────────────────────────
          Row(
            children: [
              _SectionLabel('Slides'),
              const Spacer(),
              TextButton.icon(
                icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
                label: const Text('Add image'),
                onPressed: _addSlide,
              ),
            ],
          ),
          const SizedBox(height: 8),

          if (_slides.isEmpty)
            Container(
              height: 120,
              decoration: BoxDecoration(
                border: Border.all(
                    color: scheme.outlineVariant,
                    style: BorderStyle.solid),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.image_outlined,
                        size: 36, color: scheme.outlineVariant),
                    const SizedBox(height: 8),
                    Text('No images yet — tap Add image',
                        style: TextStyle(color: scheme.outline)),
                  ],
                ),
              ),
            )
          else
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _slides.length,
              onReorderItem: (oldIdx, newIdx) {
                setState(() {
                  final s = _slides.removeAt(oldIdx);
                  _slides.insert(newIdx, s);
                });
              },
              itemBuilder: (_, i) {
                final slide = _slides[i];
                return _SlideRow(
                  key: ValueKey(slide),
                  index: i,
                  slide: slide,
                  onDelete: () => setState(() => _slides.removeAt(i)),
                );
              },
            ),

          const SizedBox(height: 24),

          // ── Settings ──────────────────────────────────────────────────
          _SectionLabel('Settings'),
          const SizedBox(height: 12),
          _SettingsCard(
            slideSec: _slideSec,
            onSlideSecChanged: (v) => setState(() => _slideSec = v),
          ),

          // ── Status messages ───────────────────────────────────────────
          if (_error != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.errorContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(_error!,
                  style: TextStyle(color: scheme.onErrorContainer, fontSize: 13)),
            ),
          ],
          if (_savedMessage != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_outline,
                      color: Colors.green, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(_savedMessage!,
                        style: const TextStyle(
                            color: Colors.green, fontSize: 13)),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 40),

          // ── Preview strip ─────────────────────────────────────────────
          if (_slides.isNotEmpty) ...[
            _SectionLabel('Preview — 9:16 aspect ratio'),
            const SizedBox(height: 8),
            _ScreensaverPreview(slides: _slides),
            const SizedBox(height: 32),
          ],
        ],
      ),
    );
  }
}

// ── Data ──────────────────────────────────────────────────────────────────────

class _Slide {
  final int resourceId;
  final String publicUrl;
  const _Slide({required this.resourceId, required this.publicUrl});
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
      );
}

class _TemplateCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  const _TemplateCard(
      {required this.icon,
      required this.title,
      required this.subtitle,
      required this.selected});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: selected ? scheme.primaryContainer : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: selected ? scheme.primary : Colors.transparent, width: 2),
      ),
      child: Row(
        children: [
          Icon(icon, color: selected ? scheme.primary : scheme.onSurfaceVariant),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: selected
                            ? scheme.onPrimaryContainer
                            : scheme.onSurface)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: TextStyle(
                        fontSize: 12,
                        color: selected
                            ? scheme.onPrimaryContainer.withValues(alpha: 0.7)
                            : scheme.outline)),
              ],
            ),
          ),
          if (selected)
            Icon(Icons.check_circle, color: scheme.primary, size: 20),
        ],
      ),
    );
  }
}

class _SlideRow extends StatelessWidget {
  final int index;
  final _Slide slide;
  final VoidCallback onDelete;
  const _SlideRow(
      {super.key,
      required this.index,
      required this.slide,
      required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: ProductImage(
            imageResourceId: slide.resourceId,
            width: 52,
            height: 52,
          ),
        ),
        title: Text('Slide ${index + 1}',
            style: const TextStyle(fontWeight: FontWeight.w500)),
        subtitle: Text(
          slide.publicUrl,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 11, color: scheme.outline),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.drag_handle, color: scheme.outline),
            const SizedBox(width: 4),
            IconButton(
              icon: Icon(Icons.close, color: scheme.error, size: 18),
              onPressed: onDelete,
              tooltip: 'Remove',
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  final int slideSec;
  final ValueChanged<int> onSlideSecChanged;

  const _SettingsCard({
    required this.slideSec,
    required this.onSlideSecChanged,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          _SettingRow(
            label: 'Slide duration',
            value: slideSec,
            unit: 'sec',
            min: 2,
            max: 30,
            onChanged: onSlideSecChanged,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.touch_app_outlined, size: 16, color: scheme.outline),
              const SizedBox(width: 6),
              Text('Tap anywhere → Browse screen',
                  style: TextStyle(fontSize: 12, color: scheme.outline)),
            ],
          ),
        ],
      ),
    );
  }
}

class _SettingRow extends StatelessWidget {
  final String label;
  final int value;
  final String unit;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  const _SettingRow({
    required this.label,
    required this.value,
    required this.unit,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(child: Text(label, style: const TextStyle(fontSize: 14))),
        IconButton(
          icon: const Icon(Icons.remove_circle_outline),
          onPressed: value > min ? () => onChanged(value - 1) : null,
          color: scheme.primary,
          padding: EdgeInsets.zero,
        ),
        SizedBox(
          width: 48,
          child: Text(
            '$value $unit',
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.add_circle_outline),
          onPressed: value < max ? () => onChanged(value + 1) : null,
          color: scheme.primary,
          padding: EdgeInsets.zero,
        ),
      ],
    );
  }
}

/// Animated preview of the screensaver at correct 9:16 ratio.
class _ScreensaverPreview extends StatefulWidget {
  final List<_Slide> slides;
  const _ScreensaverPreview({required this.slides});

  @override
  State<_ScreensaverPreview> createState() => _ScreensaverPreviewState();
}

class _ScreensaverPreviewState extends State<_ScreensaverPreview> {
  late final PageController _pageCtrl;
  Timer? _timer;
  int _page = 0;

  static const _transitionMs = 700;
  static const _pauseSec = 3;

  @override
  void initState() {
    super.initState();
    _pageCtrl = PageController();
    _scheduleNext();
  }

  void _scheduleNext() {
    _timer?.cancel();
    if (widget.slides.length < 2) return;
    _timer = Timer(const Duration(seconds: _pauseSec), _advance);
  }

  void _advance() {
    if (!mounted) return;
    _page = (_page + 1) % widget.slides.length;
    _pageCtrl.animateToPage(
      _page,
      duration: const Duration(milliseconds: _transitionMs),
      curve: Curves.easeInOut,
    );
    _scheduleNext();
  }

  @override
  void didUpdateWidget(_ScreensaverPreview old) {
    super.didUpdateWidget(old);
    // If slides changed, reset to first slide
    if (old.slides != widget.slides) {
      _page = 0;
      _pageCtrl.jumpToPage(0);
      _scheduleNext();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 200),
        child: AspectRatio(
          aspectRatio: 9 / 16,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Container(color: Colors.black),
                PageView.builder(
                  controller: _pageCtrl,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: widget.slides.length,
                  itemBuilder: (_, i) => ProductImage(
                    imageResourceId: widget.slides[i].resourceId,
                    width: double.infinity,
                    height: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
                Positioned(
                  bottom: 12, left: 0, right: 0,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.touch_app,
                              size: 12,
                              color: Colors.white.withValues(alpha: 0.8)),
                          const SizedBox(width: 4),
                          Text('tap → browse',
                              style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.8),
                                  fontSize: 10)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
