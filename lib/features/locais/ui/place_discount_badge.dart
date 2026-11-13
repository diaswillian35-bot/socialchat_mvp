import 'package:flutter/material.dart';

import '../models/place_discount.dart';

/// Selo verde "−X%" dos mockups (fundo #15803D, pílula, 11/w800).
class PlaceDiscountBadge extends StatelessWidget {
  const PlaceDiscountBadge({
    super.key,
    required this.discount,
    this.onTap,
    this.compact = true,
  });

  final PlaceDiscount discount;
  final VoidCallback? onTap;
  final bool compact;

  static const Color sale = Color(0xFF15803D);

  @override
  Widget build(BuildContext context) {
    final pad = compact
        ? const EdgeInsets.symmetric(horizontal: 8, vertical: 3)
        : const EdgeInsets.symmetric(horizontal: 12, vertical: 6);
    final child = Container(
      padding: pad,
      decoration: BoxDecoration(
        color: sale,
        borderRadius: BorderRadius.circular(999),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1F000000),
            blurRadius: 2,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Text(
        discount.badgeLabel(),
        style: TextStyle(
          color: Colors.white,
          fontSize: compact ? 11 : 13,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
    if (onTap == null) return child;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: const Key('place_discount_badge'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: child,
      ),
    );
  }
}

class PlaceDiscountPartnerPill extends StatelessWidget {
  const PlaceDiscountPartnerPill({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFEEF2FF),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFF264E9A),
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
