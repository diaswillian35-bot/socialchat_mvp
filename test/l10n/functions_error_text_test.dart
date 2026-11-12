import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/l10n/app_texts.dart';
import 'package:socialchat_mvp/services/functions_error_text.dart';

void main() {
  setUp(() {
    AppTexts.loadFromMap({
      'fn_error_generic': 'Não foi possível concluir. Tente novamente.',
      'group_premium_other_country':
          'Este grupo é de outro país. Recurso disponível no Premium.',
    });
  });

  test('usa details.i18nKey via AppTexts', () {
    final e = FirebaseFunctionsException(
      code: 'failed-precondition',
      message: 'Premium required for international groups.',
      details: {'i18nKey': 'group_premium_other_country'},
    );
    expect(
      functionsErrorText(e),
      'Este grupo é de outro país. Recurso disponível no Premium.',
    );
  });

  test('sem chave cai no fallback', () {
    final e = FirebaseFunctionsException(
      code: 'internal',
      message: 'weird-unknown',
    );
    expect(functionsErrorText(e), 'weird-unknown');
  });
}
