// Captura PNGs reais (Roboto + ícones Material) das telas de "Adicionar local".
// Rodar: flutter test tool/screens/place_screens_test.dart
// Saída: tool/screens/out/*.png (não faz parte da suíte nem do app).
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/features/locais/data/place_repository.dart';
import 'package:socialchat_mvp/features/locais/data/place_submission_service.dart';
import 'package:socialchat_mvp/features/locais/locais_feature_flag.dart';
import 'package:socialchat_mvp/features/locais/locais_strings.dart';
import 'package:socialchat_mvp/features/locais/ui/locais_list_page.dart';
import 'package:socialchat_mvp/features/locais/ui/place_editor_page.dart';
import 'package:socialchat_mvp/features/locais/ui/place_submissions_page.dart';
import 'package:socialchat_mvp/l10n/app_texts.dart';
import 'package:socialchat_mvp/widgets/publish_cta_card.dart';

const _fonts = '/Users/macbookairm1/Downloads/flutter/bin/cache/artifacts/material_fonts';

Future<void> _loadFonts() async {
  Future<ByteData> f(String n) async =>
      ByteData.view(Uint8List.fromList(File('$_fonts/$n').readAsBytesSync()).buffer);
  final roboto = FontLoader('Roboto');
  for (final n in ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf', 'Roboto-Black.ttf']) {
    roboto.addFont(f(n));
  }
  await roboto.load();
  final icons = FontLoader('MaterialIcons')..addFont(f('MaterialIcons-Regular.otf'));
  await icons.load();
}

ThemeData _theme() {
  const navy = Color(0xFF313A5F);
  return ThemeData(
    useMaterial3: true,
    fontFamily: 'Roboto',
    colorScheme: const ColorScheme.light(
      primary: navy, onPrimary: Colors.white, surface: Colors.white,
      onSurface: Color(0xFF111827), onSurfaceVariant: Color(0xFF6B7280),
      outline: Color(0xFFE5E7EB),
    ),
    scaffoldBackgroundColor: Colors.white,
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: navy, contentTextStyle: TextStyle(color: Colors.white),
    ),
  );
}

Future<void> _shot(WidgetTester tester, String name) async {
  await tester.pumpAndSettle();
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(const Key('shot')));
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 3);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final out = File('tool/screens/out/$name.png')..createSync(recursive: true);
    out.writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

Future<void> _pump(WidgetTester tester, Widget page) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  await tester.pumpWidget(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: _theme(),
    builder: (context, child) =>
        RepaintBoundary(key: const Key('shot'), child: child),
    home: page,
  ));
}

void main() {
  setUpAll(() async {
    await _loadFonts();
    AppTexts.loadFromMap(
      jsonDecode(File('lib/l10n/pt-BR.json').readAsStringSync()) as Map<String, dynamic>,
      const Locale('pt', 'BR'),
    );
    LocaisFeatureFlag.debugOverride = true;
    LocaisStrings.debugLocale = const Locale('pt', 'BR');
  });

  testWidgets('capturas', (tester) async {
    await _pump(tester, LocaisListPage(
      repository: DemoPlaceRepository(),
      clock: () => DateTime(2026, 10, 14, 15),
    ));
    await _shot(tester, '1_locais_botao_adicionar');

    await _pump(tester, const PlaceEditorPage());
    await _shot(tester, '2_form_passo1_vazio');
    await tester.enterText(find.byKey(const Key('place_name_field')), 'Café da Praça');
    await tester.pumpAndSettle();
    await _shot(tester, '3_form_passo1_preenchido');
    await tester.tap(find.byKey(const Key('place_next_button')));
    await tester.pumpAndSettle();
    await _shot(tester, '4_form_passo2_endereco');
    final sample = [
      PlaceDraft(id: 'a', name: 'Café da Praça', category: 'cafe', cityName: 'Toronto',
          stateName: 'ON', countryCode: 'CA', status: 'pending')..cityDisplay = 'Toronto, ON',
      PlaceDraft(id: 'b', name: 'Bar do Zé', category: 'bar', cityName: 'São Paulo',
          stateName: 'SP', status: 'pending')..cityDisplay = 'São Paulo, SP',
      PlaceDraft(id: 'c', name: 'Pousada Mar Azul', category: 'pousada', cityName: 'Lisboa',
          countryCode: 'PT', status: 'pending')..cityDisplay = 'Lisboa',
    ];
    await _pump(tester, PlaceSubmissionsPage(adminPending: true, loader: () async => sample));
    await _shot(tester, '5_admin_locais_em_analise');
    await tester.tap(find.text('Bar do Zé'));
    await tester.pumpAndSettle();
    await _shot(tester, '6_admin_aprovar_recusar');
  });

  testWidgets('cards de divulgação', (tester) async {
    await _pump(tester, LocaisListPage(
      repository: DemoPlaceRepository(),
      clock: () => DateTime(2026, 10, 14, 15),
    ));
    await _shot(tester, '7_locais_card');
    // Eventos: a página real depende do Firebase; captura o mesmo card
    // com o fundo, a busca e os espaçamentos da aba Eventos.
    await _pump(tester, Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      body: SafeArea(child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 5, 10, 6),
          child: TextField(decoration: InputDecoration(
            hintText: AppTexts.t('events_search_hint'),
            prefixIcon: const Icon(Icons.search), filled: true, fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
          )),
        ),
        PublishCtaCard(
          padding: const EdgeInsets.fromLTRB(10, 2, 10, 6),
          icon: Icons.event_available_outlined,
          title: AppTexts.t('event_cta_title'),
          subtitle: AppTexts.t('event_cta_subtitle'),
          onTap: () {},
        ),
      ])),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF313A5F), onPressed: () {},
        child: const Icon(Icons.add, color: Colors.white)),
    ));
    await _shot(tester, '8_eventos_card');
  });
}
