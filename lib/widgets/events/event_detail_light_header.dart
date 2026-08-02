import 'package:flutter/material.dart';

import '../remdy_logo.dart';


/// Hero + cabeçalho do detalhe de evento no **tema claro** (mockup oficial).
///
/// - Foto com [BoxFit.cover]
/// - Degradê inferior para branco (sem faixa cinza)
/// - Título/status/local/data **abaixo** da foto, sobre fundo branco
/// - Controles sobre a foto com contraste adaptável
/// - Nunca usa logo do evento para preencher o hero
class EventDetailLightHeader extends StatelessWidget {
  const EventDetailLightHeader({
    super.key,
    required this.title,
    required this.locationLine,
    required this.dateLine,
    required this.confirmed,
    required this.cancelled,
    required this.liked,
    required this.confirmedLabel,
    required this.cancelledLabel,
    this.coverImage,
    this.coverImageUrl,
    this.coverChild,
    this.onBack,
    this.onShare,
    this.onLike,
    this.pageBackground = const Color(0xFFFFFFFF),
    this.heroHeight = 280,
  });

  static const Color navy = Color(0xFF313A5F);
  static const Color muted = Color(0xFF6B7280);
  static const Color confirmGreen = Color(0xFF22C55E);

  final String title;
  final String locationLine;
  final String dateLine;
  final bool confirmed;
  final bool cancelled;
  final bool liked;
  final String confirmedLabel;
  final String cancelledLabel;

  /// Imagem local (golden/tests). Prioridade sobre [coverImageUrl].
  final ImageProvider? coverImage;
  final String? coverImageUrl;

  /// Widget síncrono de capa (goldens). Prioridade sobre image/url.
  final Widget? coverChild;

  final VoidCallback? onBack;
  final VoidCallback? onShare;
  final VoidCallback? onLike;
  final Color pageBackground;
  final double heroHeight;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;

    return ColoredBox(
      color: pageBackground,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: heroHeight + top,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Positioned.fill(child: _buildPhoto()),
                // Degradê foto → branco (mockup claro).
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            pageBackground.withValues(alpha: 0),
                            pageBackground.withValues(alpha: 0),
                            pageBackground.withValues(alpha: 0.35),
                            pageBackground.withValues(alpha: 0.72),
                            pageBackground,
                          ],
                          stops: const [0.0, 0.55, 0.75, 0.90, 1.0],
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: top + 8,
                  left: 10,
                  right: 10,
                  child: Row(
                    children: [
                      _AdaptiveHeroButton(
                        icon: Icons.arrow_back_ios_new_rounded,
                        onTap: onBack,
                      ),
                      const Spacer(),
                      if (onShare != null) ...[
                        _AdaptiveHeroButton(
                          icon: Icons.ios_share_rounded,
                          onTap: onShare,
                        ),
                        const SizedBox(width: 8),
                      ],
                      _AdaptiveHeroButton(
                        icon: liked
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        iconColor:
                            liked ? const Color(0xFFE11D48) : Colors.white,
                        onTap: onLike,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (confirmed && !cancelled) ...[
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: confirmGreen,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      confirmedLabel,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                if (cancelled) ...[
                  Text(
                    cancelledLabel,
                    style: const TextStyle(
                      color: Color(0xFFDC2626),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                Text(
                  title,
                  style: const TextStyle(
                    color: navy,
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    height: 1.15,
                  ),
                ),
                if (locationLine.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.place_outlined, size: 16, color: muted),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          locationLine,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: muted,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                if (dateLine.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.calendar_today_outlined,
                          size: 15, color: muted),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          dateLine,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: muted,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhoto() {
    if (coverChild != null) {
      return coverChild!;
    }
    if (coverImage != null) {
      return Image(
        image: coverImage!,
        fit: BoxFit.cover,
        alignment: Alignment.center,
        filterQuality: FilterQuality.medium,
        gaplessPlayback: true,
      );
    }
    final url = (coverImageUrl ?? '').trim();
    if (url.isNotEmpty) {
      return Image.network(
        url,
        fit: BoxFit.cover,
        alignment: Alignment.center,
        gaplessPlayback: true,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, __, ___) => const _LightHeroFallback(),
      );
    }
    return const _LightHeroFallback();
  }
}

class _LightHeroFallback extends StatelessWidget {
  const _LightHeroFallback();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFF3F5FA),
            Color(0xFFE7EBF5),
            Color(0xFFDCE3F0),
          ],
        ),
      ),
      child: const Center(child: RemdyLogo(height: 48)),
    );
  }
}

/// Botão sobre a foto: disco escuro semi-transparente para contraste em
/// imagens claras e escuras (sem degradê escuro no hero).
class _AdaptiveHeroButton extends StatelessWidget {
  const _AdaptiveHeroButton({
    required this.icon,
    this.onTap,
    this.iconColor = Colors.white,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0x99000000),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, color: iconColor, size: 20),
        ),
      ),
    );
  }
}
