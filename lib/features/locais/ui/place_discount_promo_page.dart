import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../l10n/app_texts.dart';
import '../../../services/functions_error_text.dart';
import '../data/place_discount_service.dart';
import '../models/place_discount.dart';
import '../models/place_listing.dart';
import 'locais_layout.dart';
import 'place_discount_badge.dart';

class PlaceDiscountPromoPage extends StatefulWidget {
  const PlaceDiscountPromoPage({
    super.key,
    required this.placeName,
    required this.placeId,
    required this.discount,
  });

  final String placeName;
  final String placeId;
  final PlaceDiscount discount;

  static Future<void> open(
    BuildContext context, {
    required String placeId,
    required String placeName,
    required PlaceDiscount discount,
  }) {
    return Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => PlaceDiscountPromoPage(
          placeId: placeId,
          placeName: placeName,
          discount: discount,
        ),
      ),
    );
  }

  static Future<void> openFromPlace(
    BuildContext context,
    PlaceListing place,
  ) {
    final discount = place.discount;
    if (discount == null || !discount.isActiveAt(DateTime.now())) {
      return Future.value();
    }
    return open(
      context,
      placeId: place.id,
      placeName: place.name,
      discount: discount,
    );
  }

  @override
  State<PlaceDiscountPromoPage> createState() => _PlaceDiscountPromoPageState();
}

class _PlaceDiscountPromoPageState extends State<PlaceDiscountPromoPage> {
  PlaceDiscountCode? _code;
  String? _errorText;
  bool _loading = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _tick();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    if (PlaceDiscountService.isLoggedIn) {
      _issue();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _issue() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _errorText = null;
    });
    try {
      final code = await PlaceDiscountService.issueCode(widget.placeId);
      if (!mounted) return;
      setState(() {
        _code = code;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorText = functionsErrorText(e, fallbackKey: 'place_discount_error');
      });
    }
  }

  void _tick() {
    final code = _code;
    if (code == null) {
      if (mounted) setState(() {});
      return;
    }
    if (!code.expiresAt.isAfter(DateTime.now().toUtc())) {
      _issue();
      return;
    }
    if (mounted) setState(() {});
  }

  String _rules(PlaceDiscount d) {
    switch (d.coveredBy) {
      case 'remdy':
        return AppTexts.t('place_discount_rules_remdy');
      case 'shared':
        return AppTexts.t('place_discount_rules_shared');
      default:
        return AppTexts.t('place_discount_rules_place');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexts.t;
    final d = widget.discount;
    final remain = _code == null
        ? Duration.zero
        : _code!.expiresAt.difference(DateTime.now().toUtc());
    final secs = remain.isNegative ? 0 : remain.inSeconds.clamp(0, 60);
    final progress = _code == null ? 0.0 : (secs / 60).clamp(0.0, 1.0);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: LocaisColors.text,
        title: Text(
          t('place_discount_promo_title'),
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              PlaceDiscountBadge(discount: d, compact: true),
              if (d.isPartnership)
                PlaceDiscountPartnerPill(label: t('place_discount_partner')),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            t('place_discount_headline')
                .replaceAll('{percent}', '${d.percent}'),
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              height: 1.25,
              color: LocaisColors.text,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            t('place_discount_valid_line')
                .replaceAll('{name}', widget.placeName)
                .replaceAll('{date}', d.formatValidUntil()),
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: LocaisColors.muted,
            ),
          ),
          const SizedBox(height: 14),
          _block(
            title: t('place_discount_how_title'),
            body: t('place_discount_how_body'),
          ),
          const SizedBox(height: 12),
          _codeBox(t, secs, progress),
          const SizedBox(height: 12),
          _block(
            title: t('place_discount_rules_title'),
            body: _rules(d),
          ),
        ],
      ),
    );
  }

  Widget _block({required String title, required String body}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: LocaisColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: LocaisColors.muted,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              height: 1.4,
              color: LocaisColors.text,
            ),
          ),
        ],
      ),
    );
  }

  Widget _codeBox(String Function(String) t, int secs, double progress) {
    Widget inner;
    if (!PlaceDiscountService.isLoggedIn) {
      inner = Text(
        t('place_discount_login'),
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: LocaisColors.muted,
        ),
      );
    } else if (_errorText != null) {
      inner = Column(
        children: [
          Text(
            _errorText!,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: LocaisColors.text,
            ),
          ),
          TextButton(
            onPressed: _issue,
            child: Text(t('place_discount_retry')),
          ),
        ],
      );
    } else if (_code == null) {
      inner = const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    } else {
      final mm = (secs ~/ 60).toString().padLeft(1, '0');
      final ss = (secs % 60).toString().padLeft(2, '0');
      inner = Column(
        children: [
          Text(
            _code!.code,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              letterSpacing: 2.4,
              color: LocaisColors.navy,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            t('place_discount_refresh').replaceAll('{time}', '$mm:$ss'),
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: LocaisColors.navy,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 10, 24, 0),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                minHeight: 6,
                value: progress,
                backgroundColor: const Color(0xFFE8EAF0),
                color: LocaisColors.navy,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            width: 132,
            height: 132,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: LocaisColors.border),
            ),
            child: QrImageView(
              data: _code!.payload,
              size: 124,
              backgroundColor: Colors.white,
              eyeStyle: const QrEyeStyle(
                eyeShape: QrEyeShape.square,
                color: LocaisColors.navy,
              ),
              dataModuleStyle: const QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.square,
                color: LocaisColors.navy,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            t('place_discount_qr_note'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              height: 1.35,
              color: LocaisColors.muted,
            ),
          ),
        ],
      );
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
      decoration: BoxDecoration(
        color: LocaisColors.bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: LocaisColors.navy, width: 2),
      ),
      // dashed border approximation: navy solid 2 is close; mockup is dashed.
      child: inner,
    );
  }
}
