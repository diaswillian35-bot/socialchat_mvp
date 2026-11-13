import 'package:flutter/material.dart';

import '../../../l10n/app_texts.dart';
import '../../../services/functions_error_text.dart';
import '../data/place_discount_service.dart';
import 'locais_layout.dart';

class PlaceDiscountRedeemPage extends StatefulWidget {
  const PlaceDiscountRedeemPage({
    super.key,
    required this.placeId,
    required this.placeName,
  });

  final String placeId;
  final String placeName;

  static Future<void> open(
    BuildContext context, {
    required String placeId,
    required String placeName,
  }) {
    return Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => PlaceDiscountRedeemPage(
          placeId: placeId,
          placeName: placeName,
        ),
      ),
    );
  }

  @override
  State<PlaceDiscountRedeemPage> createState() =>
      _PlaceDiscountRedeemPageState();
}

class _PlaceDiscountRedeemPageState extends State<PlaceDiscountRedeemPage> {
  final _controller = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _redeem() async {
    final code = _controller.text.trim();
    if (code.isEmpty) return;
    setState(() => _busy = true);
    try {
      final percent = await PlaceDiscountService.redeem(
        placeId: widget.placeId,
        code: code,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppTexts.t('place_discount_redeem_ok')
                .replaceAll('{percent}', '$percent'),
          ),
        ),
      );
      _controller.clear();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(functionsErrorText(e, fallbackKey: 'place_discount_error')),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexts.t;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: LocaisColors.text,
        title: Text(
          t('place_discount_redeem_title'),
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Text(
            widget.placeName,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: LocaisColors.muted,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('place_discount_redeem_input'),
            controller: _controller,
            textCapitalization: TextCapitalization.characters,
            autocorrect: false,
            enabled: !_busy,
            decoration: InputDecoration(
              labelText: t('place_discount_redeem_hint'),
              labelStyle: const TextStyle(
                fontWeight: FontWeight.w700,
                color: LocaisColors.muted,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            onSubmitted: (_) => _redeem(),
          ),
          const SizedBox(height: 18),
          FilledButton(
            onPressed: _busy ? null : _redeem,
            style: FilledButton.styleFrom(
              backgroundColor: LocaisColors.navy,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(48),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              textStyle: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            child: _busy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : Text(t('place_discount_redeem_action')),
          ),
        ],
      ),
    );
  }
}
