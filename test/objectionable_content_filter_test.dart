import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/services/message_moderation.dart';
import 'package:socialchat_mvp/services/objectionable_content_filter.dart';

void main() {
  setUp(ObjectionableContentFilter.resetDomainsForTest);

  test('falsos positivos passam', () {
    for (final sample in [
      'vou matar a fome',
      'sexta-feira',
      'Essex',
      'documento.pdf',
      'privacy policy do app',
    ]) {
      expect(ObjectionableContentFilter.evaluate(sample), isNull, reason: sample);
    }
  });

  test('não bloqueia nude, pedofilia, violer nem kill you soltos', () {
    for (final sample in [
      'batom nude',
      'odeio pedofilia, tem que denunciar',
      'violer la loi',
      'this will kill you',
      'vou matar a fome',
    ]) {
      expect(ObjectionableContentFilter.evaluate(sample), isNull, reason: sample);
    }
  });

  test('leetspeak e letras separadas bloqueiam', () {
    expect(ObjectionableContentFilter.evaluate('p0rn')?.reason, 'text_adult');
    expect(ObjectionableContentFilter.evaluate('0nlyfans')?.reason, 'text_adult');
    expect(ObjectionableContentFilter.evaluate('x v i d e o s')?.reason, 'text_adult');
  });

  test('casos positivos', () {
    expect(ObjectionableContentFilter.evaluate('onlyfans.com/x')?.reason, 'link_adult');
    expect(
      ObjectionableContentFilter.evaluate('entra no onlyfans ponto com/x')?.reason,
      'link_adult',
    );
    expect(ObjectionableContentFilter.evaluate('only fans . com')?.reason, 'link_adult');
    expect(ObjectionableContentFilter.evaluate('vendo nudes')?.reason, 'text_adult');
    expect(ObjectionableContentFilter.evaluate('vou te matar')?.reason, 'text_adult');
    expect(
      ObjectionableContentFilter.evaluate('pornografia infantil')?.reason,
      'csam',
    );
  });

  test('balão bloqueado não abre imagem e a prévia não usa o texto cru', () {
    expect(
      MessageModeration.hidesImage(status: 'blocked', isMe: true, type: 'image'),
      isTrue,
    );
    expect(
      MessageModeration.hidesImage(status: 'review', isMe: false, type: 'image'),
      isTrue,
    );
    expect(
      MessageModeration.hidesImage(status: 'review', isMe: true, type: 'image'),
      isFalse,
    );
    expect(
      MessageModeration.hidesText(status: 'blocked', type: 'text'),
      isTrue,
    );
    expect(
      MessageModeration.inboxPreview(
        data: {'lastMessageModeration': 'blocked', 'lastMessageType': 'text'},
        raw: 'onlyfans.com/x',
        imageLabel: 'img',
        textLabel: 'txt',
      ),
      'txt',
    );
  });

  test('suspenso some das listas', () {
    expect(
      ModerationVisibility.isHiddenFromLists({
        'moderation': {'status': 'suspended_pending_review'},
      }),
      isTrue,
    );
    expect(ModerationVisibility.isHiddenFromLists({'name': 'Ana'}), isFalse);
  });
}
