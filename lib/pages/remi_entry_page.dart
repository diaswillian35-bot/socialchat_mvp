import 'package:flutter/material.dart';

import 'remi_chat_page.dart';
import 'remi_intro_page.dart';
import '../services/remi_intro_service.dart';

/// Gate de entrada da Remi: apresentação 1× por conta, sem flash/spinner longo.
///
/// Atalho da Home (já visto): abre o chat padrão (sem regressão).
/// Primeira vez: [RemiIntroPage] → fluxo Languages.
class RemiEntryPage extends StatefulWidget {
  const RemiEntryPage({super.key});

  static const Color _bg = Color(0xFFF8FAFC);

  @override
  State<RemiEntryPage> createState() => _RemiEntryPageState();
}

class _RemiEntryPageState extends State<RemiEntryPage> {
  Widget? _body;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  Future<void> _resolve() async {
    final showIntro = await RemiIntroService.instance.shouldShowIntro();
    if (!mounted) return;

    setState(() {
      _body = showIntro
          ? const RemiIntroPage()
          : const RemiChatPage(
              language: 'English',
              goal: 'Daily Life',
              lesson: 'Small Talk',
            );
    });
  }

  @override
  Widget build(BuildContext context) {
    // Fundo igual ao da Remi enquanto decide — sem spinner / tela branca.
    return _body ??
        const Scaffold(
          backgroundColor: RemiEntryPage._bg,
          body: SizedBox.expand(),
        );
  }
}
