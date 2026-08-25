import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/l10n/app_texts.dart';
import 'package:socialchat_mvp/widgets/link_preview_card.dart';

/// Controlled clock + no rootBundle / no real network for link-preview widgets.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Map<String, dynamic> ptBr;

  setUpAll(() {
    ptBr = jsonDecode(File('lib/l10n/pt-BR.json').readAsStringSync())
        as Map<String, dynamic>;
  });

  setUp(() {
    AppTexts.loadFromMap(ptBr, const Locale('pt', 'BR'));
  });

  group('unit: LinkPreviewData / slot (DM≡group)', () {
    test('fromMap Open Graph completo', () {
      final data = LinkPreviewData.fromMap({
        'url': 'https://example.com/a',
        'domain': 'example.com',
        'title': 'Título',
        'description': 'Desc',
        'imageUrl': 'https://cdn.example.com/i.png',
      });
      expect(data, isNotNull);
      expect(data!.title, 'Título');
      expect(data.imageUrl, contains('https://'));
      expect(data.fallback, isFalse);
    });

    test('fromMap sem imagem', () {
      final data = LinkPreviewData.fromMap({
        'url': 'https://example.com/a',
        'domain': 'example.com',
        'title': 'Só título',
      });
      expect(data!.imageUrl, isEmpty);
    });

    test('Instagram fallback provider', () {
      final data = LinkPreviewData.fromMap({
        'url': 'https://www.instagram.com/p/abc/',
        'domain': 'instagram.com',
        'title': 'Instagram post',
        'provider': 'instagram',
        'fallback': true,
        'imageUrl': '',
      });
      expect(data!.isInstagram, isTrue);
      expect(data.fallback, isTrue);
    });

    test('URL inválida → fromMap null', () {
      expect(LinkPreviewData.fromMap({'url': 'javascript:alert(1)'}), isNull);
      expect(LinkPreviewData.fromMap({'url': ''}), isNull);
      expect(LinkPreviewData.fromMap(null), isNull);
    });

    test('pending → loading; ready → card; failed → none', () {
      const text = 'veja https://www.instagram.com/p/abc/';
      expect(
        LinkPreviewSlot.resolve(
          isDeleted: false,
          preview: null,
          status: 'pending',
          messageText: text,
        ),
        LinkPreviewSlotKind.loading,
      );

      final ready = LinkPreviewData.fromMap({
        'url': 'https://example.com/a',
        'domain': 'example.com',
        'title': 'OK',
        'imageUrl': 'https://cdn.example.com/i.png',
      });
      expect(
        LinkPreviewSlot.resolve(
          isDeleted: false,
          preview: ready,
          status: 'ready',
          messageText: text,
        ),
        LinkPreviewSlotKind.card,
      );

      expect(
        LinkPreviewSlot.resolve(
          isDeleted: false,
          preview: null,
          status: 'failed',
          messageText: text,
        ),
        LinkPreviewSlotKind.none,
      );
    });

    test('l10n keys Instagram/loading presentes nos 5 idiomas', () {
      for (final lang in ['pt-BR', 'en', 'es', 'fr', 'pt-PT']) {
        final json = File('lib/l10n/$lang.json').readAsStringSync();
        expect(json.contains('link_preview_instagram_post'), isTrue,
            reason: lang);
        expect(json.contains('link_preview_loading'), isTrue, reason: lang);
      }
    });

    test('DM and group pages both mount LinkPreviewInBubble', () {
      final chat = File('lib/pages/chat_page.dart').readAsStringSync();
      final group = File('lib/pages/group_chat_page.dart').readAsStringSync();
      expect(chat.contains('LinkPreviewInBubble('), isTrue);
      expect(group.contains('LinkPreviewInBubble('), isTrue);
      expect(chat.contains('LinkPreviewLoadingCard('), isFalse);
      expect(group.contains('LinkPreviewLoadingCard('), isFalse);
      final src = File('lib/services/outgoing_text_message_service.dart')
          .readAsStringSync();
      expect(src.contains('LinkPreviewService.requestPreviewForMessage'), isTrue);
    });
  });

  group('widgets: controlled clock / no network', () {
    Future<void> pumpPreview(
      WidgetTester tester, {
      required Widget child,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: child,
            ),
          ),
        ),
      );
      // One frame only — never pumpAndSettle (indeterminate animations).
      await tester.pump();
    }

    Future<void> disposeTree(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      // Flush any residual frame callbacks without spinning forever.
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.binding.transientCallbackCount, 0);
    }

    final tinyPng = MemoryImage(
      UriData.parse(
        'data:image/png;base64,'
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
      ).contentAsBytes(),
    );

    testWidgets('pending mostra loading (sem ticker infinito)', (tester) async {
      await pumpPreview(
        tester,
        child: const LinkPreviewInBubble(
          isMe: false,
          isDeleted: false,
          messageText: 'https://example.com/x',
          linkPreviewStatus: 'pending',
          animateLoading: false,
        ),
      );

      expect(find.byType(LinkPreviewLoadingCard), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Carregando prévia…'), findsOneWidget);
      expect(find.byType(LinkPreviewCard), findsNothing);
      // Determinate → no animation ticker left running.
      expect(tester.binding.transientCallbackCount, 0);

      await disposeTree(tester);
    });

    testWidgets('ready mostra o card com imagem local (sem HTTP)', (tester) async {
      final data = LinkPreviewData.fromMap({
        'url': 'https://example.com/post',
        'domain': 'example.com',
        'title': 'Título OG',
        'description': 'Desc',
        'imageUrl': 'https://cdn.example.com/real.png',
      })!;

      await pumpPreview(
        tester,
        child: LinkPreviewInBubble(
          isMe: false,
          isDeleted: false,
          messageText: 'https://example.com/post',
          linkPreviewStatus: 'ready',
          linkPreview: data,
          imageProviderOverride: tinyPng,
        ),
      );

      expect(find.byType(LinkPreviewCard), findsOneWidget);
      expect(find.text('Título OG'), findsOneWidget);
      expect(find.text('example.com'), findsOneWidget);
      expect(find.byType(LinkPreviewLoadingCard), findsNothing);
      expect(find.byIcon(Icons.camera_alt_rounded), findsNothing);

      await disposeTree(tester);
    });

    testWidgets('fallback Instagram aparece sem imagem remota', (tester) async {
      final data = LinkPreviewData.fromMap({
        'url': 'https://www.instagram.com/p/abc/',
        'domain': 'instagram.com',
        'provider': 'instagram',
        'fallback': true,
        'title': '',
        'imageUrl': '',
      })!;

      await pumpPreview(
        tester,
        child: LinkPreviewInBubble(
          isMe: false,
          isDeleted: false,
          messageText: 'https://www.instagram.com/p/abc/',
          linkPreviewStatus: 'ready',
          linkPreview: data,
        ),
      );

      expect(find.byType(LinkPreviewCard), findsOneWidget);
      expect(find.text('Publicação no Instagram'), findsOneWidget);
      expect(find.text('instagram.com'), findsOneWidget);
      expect(find.byIcon(Icons.camera_alt_rounded), findsOneWidget);
      // No NetworkImage path when fallback + empty imageUrl.
      expect(find.byType(Image), findsNothing);

      await disposeTree(tester);
    });

    testWidgets('failed mantém mensagem+URL e não mostra card', (tester) async {
      const url = 'https://www.instagram.com/p/fail/';
      await pumpPreview(
        tester,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Olá $url'),
            LinkPreviewInBubble(
              isMe: false,
              isDeleted: false,
              messageText: 'Olá $url',
              linkPreviewStatus: 'failed',
            ),
          ],
        ),
      );

      expect(find.textContaining(url), findsOneWidget);
      expect(find.byType(LinkPreviewCard), findsNothing);
      expect(find.byType(LinkPreviewLoadingCard), findsNothing);

      await disposeTree(tester);
    });

    testWidgets('transição pending → fallback/ready', (tester) async {
      final status = ValueNotifier<String>('pending');
      final preview = ValueNotifier<LinkPreviewData?>(null);
      addTearDown(status.dispose);
      addTearDown(preview.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AnimatedBuilder(
              animation: Listenable.merge([status, preview]),
              builder: (_, __) => LinkPreviewInBubble(
                isMe: true,
                isDeleted: false,
                messageText: 'https://www.instagram.com/p/xyz/',
                linkPreviewStatus: status.value,
                linkPreview: preview.value,
                animateLoading: false,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(LinkPreviewLoadingCard), findsOneWidget);

      preview.value = LinkPreviewData.fromMap({
        'url': 'https://www.instagram.com/p/xyz/',
        'domain': 'instagram.com',
        'provider': 'instagram',
        'fallback': true,
        'imageUrl': '',
      });
      status.value = 'ready';
      await tester.pump();

      expect(find.byType(LinkPreviewLoadingCard), findsNothing);
      expect(find.byType(LinkPreviewCard), findsOneWidget);
      expect(find.byIcon(Icons.camera_alt_rounded), findsOneWidget);
      expect(tester.binding.transientCallbackCount, 0);

      await disposeTree(tester);
    });

    testWidgets('DM e grupo: mesmo slot resolve loading/card/none', (tester) async {
      // Behavioral parity is the shared LinkPreviewInBubble used by both pages.
      const text = 'link https://example.com/a';
      for (final isMe in [false, true]) {
        expect(
          LinkPreviewSlot.resolve(
            isDeleted: false,
            preview: null,
            status: 'pending',
            messageText: text,
          ),
          LinkPreviewSlotKind.loading,
        );
        await pumpPreview(
          tester,
          child: LinkPreviewInBubble(
            isMe: isMe,
            isDeleted: false,
            messageText: text,
            linkPreviewStatus: 'pending',
            animateLoading: false,
          ),
        );
        expect(find.byType(LinkPreviewLoadingCard), findsOneWidget);
        await disposeTree(tester);
      }
    });

    testWidgets('loading animado: dispose cancela ticker (sem hang)', (tester) async {
      await pumpPreview(
        tester,
        child: const LinkPreviewLoadingCard(isMe: false, animate: true),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      // Indeterminate registers a ticker while mounted.
      expect(tester.binding.transientCallbackCount, greaterThan(0));

      await disposeTree(tester);
      expect(tester.binding.transientCallbackCount, 0);
    });
  });
}
