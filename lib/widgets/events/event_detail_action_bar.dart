import 'package:flutter/material.dart';

/// Faixa de ações do detalhe (mockup tema claro).
class EventDetailActionBar extends StatelessWidget {
  const EventDetailActionBar({
    super.key,
    required this.favoriteLabel,
    required this.participateLabel,
    required this.shareLabel,
    required this.calendarLabel,
    required this.directionsLabel,
    required this.favorited,
    required this.participating,
    required this.favoriteBusy,
    required this.participateBusy,
    required this.shareBusy,
    required this.calendarBusy,
    required this.directionsEnabled,
    required this.onFavorite,
    required this.onParticipate,
    required this.onShare,
    required this.onCalendar,
    required this.onDirections,
  });

  static const Color navy = Color(0xFF313A5F);
  static const Color actionBlue = Color(0xFF264E9A);
  static const Color border = Color(0xFFE5E7EB);

  final String favoriteLabel;
  final String participateLabel;
  final String shareLabel;
  final String calendarLabel;
  final String directionsLabel;

  final bool favorited;
  final bool participating;
  final bool favoriteBusy;
  final bool participateBusy;
  final bool shareBusy;
  final bool calendarBusy;
  final bool directionsEnabled;

  final VoidCallback? onFavorite;
  final VoidCallback? onParticipate;
  final VoidCallback? onShare;
  final VoidCallback? onCalendar;
  final VoidCallback? onDirections;

  @override
  Widget build(BuildContext context) {
    final textScaler = MediaQuery.textScalerOf(context);
    final narrow = MediaQuery.sizeOf(context).width < 360 ||
        textScaler.scale(14) > 16;

    // UI: Favoritar · Participar · Compartilhar (Calendário/Como chegar preservados fora da UI).
    final actions = <Widget>[
      _ActionChip(
        label: favoriteLabel,
        icon: favorited ? Icons.favorite_rounded : Icons.favorite_border_rounded,
        highlighted: false,
        selected: favorited,
        busy: favoriteBusy,
        enabled: onFavorite != null,
        onTap: onFavorite,
      ),
      _ActionChip(
        label: participateLabel,
        icon: participating
            ? Icons.person_rounded
            : Icons.person_add_alt_1_rounded,
        highlighted: true,
        selected: participating,
        busy: participateBusy,
        enabled: onParticipate != null,
        onTap: onParticipate,
      ),
      _ActionChip(
        label: shareLabel,
        icon: Icons.ios_share_rounded,
        highlighted: false,
        busy: shareBusy,
        enabled: onShare != null,
        onTap: onShare,
      ),
    ];

    if (narrow) {
      return SizedBox(
        height: 78,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: actions.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (_, i) => SizedBox(width: 76, child: actions[i]),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          for (var i = 0; i < actions.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(child: actions[i]),
          ],
        ],
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.label,
    required this.icon,
    required this.highlighted,
    required this.busy,
    required this.enabled,
    required this.onTap,
    this.selected = false,
  });

  final String label;
  final IconData icon;
  final bool highlighted;
  final bool selected;
  final bool busy;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final bg = highlighted
        ? EventDetailActionBar.actionBlue
        : Colors.white;
    final fg = highlighted
        ? Colors.white
        : (enabled
            ? EventDetailActionBar.navy
            : EventDetailActionBar.navy.withValues(alpha: 0.35));
    final borderColor = highlighted
        ? EventDetailActionBar.actionBlue
        : (selected
            ? EventDetailActionBar.navy.withValues(alpha: 0.35)
            : EventDetailActionBar.border);

    return Semantics(
      button: true,
      enabled: enabled && !busy && onTap != null,
      label: label,
      selected: selected,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: (busy || onTap == null) ? null : onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            constraints: const BoxConstraints(minHeight: 64),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: borderColor),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (busy)
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: highlighted
                          ? Colors.white
                          : EventDetailActionBar.actionBlue,
                    ),
                  )
                else
                  Icon(
                    icon,
                    size: 20,
                    color: fg,
                  ),
                const SizedBox(height: 4),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: fg,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    height: 1.1,
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
