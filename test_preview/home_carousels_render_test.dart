// Gera prints da Home (iPhone 16 Pro Max, 440x956 pt @3x) com fonte SF real
// e imagens reais. Não faz parte da suíte: `flutter test test_preview/...`.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/features/locais/locais_strings.dart';
import 'package:socialchat_mvp/l10n/app_texts.dart';

import '../tool/preview/home_carousels_preview.dart';

const _out = String.fromEnvironment('OUT_DIR',
    defaultValue: '/Volumes/REMDY_SSD/remdy_b40_build/home_prints');

Future<void> _loadFont(String family, String path) async {
  final bytes = File(path).readAsBytesSync();
  final loader = FontLoader(family)
    ..addFont(Future.value(ByteData.view(bytes.buffer)));
  await loader.load();
}

void main() {
  setUpAll(() async {
    await _loadFont('SF', '/System/Library/Fonts/SFNS.ttf');
    await _loadFont('MaterialIcons',
        '${Platform.environment['FLUTTER_ROOT'] ?? '/Users/macbookairm1/Downloads/flutter'}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    Directory(_out).createSync(recursive: true);
  });

  for (final lang in ['pt-BR', 'en']) {
    for (final page in [0, 1]) {
      testWidgets('print $lang página ${page + 1}', (tester) =>
          HttpOverrides.runWithHttpOverrides(() async {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        final parts = lang.split('-');
        final locale = Locale(parts[0], parts.length > 1 ? parts[1] : null);
        AppTexts.loadFromMap(
            Map<String, dynamic>.from(
                jsonDecode(File('lib/l10n/$lang.json').readAsStringSync())
                    as Map),
            locale);
        LocaisStrings.debugLocale = locale;
        tester.view.physicalSize = const Size(440 * 3, 956 * 3);
        tester.view.devicePixelRatio = 3;
        tester.view.padding = const FakeViewPadding(top: 62 * 3, bottom: 34 * 3);
        await tester.pumpWidget(RepaintBoundary(
          key: const Key('shot'),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(fontFamily: 'SF', useMaterial3: true),
            home: HomeCarouselsPreview(page: page),
          ),
        ));
        await tester.pump();
        await tester.pumpAndSettle();
        for (var round = 0; round < 3; round++) {
          final imgs = find.byType(Image).evaluate().toList();
          await tester.runAsync(() async {
            for (final el in imgs) {
              final w = el.widget as Image;
              await precacheImage(w.image, el,
                      onError: (e, _) => debugPrint('IMG ERROR $e'))
                  .timeout(const Duration(seconds: 20),
                      onTimeout: () => debugPrint('IMG TIMEOUT ${w.image}'));
            }
          });
          await tester.pump(const Duration(milliseconds: 200));
        }
        for (var i = 0; i < 6; i++) {
          await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 700)));
          await tester.pump(const Duration(milliseconds: 100));
        }
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
              find.byKey(const Key('shot')));
          final img = await boundary.toImage(pixelRatio: 3);
          final png = await img.toByteData(format: ui.ImageByteFormat.png);
          File('$_out/home_${lang}_p${page + 1}.png')
              .writeAsBytesSync(png!.buffer.asUint8List());
        });
        debugDefaultTargetPlatformOverride = null;
        LocaisStrings.resetDebugLocale();
        addTearDown(tester.view.reset);
      }, _RealHttp()));
    }
  }
}

/// Imagens servidas por um servidor local (a rede do flutter_tester é
/// instável). `https://preview.local/x` vira `http://127.0.0.1:8765/x`.
class _RealHttp extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      _LocalClient(super.createHttpClient(context));
}

class _LocalClient implements HttpClient {
  _LocalClient(this._inner);
  final HttpClient _inner;

  Uri _map(Uri u) => u.host == 'preview.local'
      ? u.replace(scheme: 'http', host: '127.0.0.1', port: 8765)
      : u;

  @override
  Future<HttpClientRequest> getUrl(Uri url) => _inner.getUrl(_map(url));

  @override
  set autoUncompress(bool v) => _inner.autoUncompress = v;

  @override
  bool get autoUncompress => _inner.autoUncompress;

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}
