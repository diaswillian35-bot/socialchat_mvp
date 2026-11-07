import 'package:flutter/material.dart';
import '../../../l10n/app_texts.dart';
import '../data/place_description_translation_service.dart';
import 'locais_layout.dart';

/// Preserves the existing description text style; uses the existing TextButton link.
class PlaceDescription extends StatefulWidget {
  const PlaceDescription(
      {super.key,
      required this.placeId,
      required this.original,
      this.service,
      this.locale});
  final String placeId;
  final String original;
  final PlaceDescriptionTranslationService? service;
  final Locale? locale;
  @override
  State<PlaceDescription> createState() => _PlaceDescriptionState();
}

class _PlaceDescriptionState extends State<PlaceDescription>
    with WidgetsBindingObserver {
  String? _key;
  String? _translation;
  bool _original = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeLocales(List<Locale>? locales) {
    if (mounted && widget.locale == null) setState(_load);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
  }

  @override
  void didUpdateWidget(PlaceDescription oldWidget) {
    super.didUpdateWidget(oldWidget);
    _load();
  }

  void _load() {
    final locale = widget.locale ?? View.of(context).platformDispatcher.locale;
    final key =
        '${widget.placeId}/${locale.toLanguageTag()}/${widget.original}';
    if (_key == key) return;
    _key = key;
    _translation = null;
    _original = false;
    final generation = ++_generation;
    (widget.service ?? PlaceDescriptionTranslationService.shared)
        .load(widget.placeId, widget.original, locale)
        .then((text) {
      if (!mounted || generation != _generation) return;
      setState(() => _translation = text == widget.original ? null : text);
    });
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
              !_original && _translation != null
                  ? _translation!
                  : widget.original,
              key: const Key('place_description_text'),
              style: const TextStyle(color: LocaisColors.text, height: 1.4)),
          if (_translation != null)
            TextButton(
              key: const Key('place_description_toggle'),
              onPressed: () => setState(() => _original = !_original),
              child: Text(AppTexts.t(_original
                  ? 'place_view_translation'
                  : 'place_view_original')),
            ),
        ],
      );
}
