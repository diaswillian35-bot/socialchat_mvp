import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/services/user_avatar_resolver.dart';

void main() {
  group('UserAvatarResolver', () {
    test('prefers photoUrl when present', () {
      expect(
        UserAvatarResolver.resolve({
          'photoUrl': 'https://cdn.example.com/a.jpg',
          'profilePhotoUrl': 'https://cdn.example.com/b.jpg',
        }),
        'https://cdn.example.com/a.jpg',
      );
    });

    test('falls back to profilePhotoUrl for new accounts', () {
      expect(
        UserAvatarResolver.resolve({
          'profilePhotoUrl': 'https://lh3.googleusercontent.com/photo',
        }),
        'https://lh3.googleusercontent.com/photo',
      );
    });

    test('rejects non-https and empty values', () {
      expect(UserAvatarResolver.sanitize('http://insecure.example/x'), '');
      expect(UserAvatarResolver.sanitize('not-a-url'), '');
      expect(UserAvatarResolver.sanitize('null'), '');
      expect(UserAvatarResolver.resolve({'photoUrl': ''}), '');
    });

    test('initialFor handles empty and unicode', () {
      expect(UserAvatarResolver.initialFor(''), '?');
      expect(UserAvatarResolver.initialFor('willian'), 'W');
    });
  });
}
