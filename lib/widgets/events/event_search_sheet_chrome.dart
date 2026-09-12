import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Chrome compartilhado das bottom sheets de busca de cidade/local
/// no fluxo de Eventos (criar/editar).
///
/// **Não** confia no [MediaQuery] herdado do modal (`padding`/`viewPadding`
/// costumam vir zerados com `showModalBottomSheet` + `isScrollControlled`).
/// O inset físico superior vem de
/// [MediaQueryData.fromView] via [View.of].
///
/// Cancelar / seta voltar / gesto / botão do sistema:
/// fecham teclado e depois a folha (resultado `null` = formulário intacto).
class EventSearchSheetChrome extends StatelessWidget {
  const EventSearchSheetChrome({
    super.key,
    required this.searchField,
    required this.body,
    this.title,
    this.cancelLabel = 'Cancelar',
  });

  final Widget searchField;
  final Widget body;
  final String? title;
  final String cancelLabel;

  /// Espaço extra abaixo do inset físico (status / Dynamic Island).
  static const double topGap = 12;

  /// Altura mínima tocável do cabeçalho (Voltar / Cancelar).
  static const double headerMinHeight = 48;

  /// Inset superior físico da [FlutterView] (não o MediaQuery do modal).
  static double physicalTopInset(BuildContext context) {
    final view = View.of(context);
    return MediaQueryData.fromView(view).padding.top;
  }

  /// Inset inferior físico da view (home indicator), sem teclado.
  static double physicalBottomInset(BuildContext context) {
    final view = View.of(context);
    return MediaQueryData.fromView(view).padding.bottom;
  }

  /// Fecha teclado e, em seguida, a folha modal (pop com `null`).
  static Future<void> dismiss(BuildContext context) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await Future<void>.delayed(Duration.zero);
    if (!context.mounted) return;
    final nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final keyboard = mq.viewInsets.bottom;
    final topInset = physicalTopInset(context);
    final bottomInset =
        keyboard > 0 ? keyboard : physicalBottomInset(context);

    final usable =
        mq.size.height - topInset - bottomInset - topGap - 16;
    final preferred = mq.size.height * 0.72;
    final sheetHeight = math
        .min(preferred, usable)
        .clamp(180.0, math.max(180.0, usable))
        .toDouble();

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        FocusManager.instance.primaryFocus?.unfocus();
      },
      child: Padding(
        // Toda a linha do cabeçalho fica abaixo do inset físico.
        padding: EdgeInsets.only(top: topInset, bottom: bottomInset),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, topGap, 16, 16),
          child: SizedBox(
            height: sheetHeight,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: headerMinHeight,
                  child: Row(
                    children: [
                      IconButton(
                        key: const Key('event_search_sheet_back'),
                        tooltip: cancelLabel,
                        icon: const Icon(Icons.arrow_back),
                        style: IconButton.styleFrom(
                          minimumSize: const Size(
                            headerMinHeight,
                            headerMinHeight,
                          ),
                          tapTargetSize: MaterialTapTargetSize.padded,
                          padding: EdgeInsets.zero,
                        ),
                        onPressed: () => dismiss(context),
                      ),
                      Expanded(
                        child: Text(
                          title ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      TextButton(
                        key: const Key('event_search_sheet_cancel'),
                        style: TextButton.styleFrom(
                          minimumSize: const Size(72, headerMinHeight),
                          tapTargetSize: MaterialTapTargetSize.padded,
                        ),
                        onPressed: () => dismiss(context),
                        child: Text(cancelLabel),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                searchField,
                const SizedBox(height: 12),
                Expanded(child: body),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
