import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/l10n/app_texts.dart';
import 'package:socialchat_mvp/pages/require_profile_completion_page.dart';
import 'package:socialchat_mvp/widgets/interest_chips.dart';
import 'package:socialchat_mvp/widgets/profile_photo_picker.dart';

void main() {
  setUpAll(() {
    final raw = File('lib/l10n/pt-BR.json').readAsStringSync();
    AppTexts.loadFromMap(
      jsonDecode(raw) as Map<String, dynamic>,
      const Locale('pt', 'BR'),
    );
  });

  Map<String, dynamic> base({
    bool photo = true,
    bool bio = true,
    bool interest = true,
  }) =>
      {
        'profileComplete': true,
        'homeCountryCode': 'br',
        'countryLocked': true,
        if (photo) 'photoUrl': 'https://example.com/p.jpg',
        if (bio) 'about': 'Bio já preenchida',
        if (interest) 'interests': ['music'],
      };

  Future<void> pumpPage(
    WidgetTester tester, {
    required Map<String, dynamic> data,
    String? providerPhotoUrl,
    String uid = 'test-uid',
    Future<void> Function(String, Map<String, dynamic>)? onSave,
    Future<void> Function()? onLogout,
    Future<String?> Function(String)? pickPhoto,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: RequireProfileCompletionPage(
          initialData: data,
          providerPhotoUrl: providerPhotoUrl,
          uid: uid,
          onSave: onSave,
          onLogout: onLogout,
          pickPhoto: pickPhoto,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('mostra só a bio quando só ela falta', (tester) async {
    await pumpPage(tester, data: base(bio: false));
    expect(find.text('Complete seu perfil'), findsOneWidget);
    expect(
      find.text('Para continuar usando o Remdy, adicione uma bio.'),
      findsOneWidget,
    );
    expect(find.byType(ProfilePhotoPicker), findsNothing);
    expect(find.byType(InterestChips), findsNothing);
    expect(find.byKey(const Key('require_profile_about')), findsOneWidget);
    expect(find.byKey(const Key('require_profile_logout')), findsOneWidget);
    expect(find.byKey(const Key('require_profile_delete')), findsOneWidget);
    expect(
      tester.widget<PopScope>(find.byType(PopScope).first).canPop,
      isFalse,
    );
  });

  testWidgets('mostra só a foto quando só ela falta', (tester) async {
    await pumpPage(tester, data: base(photo: false));
    expect(
      find.text('Para continuar usando o Remdy, adicione uma foto de perfil.'),
      findsOneWidget,
    );
    expect(find.byType(ProfilePhotoPicker), findsOneWidget);
    expect(find.byType(InterestChips), findsNothing);
    expect(find.byKey(const Key('require_profile_about')), findsNothing);
  });

  testWidgets('mostra só os interesses quando só eles faltam', (tester) async {
    await pumpPage(tester, data: base(interest: false));
    expect(
      find.text(
          'Para continuar usando o Remdy, adicione pelo menos um interesse.'),
      findsOneWidget,
    );
    expect(find.byType(InterestChips), findsOneWidget);
    expect(find.byType(ProfilePhotoPicker), findsNothing);
    expect(find.byKey(const Key('require_profile_about')), findsNothing);
  });

  testWidgets('pré-preenche foto do provedor (Google/Facebook fake) e grava no save',
      (tester) async {
    Map<String, dynamic>? saved;
    await pumpPage(
      tester,
      data: base(photo: false),
      providerPhotoUrl: 'https://lh3.googleusercontent.com/a/fake-user',
      onSave: (uid, payload) async => saved = payload,
    );
    expect(find.byType(ProfilePhotoPicker), findsOneWidget);
    // O binding de teste responde 400 a qualquer HTTP; a URL já está no estado.
    await tester.pump();
    tester.takeException();
    await tester.tap(find.byKey(const Key('require_profile_save')));
    await tester.pump();
    await tester.pump();
    expect(saved, isNotNull);
    expect(saved!['photoUrl'],
        'https://lh3.googleusercontent.com/a/fake-user');
    expect(saved!['profilePhotoUrl'],
        'https://lh3.googleusercontent.com/a/fake-user');
    expect(saved!.containsKey('about'), isFalse);
    expect(saved!.containsKey('interests'), isFalse);
  });

  testWidgets('foto rejeitada (photoUrl limpo) bloqueia o save sem foto',
      (tester) async {
    var called = false;
    await pumpPage(
      tester,
      data: {
        ...base(photo: false),
        'photoUrl': '',
        'profilePhotoUrl': '',
      },
      onSave: (_, __) async => called = true,
    );
    await tester.tap(find.byKey(const Key('require_profile_save')));
    await tester.pump();
    await tester.pump();
    expect(called, isFalse);
    expect(find.text('Adicione uma foto de perfil para continuar.'),
        findsAtLeastNWidgets(1));
  });

  testWidgets('Sair dispara onLogout', (tester) async {
    var loggedOut = false;
    await pumpPage(
      tester,
      data: base(bio: false),
      onLogout: () async => loggedOut = true,
    );
    await tester.tap(find.byKey(const Key('require_profile_logout')));
    await tester.pump();
    await tester.pump();
    expect(loggedOut, isTrue);
  });

  testWidgets('salvar bio chama onSave só com about', (tester) async {
    Map<String, dynamic>? saved;
    await pumpPage(
      tester,
      data: base(bio: false),
      onSave: (uid, payload) async => saved = payload,
    );
    await tester.enterText(
      find.byKey(const Key('require_profile_about')),
      'Nova bio do teste',
    );
    await tester.tap(find.byKey(const Key('require_profile_save')));
    await tester.pump();
    await tester.pump();
    expect(saved, isNotNull);
    expect(saved!['about'], 'Nova bio do teste');
    expect(saved!['profileComplete'], isTrue);
    expect(saved!.containsKey('photoUrl'), isFalse);
  });
}
