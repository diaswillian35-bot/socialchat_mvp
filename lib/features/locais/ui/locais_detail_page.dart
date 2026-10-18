import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/place_actions_service.dart';
import '../data/place_repository.dart';
import '../locais_feature_flag.dart';
import '../locais_strings.dart';
import '../logic/merchant_portal_plan.dart';
import '../models/place_listing.dart';
import '../../../widgets/events/event_detail_light_header.dart';
import 'locais_layout.dart';
import 'locais_state_views.dart';
import 'place_card.dart';
import 'place_photo_viewer.dart';

class LocaisDetailPage extends StatefulWidget {
  const LocaisDetailPage({
    super.key,
    required this.placeId,
    required this.repository,
    this.clock,
    PlaceActionsService? actions,
    this.launcher,
  }) : actions = actions ?? const PlaceActionsService();

  final String placeId;
  final PlaceRepository repository;
  final DateTime Function()? clock;
  final PlaceActionsService actions;

  /// Abre links externos; injetável nos testes. Padrão: url_launcher.
  final Future<bool> Function(Uri uri, LaunchMode mode)? launcher;

  @override
  State<LocaisDetailPage> createState() => _LocaisDetailPageState();
}

class _LocaisDetailPageState extends State<LocaisDetailPage> {
  PlaceListing? _place;
  bool _loading = true;
  bool _failed = false;
  int _photo = 0;
  bool _canManage = false;

  /// Ações de escrita (avaliar, responder como dono, portal/reivindicar)
  /// desligadas no app: dependem de funções ainda não publicadas e a gestão
  /// dos locais é feita pelo time Remdy no admin.
  static const bool _userWriteActionsEnabled = true;

  /// "Avaliar este local": ligado (submitPlaceReview/listPlaceReviews
  /// publicadas). Resposta do dono e reivindicação seguem desligadas.
  static const bool _reviewWriteEnabled = true;

  DateTime get _now => widget.clock?.call() ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    if (LocaisFeatureFlag.isEnabled) _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final results = await Future.wait<Object?>([
        widget.repository.fetchById(widget.placeId),
        widget.repository.canManage(widget.placeId),
      ]);
      final place = results[0] as PlaceListing?;
      if (!mounted) return;
      setState(() {
        _place = place;
        _canManage = results[1] == true;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!LocaisFeatureFlag.isEnabled) {
      return const Scaffold(body: SizedBox.shrink(key: Key('locais_disabled')));
    }
    final strings = LocaisStrings.of(context);
    final place = _place;
    final showHeader = !_loading && !_failed && place != null;
    return Scaffold(
      // Mesmo padrão do detalhe de evento: fundo branco, sem AppBar; o
      // título fica no cabeçalho com foto (EventDetailLightHeader).
      backgroundColor: _eventBg,
      appBar: showHeader
          ? null
          : AppBar(
              backgroundColor: _eventBg,
              foregroundColor: LocaisColors.navy,
              elevation: 0,
            ),
      body: _body(strings),
    );
  }

  Widget _body(LocaisStrings strings) {
    if (_loading) {
      return LocaisLoading(label: strings.loading);
    }
    if (_failed) {
      return LocaisError(
        title: strings.errorTitle,
        retryLabel: strings.retry,
        onRetry: _load,
      );
    }
    final place = _place;
    if (place == null) {
      return LocaisEmpty(title: strings.emptyTitle, body: strings.emptyBody);
    }
    final open = place.isOpenAt(_now);
    final wide = MediaQuery.sizeOf(context).width >= 700;
    return ListView(
      key: const Key('locais_detail_scroll'),
      padding: EdgeInsets.zero,
      children: [
        EventDetailLightHeader(
          key: const Key('locais_detail_title'),
          title: place.name,
          locationLine: '${place.address.city} · ${place.address.region}',
          dateLine: '',
          confirmed: false,
          cancelled: false,
          liked: false,
          confirmedLabel: '',
          cancelledLabel: '',
          coverChild: _photos(place, wide),
          onBack: () => Navigator.maybePop(context),
          showLike: false,
          pageBackground: _eventBg,
          heroHeight: wide ? 340 : 280,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: _details(strings, place, open),
          ),
        ),
      ],
    );
  }

  static const Color _eventBg = Colors.white;

  /// Cartão no padrão da aba "Sobre" do evento.
  Widget _card({required Key key, required Widget child}) {
    return Material(
      key: key,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: LocaisColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(padding: const EdgeInsets.all(14), child: child),
    );
  }

  List<Widget> _details(LocaisStrings strings, PlaceListing place, bool open) {
    return [
      Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            strings.categoryName(place.category).toUpperCase(),
            style: const TextStyle(
              color: LocaisColors.navy,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
          const Icon(Icons.star_rounded, size: 18, color: Color(0xFFF5B301)),
          Text(
            strings.ratingLine(place.rating, place.ratingCount),
            style: const TextStyle(
                fontWeight: FontWeight.w700, color: LocaisColors.muted),
          ),
          _pill(open ? strings.openNow : strings.closed, open),
        ],
      ),
      const SizedBox(height: 12),
      _card(
        key: const Key('locais_detail_description'),
        child: _section(strings.description, place.description),
      ),
      const SizedBox(height: 12),
      _card(
        key: const Key('locais_detail_address_card'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle(strings.address),
            Text(
              place.address.singleLine,
              key: const Key('locais_detail_address'),
              style: const TextStyle(
                color: LocaisColors.text,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              '${place.address.postalCode} · ${place.address.countryCode}',
              style: const TextStyle(color: LocaisColors.muted),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const Key('locais_route_button'),
                style: FilledButton.styleFrom(
                  backgroundColor: LocaisColors.navy,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(48, 46),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () => _open(Uri.parse(
                    'https://www.google.com/maps/dir/?api=1&destination=${place.address.latitude},${place.address.longitude}')),
                icon: const Icon(Icons.directions_outlined),
                label: Text(strings.route),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      _card(
          key: const Key('locais_detail_contact_card'),
          child: _contacts(strings, place)),
      const SizedBox(height: 12),
      _card(
          key: const Key('locais_detail_hours_card'),
          child: _hours(strings, place)),
      const SizedBox(height: 12),
      _card(
          key: const Key('locais_detail_access_card'),
          child: _accessibility(strings, place)),
      const SizedBox(height: 12),
      if (place.menu.enabled) ...[
        _card(
            key: const Key('locais_detail_menu_card'),
            child: _menu(strings, place)),
        const SizedBox(height: 12),
      ],
      // Avaliações: resumo + lista sempre visíveis (vazio: "Ainda sem avaliações"). Escrever avaliação
      // e o portal do comerciante ficam fora da tela do usuário (o time
      // Remdy cadastra e entrega as páginas aos donos pelo admin).
      ...[
        _card(
            key: const Key('locais_detail_reviews_card'),
            child: _reviews(strings, place)),
        const SizedBox(height: 12),
      ],
      _card(
          key: const Key('locais_detail_events_card'),
          child: _events(strings, place)),
      const SizedBox(height: 12),
      if (!_canManage) _merchant(strings, place),
      if (!_canManage) const SizedBox(height: 12),
      OutlinedButton.icon(
        key: const Key('place_report_button'),
        onPressed: () => _reportDialog(strings, place),
        icon: const Icon(Icons.flag_outlined),
        label: Text(strings.reportPlace),
      ),
      const SizedBox(height: 24),
    ];
  }

  Widget _menu(LocaisStrings strings, PlaceListing place) {
    final menu = place.menu;
    if (!menu.enabled) return const SizedBox.shrink();
    return Column(
      key: const Key('locais_detail_menu'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(strings.menu),
        if (menu.photoUrls.isNotEmpty)
          SizedBox(
            height: 150,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: menu.photoUrls.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) => Semantics(
                button: true,
                label: strings.openPhoto,
                child: GestureDetector(
                  key: Key('locais_menu_photo_$index'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () => showPlacePhotoViewer(
                    context,
                    photos: [
                      for (final url in menu.photoUrls)
                        PlaceViewerPhoto(
                            url: placeSafeImageUrl(url), label: strings.menu),
                    ],
                    initialIndex: index,
                    closeLabel: strings.close,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(menu.photoUrls[index],
                        width: 120,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const SizedBox(
                            width: 120,
                            child: Icon(Icons.broken_image_outlined))),
                  ),
                ),
              ),
            ),
          ),
        for (final item in menu.items)
          ListTile(
            contentPadding: EdgeInsets.zero,
            enabled: item.available,
            title: Text(item.name,
                style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle:
                Text(item.available ? item.description : strings.unavailable),
            trailing: item.price.isEmpty
                ? null
                : Text(item.price,
                    style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
        if (menu.pdfUrl != null)
          OutlinedButton.icon(
            key: const Key('locais_menu_pdf'),
            onPressed: () => _open(Uri.parse(menu.pdfUrl!)),
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: Text(strings.menuPdf),
          ),
        const SizedBox(height: 8),
        Text(menu.notice.isEmpty ? strings.menuNotice : menu.notice,
            style: const TextStyle(color: LocaisColors.muted, fontSize: 12)),
      ],
    );
  }

  Widget _photos(PlaceListing place, bool wide) {
    return Stack(
      key: const Key('locais_detail_photos'),
      fit: StackFit.expand,
      children: [
        PageView.builder(
          itemCount: place.photos.length,
          onPageChanged: (index) => setState(() => _photo = index),
          itemBuilder: (context, index) => GestureDetector(
            key: Key('locais_detail_photo_tap_$index'),
            behavior: HitTestBehavior.opaque,
            onTap: () => showPlacePhotoViewer(
              context,
              photos: [
                for (final photo in place.photos)
                  PlaceViewerPhoto(
                      url: placeSafeImageUrl(photo.url), label: photo.alt),
              ],
              initialIndex: index,
              closeLabel: LocaisStrings.of(context).close,
            ),
            child: PlaceCover(
              photo: place.photos[index],
              category: place.category,
            ),
          ),
        ),
        if (place.photos.length > 1)
          Positioned(
            left: 0,
            right: 0,
            bottom: 28,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < place.photos.length; i++)
                  Container(
                    width: 7,
                    height: 7,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i == _photo
                          ? LocaisColors.navy
                          : Colors.white.withValues(alpha: 0.8),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _contacts(LocaisStrings strings, PlaceListing place) {
    final contact = place.contact;
    final phone = contact.phone;
    final whatsapp = contact.whatsapp;
    final website = contact.website;
    final instagram = contact.instagram;
    final instagramUri = instagram == null ? null : _instagramUri(instagram);
    final rows = <Widget>[
      if (phone != null)
        _actionRow(
          key: const Key('locais_contact_phone'),
          icon: Icons.phone_rounded,
          label: strings.phone,
          value: phone,
          uri:
              Uri(scheme: 'tel', path: phone.replaceAll(RegExp(r'[^\d+]'), '')),
        ),
      if (whatsapp != null)
        _actionRow(
          key: const Key('locais_contact_whatsapp'),
          icon: Icons.chat_outlined,
          label: 'WhatsApp',
          value: whatsapp,
          uri: Uri.https(
              'wa.me', _whatsappDigits(whatsapp, place.address.countryCode)),
        ),
      if (website != null)
        _actionRow(
          key: const Key('locais_contact_website'),
          icon: Icons.language_rounded,
          label: strings.website,
          value: website.replaceFirst(RegExp(r'^https?://'), ''),
          uri: Uri.parse(website),
        ),
      if (instagram != null && instagramUri != null)
        _actionRow(
          key: const Key('locais_contact_instagram'),
          icon: Icons.alternate_email_rounded,
          label: strings.instagram,
          value: _instagramLabel(instagram),
          uri: instagramUri,
        ),
    ];
    return Column(
      key: const Key('locais_detail_contact'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(strings.contact),
        if (rows.isEmpty)
          Text(
            strings.emptyBody,
            style: const TextStyle(color: LocaisColors.muted),
          )
        else
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: LocaisColors.border),
            rows[i],
          ],
      ],
    );
  }

  /// wa.me exige o número com DDI. Números locais (sem DDI) recebem o do
  /// país do local: BR → 55, CA/US → 1.
  static String _whatsappDigits(String raw, String countryCode) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (raw.trim().startsWith('+')) return digits;
    final cc = countryCode.toUpperCase();
    if (cc == 'BR' && (digits.length == 10 || digits.length == 11)) {
      return '55$digits';
    }
    if ((cc == 'CA' || cc == 'US') && digits.length == 10) return '1$digits';
    return digits;
  }

  /// Aceita URL https do Instagram ou @usuario / usuario.
  static Uri? _instagramUri(String raw) {
    final text = raw.trim();
    final parsed = Uri.tryParse(text);
    if (parsed != null && parsed.scheme == 'https' && parsed.host.isNotEmpty) {
      return parsed;
    }
    final handle = text
        .replaceFirst(RegExp(r'^(https?://)?(www\.)?instagram\.com/'), '')
        .replaceFirst('@', '')
        .split(RegExp(r'[/?#\s]'))
        .first;
    if (!RegExp(r'^[A-Za-z0-9._]{1,30}$').hasMatch(handle)) return null;
    return Uri.https('www.instagram.com', '/$handle/');
  }

  static String _instagramLabel(String raw) {
    final uri = _instagramUri(raw);
    if (uri != null && uri.host.contains('instagram.com')) {
      final parts = uri.pathSegments.where((part) => part.isNotEmpty);
      if (parts.isNotEmpty) return '@${parts.first}';
    }
    return raw;
  }

  /// Abre fora do app. Se o app nativo não abrir, tenta o navegador padrão
  /// e, se nada abrir, avisa o usuário (nunca falha em silêncio).
  Future<void> _open(Uri uri) async {
    final launch = widget.launcher ??
        (Uri target, LaunchMode mode) => launchUrl(target, mode: mode);
    var opened = false;
    try {
      opened = await launch(uri, LaunchMode.externalApplication);
    } catch (_) {
      opened = false;
    }
    if (!opened && (uri.scheme == 'https' || uri.scheme == 'http')) {
      try {
        opened = await launch(uri, LaunchMode.platformDefault);
      } catch (_) {
        opened = false;
      }
    }
    if (!opened && mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(LocaisStrings.of(context).linkOpenFailed)),
      );
    }
  }

  /// Linha tocável no estilo das linhas de informação do evento: ícone navy,
  /// rótulo, valor e seta, com área de toque inteira (InkWell na Material do
  /// cartão).
  Widget _actionRow({
    required Key key,
    required IconData icon,
    required String label,
    required String value,
    required Uri uri,
  }) {
    return Semantics(
      button: true,
      label: '$label, $value',
      excludeSemantics: true,
      child: InkWell(
        key: key,
        borderRadius: BorderRadius.circular(12),
        onTap: () => _open(uri),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Icon(icon, size: 20, color: LocaisColors.navy),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: const TextStyle(
                          color: LocaisColors.muted,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: LocaisColors.navy,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded,
                    color: LocaisColors.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _hours(LocaisStrings strings, PlaceListing place) {
    return Column(
      key: const Key('locais_detail_hours'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(strings.hours),
        for (var day = 1; day <= 7; day++) _hourRow(strings, place, day),
      ],
    );
  }

  Widget _hourRow(LocaisStrings strings, PlaceListing place, int weekday) {
    final slots = place.hours.where((slot) => slot.weekday == weekday).toList();
    final today = weekday == _now.weekday;
    final text = slots.isEmpty
        ? strings.closedToday
        : slots.map((slot) => '${slot.opens}–${slot.closes}').join(', ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              strings.weekday(weekday) + (today ? ' · ${strings.today}' : ''),
              style: TextStyle(
                fontWeight: today ? FontWeight.w800 : FontWeight.w600,
                color: LocaisColors.text,
              ),
            ),
          ),
          Flexible(
            child: Text(
              text,
              textAlign: TextAlign.end,
              style: const TextStyle(color: LocaisColors.muted),
            ),
          ),
        ],
      ),
    );
  }

  Widget _accessibility(LocaisStrings strings, PlaceListing place) {
    final access = place.accessibility;
    return Column(
      key: const Key('locais_detail_accessibility'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(strings.accessibility),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _accessChip(strings.wheelchairEntrance, access.wheelchairEntrance),
            _accessChip(strings.stepFree, access.stepFree),
            _accessChip(strings.accessibleRestroom, access.accessibleRestroom),
          ],
        ),
        if (access.notes.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            access.notes,
            style: const TextStyle(color: LocaisColors.text, height: 1.35),
          ),
        ],
      ],
    );
  }

  Widget _reviews(LocaisStrings strings, PlaceListing place) {
    final summary = ReviewSummary.of(place);
    return Column(
      key: const Key('locais_detail_reviews'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(strings.reviews),
        _reviewSummary(strings, summary),
        if (_reviewWriteEnabled) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const Key('place_write_review'),
              style: FilledButton.styleFrom(
                backgroundColor: LocaisColors.navy,
                foregroundColor: Colors.white,
                minimumSize: const Size(48, 46),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: () => _reviewDialog(strings, place),
              icon: const Icon(Icons.star_outline_rounded),
              label: Text(strings.writeReview),
            ),
          ),
        ],
        const SizedBox(height: 12),
        if (place.reviews.isEmpty)
          Text(
            strings.noReviews,
            key: const Key('locais_reviews_empty'),
            style: const TextStyle(
                color: LocaisColors.muted, fontWeight: FontWeight.w600),
          )
        else
          for (var i = 0; i < place.reviews.length; i++) ...[
            if (i > 0) const Divider(height: 24, color: LocaisColors.border),
            _review(strings, place.reviews[i]),
          ],
      ],
    );
  }

  static const Color _starColor = Color(0xFFF5B301);

  Widget _stars(int filled, {double size = 16}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 5; i++)
          Icon(
            i <= filled ? Icons.star_rounded : Icons.star_outline_rounded,
            size: size,
            color: i <= filled ? _starColor : LocaisColors.border,
          ),
      ],
    );
  }

  Widget _reviewSummary(LocaisStrings strings, ReviewSummary summary) {
    final score = strings.ratingLine(summary.average, 0).split(' ').first;
    return Row(
      key: const Key('locais_reviews_summary'),
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 96,
          child: Column(
            children: [
              Text(
                summary.total == 0 ? '–' : score,
                key: const Key('locais_reviews_average'),
                style: const TextStyle(
                  color: LocaisColors.navy,
                  fontSize: 36,
                  fontWeight: FontWeight.w900,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 4),
              _stars(summary.average.round(), size: 15),
              const SizedBox(height: 4),
              Text(
                strings.reviewTotal(summary.total),
                key: const Key('locais_reviews_total'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: LocaisColors.muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            children: [
              for (var star = 5; star >= 1; star--)
                Padding(
                  key: Key('locais_reviews_bar_$star'),
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 26,
                        child: Text(
                          '$star★',
                          style: const TextStyle(
                            color: LocaisColors.navy,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: summary.fraction(star),
                            minHeight: 8,
                            backgroundColor: const Color(0xFFF1F2F6),
                            valueColor:
                                const AlwaysStoppedAnimation(_starColor),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 30,
                        child: Text(
                          '${summary.counts[star] ?? 0}',
                          key: Key('locais_reviews_count_$star'),
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            color: LocaisColors.muted,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _reviewDialog(LocaisStrings strings, PlaceListing place) async {
    var stars = 0;
    var anonymous = false;
    final comment = TextEditingController();
    await showDialog<void>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
              builder: (context, setDialogState) => AlertDialog(
                scrollable: true,
                title: Text(strings.writeReview),
                content: Column(mainAxisSize: MainAxisSize.min, children: [
                  Semantics(
                      label: strings.writeReview,
                      child: Row(children: [
                        for (var i = 1; i <= 5; i++)
                          IconButton(
                            tooltip: '$i',
                            onPressed: () => setDialogState(() => stars = i),
                            icon: Icon(
                                i <= stars ? Icons.star : Icons.star_border,
                                color: const Color(0xFFF5B301)),
                          ),
                      ])),
                  TextField(
                      textCapitalization: TextCapitalization.sentences,
                      controller: comment,
                      maxLength: 1500,
                      maxLines: 4,
                      decoration: InputDecoration(
                          labelText: strings.reviewComment,
                          errorText:
                              stars == 0 ? strings.requiredPending : null)),
                  CheckboxListTile(
                    key: const Key('place_review_anonymous'),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: anonymous,
                    onChanged: (value) =>
                        setDialogState(() => anonymous = value == true),
                    title: Text(strings.postAnonymously),
                  ),
                ]),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: Text(strings.cancel)),
                  FilledButton(
                      onPressed: stars == 0
                          ? null
                          : () async {
                              try {
                                await widget.actions.submitReview(
                                    placeId: place.id,
                                    stars: stars,
                                    comment: comment.text,
                                    anonymous: anonymous);
                              } catch (error) {
                                if (!mounted) return;
                                ScaffoldMessenger.of(this.context).showSnackBar(
                                    SnackBar(
                                        content: Text(strings.reviewError(
                                            _reviewErrorCode(error)))));
                                return;
                              }
                              if (!dialogContext.mounted) return;
                              Navigator.pop(dialogContext);
                              if (!mounted) return;
                              ScaffoldMessenger.of(this.context).showSnackBar(
                                  SnackBar(
                                      content: Text(strings.reviewPending)));
                              await _load();
                            },
                      child: Text(strings.sendReview)),
                ],
              ),
            ));
    comment.dispose();
  }

  /// Código curto do erro da função (FirebaseFunctionsException.message/code).
  static String _reviewErrorCode(Object error) {
    try {
      final dynamic e = error;
      final message = (e.message ?? '').toString();
      final code = (e.code ?? '').toString();
      if (message.contains('Adult age verification')) return 'age';
      if (message.contains('owner_cannot_review')) return 'owner';
      if (message.contains('review_rate') || code == 'resource-exhausted') {
        return 'rate';
      }
      if (code == 'unauthenticated') return 'auth';
    } catch (_) {}
    return 'generic';
  }

  /// "2026-10-16T…" → "16/10/2026". Vazio se inválido.
  static String _reviewDate(String iso) {
    final date = DateTime.tryParse(iso);
    if (date == null) return '';
    final local = date.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)}/${local.year}';
  }

  Widget _reviewAvatar(PlaceReview review) {
    final url = review.anonymous ? null : review.authorPhotoUrl;
    return CircleAvatar(
      radius: 18,
      backgroundColor: const Color(0xFFE7EBF5),
      foregroundImage: url == null ? null : NetworkImage(url),
      child: Icon(
        review.anonymous ? Icons.person_off_outlined : Icons.person_rounded,
        size: 20,
        color: LocaisColors.navy,
      ),
    );
  }

  Widget _review(LocaisStrings strings, PlaceReview review) {
    final date = _reviewDate(review.createdAt);
    final name = review.anonymous ? strings.anonymous : review.authorName;
    return Column(
      key: Key('locais_review_${review.id}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _reviewAvatar(review),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      color: LocaisColors.navy,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      _stars(review.rating, size: 14),
                      if (date.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            review.editedAt == null
                                ? date
                                : '$date · ${strings.edited}',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: LocaisColors.muted,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        if (review.comment.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(review.comment, style: const TextStyle(height: 1.35)),
        ],
        if (review.ownerReply != null) ...[
          const SizedBox(height: 10),
          DecoratedBox(
            decoration: BoxDecoration(
              color: LocaisColors.bg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    strings.ownerReply,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(review.ownerReply!.text),
                ],
              ),
            ),
          ),
        ],
        if (_userWriteActionsEnabled && _canManage) ...[
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () => _replyDialog(strings, review),
            icon: const Icon(Icons.reply_rounded),
            label: Text(strings.ownerReply),
          ),
        ],
      ],
    );
  }

  Future<void> _replyDialog(LocaisStrings strings, PlaceReview review) async {
    final controller =
        TextEditingController(text: review.ownerReply?.text ?? '');
    await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
              scrollable: true,
              title: Text(strings.ownerReply),
              content: TextField(
                  textCapitalization: TextCapitalization.sentences,
                  controller: controller,
                  maxLength: 800,
                  maxLines: 4,
                  decoration:
                      InputDecoration(labelText: strings.reviewComment)),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: Text(strings.cancel)),
                FilledButton(
                    onPressed: () async {
                      if (controller.text.trim().isEmpty) return;
                      await widget.actions.reply(
                          placeId: widget.placeId,
                          reviewId: review.id,
                          text: controller.text);
                      if (!dialogContext.mounted) return;
                      Navigator.pop(dialogContext);
                      await _load();
                    },
                    child: Text(strings.ownerReply)),
              ],
            ));
    controller.dispose();
  }

  Widget _events(LocaisStrings strings, PlaceListing place) {
    return Column(
      key: const Key('locais_detail_events'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(strings.upcomingEvents),
        if (place.upcomingEvents.isEmpty)
          Text(
            strings.noEvents,
            style: const TextStyle(color: LocaisColors.muted),
          )
        else
          for (final event in place.upcomingEvents)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                tileColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: const BorderSide(color: LocaisColors.border),
                ),
                leading: const Icon(
                  Icons.event_rounded,
                  color: LocaisColors.navy,
                ),
                title: Text(
                  event.title,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text(
                  event.note.isEmpty
                      ? event.startsAt
                      : '${event.startsAt} · ${event.note}',
                ),
              ),
            ),
      ],
    );
  }

  // Mantido para reuso futuro (admin); não aparece para o usuário.
  // ignore: unused_element
  Widget _merchant(LocaisStrings strings, PlaceListing place) {
    final portal = MerchantPortalPlan.portalUri(place.id);
    final link = MerchantPortalPlan.deepLinkUri(place.id);
    return DecoratedBox(
      key: const Key('merchant_portal_plan'),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: LocaisColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              strings.merchantTitle,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: LocaisColors.text,
              ),
            ),
            const SizedBox(height: 6),
            Text(strings.merchantBody, style: const TextStyle(height: 1.35)),
            const SizedBox(height: 8),
            Text('${strings.portalLabel}: $portal'),
            const SizedBox(height: 4),
            Text('${strings.deepLinkLabel}: $link'),
            const SizedBox(height: 12),
            OutlinedButton(
              key: const Key('merchant_portal_button'),
              style: OutlinedButton.styleFrom(
                foregroundColor: LocaisColors.navy,
                minimumSize: const Size(48, 48),
              ),
              onPressed: () => _claimDialog(strings, place),
              child: Text(strings.claimPlace),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _claimDialog(LocaisStrings strings, PlaceListing place) async {
    final phone = TextEditingController();
    final note = TextEditingController();
    var submitted = false;
    await showDialog<void>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
              builder: (context, setDialogState) => AlertDialog(
                scrollable: true,
                title: Text(strings.claimPlace),
                content: Column(mainAxisSize: MainAxisSize.min, children: [
                  TextField(
                    textCapitalization: TextCapitalization.sentences,
                    controller: phone,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      labelText: strings.claimPhone,
                      errorText: submitted && phone.text.trim().isEmpty
                          ? strings.requiredPending
                          : null,
                    ),
                  ),
                  TextField(
                    textCapitalization: TextCapitalization.sentences,
                    controller: note,
                    maxLength: 500,
                    maxLines: 3,
                    decoration: InputDecoration(labelText: strings.claimNote),
                  ),
                ]),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: Text(strings.cancel)),
                  FilledButton(
                      onPressed: () async {
                        setDialogState(() => submitted = true);
                        if (phone.text.trim().isEmpty) return;
                        await widget.actions.claim(
                            placeId: place.id,
                            role: 'owner',
                            phone: phone.text,
                            note: note.text);
                        if (!dialogContext.mounted) return;
                        Navigator.pop(dialogContext);
                        if (!mounted) return;
                        ScaffoldMessenger.of(this.context).showSnackBar(
                            SnackBar(content: Text(strings.claimSent)));
                      },
                      child: Text(strings.claimPlace)),
                ],
              ),
            ));
    phone.dispose();
    note.dispose();
  }

  Future<void> _reportDialog(LocaisStrings strings, PlaceListing place) async {
    const reasons = [
      'incorrect_information',
      'closed_or_missing',
      'inappropriate_photo',
      'fraud_or_impersonation',
      'other',
    ];
    var reason = reasons.first;
    var submitted = false;
    final details = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          scrollable: true,
          title: Text(strings.reportPlace),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  key: const Key('place_report_reason'),
                  initialValue: reason,
                  decoration: InputDecoration(labelText: strings.reportReason),
                  items: [
                    for (final value in reasons)
                      DropdownMenuItem(
                        value: value,
                        child: Text(strings.reportReasonLabel(value)),
                      ),
                  ],
                  onChanged: (value) =>
                      setDialogState(() => reason = value ?? reasons.first),
                ),
                TextField(
                  key: const Key('place_report_details'),
                  controller: details,
                  textCapitalization: TextCapitalization.sentences,
                  maxLength: 800,
                  maxLines: 4,
                  decoration: InputDecoration(
                    labelText: strings.reportDetails,
                    errorText: submitted &&
                            reason == 'other' &&
                            details.text.trim().length < 5
                        ? strings.requiredPending
                        : null,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(strings.cancel),
            ),
            FilledButton(
              key: const Key('place_report_submit'),
              onPressed: () async {
                setDialogState(() => submitted = true);
                if (reason == 'other' && details.text.trim().length < 5) return;
                try {
                  await widget.actions.reportPlace(
                    placeId: place.id,
                    reason: reason,
                    details: details.text,
                  );
                } catch (_) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(this.context).showSnackBar(
                    SnackBar(content: Text(strings.reportError)),
                  );
                  return;
                }
                if (!dialogContext.mounted) return;
                Navigator.pop(dialogContext);
                if (!mounted) return;
                ScaffoldMessenger.of(this.context).showSnackBar(
                  SnackBar(content: Text(strings.reportSent)),
                );
              },
              child: Text(strings.reportPlace),
            ),
          ],
        ),
      ),
    );
    details.dispose();
  }

  // Mantém o roteiro do portal disponível para a futura central do comerciante.
  // ignore: unused_element
  Future<void> _showPlan(LocaisStrings strings) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  strings.merchantTitle,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                for (final step in MerchantPortalPlan.stepKeys)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text('• ${strings.merchantStep(step)}'),
                  ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    key: const Key('merchant_plan_dismiss'),
                    style: FilledButton.styleFrom(
                      backgroundColor: LocaisColors.navy,
                      minimumSize: const Size(48, 48),
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(strings.understood),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _section(String title, String body) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(title),
        Text(
          body,
          style: const TextStyle(color: LocaisColors.text, height: 1.4),
        ),
      ],
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w900,
          color: LocaisColors.navy,
        ),
      ),
    );
  }

  Widget _pill(String label, bool open) {
    final color = open ? LocaisColors.open : LocaisColors.muted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _accessChip(String label, bool available) {
    return Chip(
      avatar: Icon(
        available ? Icons.check_circle_rounded : Icons.remove_circle_outline,
        size: 18,
        color: available ? LocaisColors.open : LocaisColors.muted,
      ),
      label: Text(label),
      backgroundColor: Colors.white,
      side: const BorderSide(color: LocaisColors.border),
    );
  }
}

/// Resumo de avaliações: usa o agregado do local (`rating.stars`) e, se
/// faltar, calcula a partir das avaliações listadas.
class ReviewSummary {
  const ReviewSummary(this.average, this.total, this.counts);

  final double average;
  final int total;
  final Map<int, int> counts;

  factory ReviewSummary.of(PlaceListing place) {
    final aggregate = place.ratingCounts;
    final aggregateTotal = aggregate.values.fold<int>(0, (a, b) => a + b);
    if (aggregateTotal > 0) {
      final weighted =
          aggregate.entries.fold<int>(0, (sum, e) => sum + e.key * e.value);
      final average =
          place.rating > 0 ? place.rating : weighted / aggregateTotal;
      return ReviewSummary(average, aggregateTotal, aggregate);
    }
    final counts = {for (var s = 1; s <= 5; s++) s: 0};
    for (final review in place.reviews) {
      counts[review.rating] = (counts[review.rating] ?? 0) + 1;
    }
    final listed = place.reviews.length;
    if (listed > 0) {
      final sum = place.reviews.fold<int>(0, (a, r) => a + r.rating);
      return ReviewSummary(sum / listed, listed, counts);
    }
    return ReviewSummary(0, 0, counts);
  }

  double fraction(int star) =>
      total == 0 ? 0 : ((counts[star] ?? 0) / total).clamp(0, 1).toDouble();
}
