import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../data/remi_lessons_data.dart';
import '../services/remi_intro_service.dart';
import '../services/remi_language_contract.dart';
import '../services/remi_session_prefs.dart';
import 'remi_chat_page.dart';
import 'remi_intro_page.dart';
import 'remi_languages_page.dart';

/// Gate de entrada da Remi: apresentação 1× por conta.
///
/// Depois da intro: restaura a última lição se existir e for válida;
/// caso contrário abre o seletor de idiomas (pt/en/es/fr).
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

    if (showIntro) {
      setState(() => _body = const RemiIntroPage());
      return;
    }

    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final saved = uid.isEmpty
        ? null
        : await RemiSessionPrefs.instance.loadSelection(uid);

    if (!mounted) return;

    if (saved != null) {
      final code = RemiLanguageContract.normalize(saved.languageCode);
      final catalog = remiCatalogFor(code);
      final lessons = catalog[saved.goal];
      if (lessons != null && lessons.containsKey(saved.lesson)) {
        setState(() {
          _body = RemiChatPage(
            languageCode: code,
            goal: saved.goal,
            lesson: saved.lesson,
          );
        });
        return;
      }
    }
    // saved invalid → languages picker below

    setState(() => _body = const RemiLanguagesPage());
  }

  @override
  Widget build(BuildContext context) {
    return _body ??
        const Scaffold(
          backgroundColor: RemiEntryPage._bg,
          body: SizedBox.expand(),
        );
  }
}
