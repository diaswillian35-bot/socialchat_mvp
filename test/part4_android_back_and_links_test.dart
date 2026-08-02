import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/services/android_back_navigation.dart';
import 'package:socialchat_mvp/services/message_link_utils.dart';
import 'package:socialchat_mvp/utils/chat_message_list_stability.dart';
import 'package:socialchat_mvp/widgets/link_preview_card.dart';

void main() {
  group('AndroidBackNavigation', () {
    test('teclado fecha antes da rota', () {
      final d = AndroidBackNavigation.decide(
        keyboardOpen: true,
        currentTabIndex: 2,
        lastExitPromptAt: null,
        now: DateTime(2026, 1, 1),
      );
      expect(d, AndroidBackDecision.dismissKeyboard);
    });

    test('aba principal volta para Home', () {
      final d = AndroidBackNavigation.decide(
        keyboardOpen: false,
        currentTabIndex: 3,
        lastExitPromptAt: null,
        now: DateTime(2026, 1, 1),
      );
      expect(d, AndroidBackDecision.goHomeTab);
    });

    test('primeiro toque na Home não fecha', () {
      final d = AndroidBackNavigation.decide(
        keyboardOpen: false,
        currentTabIndex: 0,
        lastExitPromptAt: null,
        now: DateTime(2026, 1, 1, 12),
      );
      expect(d, AndroidBackDecision.showExitHint);
    });

    test('segundo toque dentro do prazo permite sair', () {
      final first = DateTime(2026, 1, 1, 12, 0, 0);
      final second = first.add(const Duration(milliseconds: 1500));
      final d = AndroidBackNavigation.decide(
        keyboardOpen: false,
        currentTabIndex: 0,
        lastExitPromptAt: first,
        now: second,
      );
      expect(d, AndroidBackDecision.allowExit);
    });

    test('prazo vencido exige novamente dois toques', () {
      final first = DateTime(2026, 1, 1, 12, 0, 0);
      final later = first.add(const Duration(seconds: 3));
      final d = AndroidBackNavigation.decide(
        keyboardOpen: false,
        currentTabIndex: 0,
        lastExitPromptAt: first,
        now: later,
      );
      expect(d, AndroidBackDecision.showExitHint);
    });

    test('rota push/deep link segura exige shell sob destino', () {
      expect(
        AndroidBackNavigation.isSafeBackStack(shellUnderDestination: true),
        isTrue,
      );
      expect(
        AndroidBackNavigation.isSafeBackStack(shellUnderDestination: false),
        isFalse,
      );
    });

    test('voltar não encerra presença', () {
      expect(
        AndroidBackNavigation.shouldAffectPresenceOnInternalBack(),
        isFalse,
      );
    });
  });

  group('MessageLinkUtils', () {
    test('URL dentro de texto', () {
      final links = MessageLinkUtils.extractLinks(
        'veja https://amazon.com/dp/ABC e compre',
      );
      expect(links.length, 1);
      expect(links.first.normalizedHttpsUrl, contains('amazon.com'));
    });

    test('mais de um link', () {
      final links = MessageLinkUtils.extractLinks(
        'a https://a.com e https://b.org fim',
      );
      expect(links.length, 2);
    });

    test('domínio com e sem https', () {
      final a = MessageLinkUtils.normalizeToHttps('amazon.com/x');
      final b = MessageLinkUtils.normalizeToHttps('https://amazon.com/x');
      expect(a, 'https://amazon.com/x');
      expect(b, 'https://amazon.com/x');
    });

    test('pontuação depois do link', () {
      final links = MessageLinkUtils.extractLinks('abra amazon.com.');
      expect(links.length, 1);
      expect(links.first.raw.endsWith('.'), isFalse);
    });

    test('não transforma e-mail em link', () {
      final links = MessageLinkUtils.extractLinks('fale em user@mail.com ok');
      expect(links, isEmpty);
    });

    test('bloqueio de esquemas perigosos', () {
      expect(MessageLinkUtils.normalizeToHttps('javascript:alert(1)'), isNull);
      expect(MessageLinkUtils.normalizeToHttps('data:text/html,x'), isNull);
      expect(MessageLinkUtils.normalizeToHttps('file:///etc/passwd'), isNull);
      expect(MessageLinkUtils.normalizeToHttps('intent://x'), isNull);
      expect(MessageLinkUtils.normalizeToHttps('content://x'), isNull);
    });

    test('links oficiais do Remdy', () {
      final links = MessageLinkUtils.extractLinks(
        'entre https://remdy.app/g/ABC123',
      );
      expect(links.length, 1);
      expect(links.first.isRemdyInternal, isTrue);
      expect(MessageLinkUtils.isRemdyHost('www.remdy.app'), isTrue);
    });

    test('punycode / internacional host', () {
      final n = MessageLinkUtils.normalizeToHttps('https://xn--fsq.com');
      expect(n, isNotNull);
      expect(n!.startsWith('https://'), isTrue);
    });

    test('IP privado bloqueado no cliente', () {
      expect(MessageLinkUtils.isPrivateOrLocalIp('127.0.0.1'), isTrue);
      expect(MessageLinkUtils.isPrivateOrLocalIp('10.0.0.1'), isTrue);
      expect(MessageLinkUtils.isPrivateOrLocalIp('192.168.1.1'), isTrue);
      expect(MessageLinkUtils.isPrivateOrLocalIp('169.254.169.254'), isTrue);
      expect(MessageLinkUtils.isPrivateOrLocalIp('::1'), isTrue);
      expect(MessageLinkUtils.isPrivateOrLocalIp('fc00::1'), isTrue);
      expect(MessageLinkUtils.isPrivateOrLocalIp('8.8.8.8'), isFalse);
    });

    test('mensagem antiga sem metadados', () {
      expect(LinkPreviewData.fromMap(null), isNull);
      expect(LinkPreviewData.fromMap(<String, dynamic>{}), isNull);
    });

    test('mesma chave/ID antes e depois da prévia', () {
      const id = 'msgAbc123';
      final before = ChatMessageListStability.bubbleKey(id);
      final after = ChatMessageListStability.bubbleKey(id);
      expect(before, after);
      expect(before, 'msg_$id');
    });

    test('falha da prévia não impede envio (candidato opcional)', () {
      // Sem link → sem prévia; envio segue normalmente.
      expect(MessageLinkUtils.firstPreviewCandidate('olá mundo'), isNull);
      // Com link → candidato existe, mas falha da CF é tratada no service.
      expect(
        MessageLinkUtils.firstPreviewCandidate('veja amazon.com/dp/1'),
        isNotNull,
      );
    });

    test('displayDomain evita engano por subdomínio', () {
      expect(
        MessageLinkUtils.displayDomain('evil.amazon.com'),
        'amazon.com',
      );
      expect(
        MessageLinkUtils.displayDomain('shop.example.com.br'),
        'example.com.br',
      );
    });
  });
}
