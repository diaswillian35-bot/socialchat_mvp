import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/services/app_language_sync.dart';

void main() {
  group('AppLanguageSync.normalize', () {
    test('aceita os 5 códigos canónicos', () {
      expect(AppLanguageSync.normalize('pt-BR'), 'pt-BR');
      expect(AppLanguageSync.normalize('pt-PT'), 'pt-PT');
      expect(AppLanguageSync.normalize('en'), 'en');
      expect(AppLanguageSync.normalize('es'), 'es');
      expect(AppLanguageSync.normalize('fr'), 'fr');
    });

    test('normaliza variantes para o formato do servidor', () {
      expect(AppLanguageSync.normalize('pt_BR'), 'pt-BR');
      expect(AppLanguageSync.normalize('pt_br'), 'pt-BR');
      expect(AppLanguageSync.normalize('PT-BR'), 'pt-BR');
      expect(AppLanguageSync.normalize('pt'), 'pt-BR');
      expect(AppLanguageSync.normalize('pt-br-x-foo'), 'pt-BR');
      expect(AppLanguageSync.normalize('pt_PT'), 'pt-PT');
      expect(AppLanguageSync.normalize('PT-PT'), 'pt-PT');
      expect(AppLanguageSync.normalize('pt-PT-x-foo'), 'pt-PT');
      expect(AppLanguageSync.normalize('EN'), 'en');
      expect(AppLanguageSync.normalize('en-US'), 'en');
      expect(AppLanguageSync.normalize('en_GB'), 'en');
      expect(AppLanguageSync.normalize('ES-MX'), 'es');
      expect(AppLanguageSync.normalize('fr-FR'), 'fr');
      expect(AppLanguageSync.normalize('  en  '), 'en');
    });

    test('vazio ou desconhecido cai em en, como no servidor', () {
      expect(AppLanguageSync.normalize(null), 'en');
      expect(AppLanguageSync.normalize(''), 'en');
      expect(AppLanguageSync.normalize('   '), 'en');
      expect(AppLanguageSync.normalize('de'), 'en');
      expect(AppLanguageSync.normalize('it'), 'en');
      expect(AppLanguageSync.normalize('zh-CN'), 'en');
    });
  });

  group('AppLanguageSync.needsWrite', () {
    test('não pede escrita quando o valor gravado já é o canónico', () {
      expect(AppLanguageSync.needsWrite('pt-BR', 'pt-BR'), isFalse);
      expect(AppLanguageSync.needsWrite('pt-PT', 'pt-PT'), isFalse);
      expect(AppLanguageSync.needsWrite('en', 'en'), isFalse);
      expect(AppLanguageSync.needsWrite('es', 'es'), isFalse);
      expect(AppLanguageSync.needsWrite('fr', 'fr'), isFalse);
      expect(AppLanguageSync.needsWrite('en', 'en-US'), isFalse);
      expect(AppLanguageSync.needsWrite('pt-BR', 'pt'), isFalse);
    });

    test('pede escrita se o campo falta ou difere', () {
      expect(AppLanguageSync.needsWrite(null, 'pt-BR'), isTrue);
      expect(AppLanguageSync.needsWrite('', 'en'), isTrue);
      expect(AppLanguageSync.needsWrite('en', 'pt-BR'), isTrue);
      expect(AppLanguageSync.needsWrite('pt-BR', 'pt-PT'), isTrue);
      expect(AppLanguageSync.needsWrite('pt-br', 'pt-BR'), isTrue);
      expect(AppLanguageSync.needsWrite('EN', 'en'), isTrue);
    });
  });
}
