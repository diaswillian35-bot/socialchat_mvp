import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/services/profile_completion.dart';

Map<String, dynamic> complete({
  bool photo = true,
  bool bio = true,
  bool interest = true,
  bool profileComplete = true,
  bool country = true,
  bool language = true,
}) =>
    {
      'profileComplete': profileComplete,
      if (photo) 'photoUrl': 'https://example.com/p.jpg',
      if (bio) 'about': 'Olá, eu moro no Paraná.',
      if (interest) 'interests': ['music', 'tech'],
      if (country) ...{
        'homeCountryCode': 'br',
        'countryLocked': true,
      },
      if (language) 'languages': 'Português',
    };

void main() {
  group('ProfileCompletion', () {
    test('foto válida só com URL http(s)', () {
      expect(ProfileCompletion.hasPhoto({'photoUrl': 'https://x.com/a.jpg'}),
          isTrue);
      expect(
          ProfileCompletion.hasPhoto({'profilePhotoUrl': 'http://x.com/a.jpg'}),
          isTrue);
      expect(ProfileCompletion.hasPhoto({'photoURL': 'https://x.com/a.jpg'}),
          isTrue);
      expect(ProfileCompletion.hasPhoto({'photoUrl': ''}), isFalse);
      expect(ProfileCompletion.hasPhoto({'photoUrl': 'gs://bucket/a.jpg'}),
          isFalse);
      expect(ProfileCompletion.hasPhoto(null), isFalse);
    });

    test('foto pendente de moderação (URL http) conta', () {
      expect(
        ProfileCompletion.hasPhoto({
          'photoUrl': 'https://storage.googleapis.com/pending/a.jpg',
          'moderation': {'status': 'pending'},
        }),
        isTrue,
      );
    });

    test('bio e interesse', () {
      expect(ProfileCompletion.hasBio({'about': '  oi  '}), isTrue);
      expect(ProfileCompletion.hasBio({'about': '   '}), isFalse);
      expect(ProfileCompletion.hasBio({}), isFalse);
      expect(ProfileCompletion.hasInterest({'interests': ['music']}), isTrue);
      expect(ProfileCompletion.hasInterest({'interests': ['nao-existe']}),
          isFalse);
      expect(ProfileCompletion.hasInterest({'interests': []}), isFalse);
    });

    test('idioma: languages ou nativeLanguage', () {
      expect(ProfileCompletion.hasLanguage({'languages': 'pt'}), isTrue);
      expect(ProfileCompletion.hasLanguage({'nativeLanguage': 'en'}), isTrue);
      expect(ProfileCompletion.hasLanguage({}), isFalse);
    });

    test('conta nova (!profileComplete) vai para Completar perfil', () {
      final data = complete(profileComplete: false, photo: false, bio: false, interest: false);
      expect(ProfileCompletion.needsInitialCompletion(data), isTrue);
      expect(ProfileCompletion.needsRepair(data), isFalse);
    });

    test('conta antiga completa na flag mas sem foto, bio ou interesse', () {
      expect(ProfileCompletion.needsRepair(complete(photo: false)), isTrue);
      expect(ProfileCompletion.needsRepair(complete(bio: false)), isTrue);
      expect(ProfileCompletion.needsRepair(complete(interest: false)), isTrue);
      expect(ProfileCompletion.needsRepair(complete()), isFalse);
    });

    test('foto rejeitada (photoUrl limpo) pede correção', () {
      final data = complete()
        ..['photoUrl'] = ''
        ..['profilePhotoUrl'] = ''
        ..remove('photoURL');
      expect(ProfileCompletion.hasPhoto(data), isFalse);
      expect(ProfileCompletion.needsRepair(data), isTrue);
      expect(ProfileCompletion.bodyKeyFromData(data),
          'profile_complete_body_photo');
    });

    test('textos do corpo conforme o que falta', () {
      expect(
        ProfileCompletion.bodyKey(
            needPhoto: true, needBio: true, needInterest: true),
        'profile_complete_body_all',
      );
      expect(
        ProfileCompletion.bodyKey(
            needPhoto: true, needBio: false, needInterest: false),
        'profile_complete_body_photo',
      );
      expect(
        ProfileCompletion.bodyKey(
            needPhoto: false, needBio: true, needInterest: false),
        'profile_complete_body_bio',
      );
      expect(
        ProfileCompletion.bodyKey(
            needPhoto: false, needBio: false, needInterest: true),
        'profile_complete_body_interest',
      );
      expect(
        ProfileCompletion.bodyKey(
            needPhoto: true, needBio: true, needInterest: false),
        'profile_complete_body_photo_bio',
      );
      expect(
        ProfileCompletion.bodyKey(
            needPhoto: true, needBio: false, needInterest: true),
        'profile_complete_body_photo_interest',
      );
      expect(
        ProfileCompletion.bodyKey(
            needPhoto: false, needBio: true, needInterest: true),
        'profile_complete_body_bio_interest',
      );
    });

    test('validateForSave exige os três', () {
      expect(
        ProfileCompletion.validateForSave(
            photoUrl: '', about: 'bio', interests: ['music']),
        'profile_photo_required',
      );
      expect(
        ProfileCompletion.validateForSave(
            photoUrl: 'https://x.com/a.jpg', about: '  ', interests: ['music']),
        'profile_bio_required',
      );
      expect(
        ProfileCompletion.validateForSave(
            photoUrl: 'https://x.com/a.jpg', about: 'bio', interests: []),
        'profile_interest_required',
      );
      expect(
        ProfileCompletion.validateForSave(
            photoUrl: 'https://x.com/a.jpg',
            about: 'bio',
            interests: ['music']),
        isNull,
      );
    });

    test('repairPayload só inclui o que faltava', () {
      final payload = ProfileCompletion.repairPayload(
        needPhoto: true,
        photoUrl: 'https://x.com/a.jpg',
        needBio: false,
        about: 'não deve entrar',
        needInterest: true,
        interests: ['music', 'fake'],
      );
      expect(payload['profileComplete'], isTrue);
      expect(payload['photoUrl'], 'https://x.com/a.jpg');
      expect(payload['profilePhotoUrl'], 'https://x.com/a.jpg');
      expect(payload.containsKey('about'), isFalse);
      expect(payload['interests'], ['music']);
    });
  });

  group('ProfileAccessGate', () {
    test('sem idade verificada', () {
      expect(
        ProfileAccessGate.next(ageVerified: false, data: complete()),
        ProfileAccessStep.age,
      );
    });

    test('cadastro novo (e-mail/Google/Facebook) sem perfil completo', () {
      for (final data in [
        null,
        complete(profileComplete: false),
        {
          'profileComplete': false,
          'photoUrl': 'https://lh3.googleusercontent.com/a/x',
        },
        {
          'profileComplete': false,
          'photoUrl': 'https://graph.facebook.com/v/pic',
        },
      ]) {
        expect(
          ProfileAccessGate.next(ageVerified: true, data: data),
          ProfileAccessStep.initialCompletion,
        );
      }
    });

    test('sem país travado vai para Completar perfil', () {
      expect(
        ProfileAccessGate.next(
          ageVerified: true,
          data: complete()..['countryLocked'] = false,
        ),
        ProfileAccessStep.initialCompletion,
      );
      expect(
        ProfileAccessGate.next(
          ageVerified: true,
          data: complete()..['homeCountryCode'] = '',
        ),
        ProfileAccessStep.initialCompletion,
      );
    });

    test('conta antiga sem foto, bio ou interesse vai para a tela nova', () {
      expect(
        ProfileAccessGate.next(
            ageVerified: true, data: complete(photo: false)),
        ProfileAccessStep.repairCompletion,
      );
      expect(
        ProfileAccessGate.next(ageVerified: true, data: complete(bio: false)),
        ProfileAccessStep.repairCompletion,
      );
      expect(
        ProfileAccessGate.next(
            ageVerified: true, data: complete(interest: false)),
        ProfileAccessStep.repairCompletion,
      );
    });

    test('perfil pronto segue para a Home', () {
      expect(
        ProfileAccessGate.next(ageVerified: true, data: complete()),
        ProfileAccessStep.ready,
      );
    });
  });
}
