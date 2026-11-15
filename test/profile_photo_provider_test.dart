import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/services/profile_photo.dart';

void main() {
  test('pré-preenche photoURL direto do provedor', () {
    expect(
      ProfilePhoto.providerPhotoUrlFrom(
          photoURL: 'https://lh3.googleusercontent.com/a/fake'),
      'https://lh3.googleusercontent.com/a/fake',
    );
  });

  test('cai no providerData quando photoURL está vazio (Facebook/Google)', () {
    expect(
      ProfilePhoto.providerPhotoUrlFrom(
        photoURL: '',
        providerPhotoURLs: [
          '',
          'https://graph.facebook.com/v19.0/me/picture',
        ],
      ),
      'https://graph.facebook.com/v19.0/me/picture',
    );
  });

  test('ignora valores que não começam com http', () {
    expect(
      ProfilePhoto.providerPhotoUrlFrom(
        photoURL: 'gs://bucket/x.jpg',
        providerPhotoURLs: ['file://local.jpg', ''],
      ),
      '',
    );
    expect(ProfilePhoto.providerPhotoUrl(null), '');
  });
}
