import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/place_actions_service.dart';
import '../data/place_repository.dart';
import '../locais_feature_flag.dart';
import '../locais_strings.dart';
import '../logic/merchant_portal_plan.dart';
import '../models/place_listing.dart';
import 'locais_layout.dart';
import 'locais_map_view.dart';
import 'locais_state_views.dart';
import 'place_card.dart';

class LocaisDetailPage extends StatefulWidget {
  const LocaisDetailPage({
    super.key,
    required this.placeId,
    required this.repository,
    this.clock,
    PlaceActionsService? actions,
  }) : actions = actions ?? const PlaceActionsService();

  final String placeId;
  final PlaceRepository repository;
  final DateTime Function()? clock;
  final PlaceActionsService actions;

  @override
  State<LocaisDetailPage> createState() => _LocaisDetailPageState();
}

class _LocaisDetailPageState extends State<LocaisDetailPage> {
  PlaceListing? _place;
  bool _loading = true;
  bool _failed = false;
  int _photo = 0;
  bool _canManage = false;

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
    return Scaffold(
      backgroundColor: LocaisColors.bg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: LocaisColors.navy,
        elevation: 0,
        title: Text(
          _place?.name ?? strings.title,
          key: const Key('locais_detail_title'),
        ),
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
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      children: [
        _photos(place, wide),
        const SizedBox(height: 16),
        Text(
          strings.categoryName(place.category).toUpperCase(),
          style: const TextStyle(
            color: LocaisColors.logoBlue,
            fontWeight: FontWeight.w800,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          place.name,
          style: const TextStyle(
            color: LocaisColors.text,
            fontSize: 26,
            fontWeight: FontWeight.w900,
            height: 1.15,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Icon(Icons.star_rounded, color: Color(0xFFF5B301)),
            Text(
              strings.ratingLine(place.rating, place.ratingCount),
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            _pill(open ? strings.openNow : strings.closed, open),
          ],
        ),
        const SizedBox(height: 18),
        _section(
          strings.description,
          place.description,
          key: const Key('locais_detail_description'),
        ),
        const SizedBox(height: 16),
        _sectionTitle(strings.address),
        SizedBox(
          key: const Key('locais_detail_map'),
          height: wide ? 240 : 180,
          child: LocaisMapView(
            places: [place],
            strings: strings,
            highlightId: place.id,
          ),
        ),
        const SizedBox(height: 8),
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
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: const Key('locais_route_button'),
          onPressed: () => launchUrl(
            Uri.parse(
                'https://www.google.com/maps/dir/?api=1&destination=${place.address.latitude},${place.address.longitude}'),
            mode: LaunchMode.externalApplication,
          ),
          icon: const Icon(Icons.directions_outlined),
          label: Text(strings.route),
        ),
        const SizedBox(height: 16),
        _contacts(strings, place),
        const SizedBox(height: 16),
        _hours(strings, place),
        const SizedBox(height: 16),
        _accessibility(strings, place),
        const SizedBox(height: 16),
        _menu(strings, place),
        if (place.menu.enabled) const SizedBox(height: 16),
        _reviews(strings, place),
        const SizedBox(height: 16),
        _events(strings, place),
        const SizedBox(height: 16),
        _merchant(strings, place),
      ],
    );
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
              itemBuilder: (_, index) => ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(menu.photoUrls[index],
                    width: 120,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox(
                        width: 120, child: Icon(Icons.broken_image_outlined))),
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
            onPressed: () => launchUrl(Uri.parse(menu.pdfUrl!),
                mode: LaunchMode.externalApplication),
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
    return Column(
      key: const Key('locais_detail_photos'),
      children: [
        SizedBox(
          height: wide ? 280 : 210,
          child: PageView.builder(
            itemCount: place.photos.length,
            onPageChanged: (index) => setState(() => _photo = index),
            itemBuilder: (context, index) {
              return ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: PlaceCover(
                  photo: place.photos[index],
                  category: place.category,
                ),
              );
            },
          ),
        ),
        if (place.photos.length > 1) ...[
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < place.photos.length; i++)
                Container(
                  width: 7,
                  height: 7,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color:
                        i == _photo ? LocaisColors.navy : LocaisColors.border,
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _contacts(LocaisStrings strings, PlaceListing place) {
    final contact = place.contact;
    return Column(
      key: const Key('locais_detail_contact'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(strings.contact),
        if (contact.phone != null)
          _actionRow(Icons.phone_rounded, strings.phone, contact.phone!,
              Uri(scheme: 'tel', path: contact.phone)),
        if (contact.whatsapp != null)
          _actionRow(
              Icons.chat_outlined,
              'WhatsApp',
              contact.whatsapp!,
              Uri.https(
                  'wa.me', contact.whatsapp!.replaceAll(RegExp(r'\D'), ''))),
        if (contact.website != null)
          _infoRow(Icons.language_rounded, strings.website, contact.website!),
        if (contact.instagram != null)
          _infoRow(
            Icons.alternate_email_rounded,
            strings.instagram,
            contact.instagram!,
          ),
        if (contact.phone == null &&
            contact.website == null &&
            contact.instagram == null)
          Text(
            strings.emptyBody,
            style: const TextStyle(color: LocaisColors.muted),
          ),
      ],
    );
  }

  Widget _actionRow(IconData icon, String label, String value, Uri uri) {
    return Semantics(
      button: true,
      label: '$label, $value',
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon, color: LocaisColors.navy),
        title: Text(label),
        subtitle: Text(value),
        trailing: const Icon(Icons.open_in_new, size: 18),
        onTap: () => launchUrl(uri, mode: LaunchMode.externalApplication),
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
    return Column(
      key: const Key('locais_detail_reviews'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(strings.reviews),
        FilledButton.icon(
          key: const Key('place_write_review'),
          onPressed: () => _reviewDialog(strings, place),
          icon: const Icon(Icons.star_outline_rounded),
          label: Text(strings.writeReview),
        ),
        const SizedBox(height: 10),
        if (place.reviews.isEmpty)
          Text(
            strings.noReviews,
            style: const TextStyle(color: LocaisColors.muted),
          )
        else
          for (final review in place.reviews) _review(strings, review),
      ],
    );
  }

  Future<void> _reviewDialog(LocaisStrings strings, PlaceListing place) async {
    var stars = 0;
    final comment = TextEditingController();
    await showDialog<void>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
              builder: (context, setDialogState) => AlertDialog(
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
                ]),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('Cancelar')),
                  FilledButton(
                      onPressed: stars == 0
                          ? null
                          : () async {
                              await widget.actions.submitReview(
                                  placeId: place.id,
                                  stars: stars,
                                  comment: comment.text);
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

  Widget _review(LocaisStrings strings, PlaceReview review) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: LocaisColors.border),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      review.authorName,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  const Icon(
                    Icons.star_rounded,
                    size: 16,
                    color: Color(0xFFF5B301),
                  ),
                  Text('${review.rating}'),
                ],
              ),
              const SizedBox(height: 4),
              Text(review.comment, style: const TextStyle(height: 1.35)),
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
              if (_canManage) ...[
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () => _replyDialog(strings, review),
                  icon: const Icon(Icons.reply_rounded),
                  label: Text(strings.ownerReply),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _replyDialog(LocaisStrings strings, PlaceReview review) async {
    final controller =
        TextEditingController(text: review.ownerReply?.text ?? '');
    await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
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
                    child: const Text('Cancelar')),
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
                      child: const Text('Cancelar')),
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

  Widget _section(String title, String body, {required Key key}) {
    return Column(
      key: key,
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
          fontWeight: FontWeight.w800,
          color: LocaisColors.text,
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: LocaisColors.navy),
          const SizedBox(width: 8),
          Expanded(
            child: Text('$label: $value', style: const TextStyle(height: 1.3)),
          ),
        ],
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
