import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/utils/event_gallery_urls.dart';

void main() {
  group('EventGalleryUrls.resolve', () {
    test('orders cover then photoUrls, dedupes, max 5, https only', () {
      final urls = EventGalleryUrls.resolve({
        'coverUrl': 'https://cdn/a.jpg',
        'photoUrls': [
          'https://cdn/a.jpg',
          'https://cdn/b.jpg',
          'http://insecure/c.jpg',
          'https://cdn/c.jpg',
          '',
          '  ',
          'https://cdn/d.jpg',
          'https://cdn/e.jpg',
          'https://cdn/f.jpg',
        ],
        'logoUrl': 'https://cdn/logo.png',
      });
      expect(urls, [
        'https://cdn/a.jpg',
        'https://cdn/b.jpg',
        'https://cdn/c.jpg',
        'https://cdn/d.jpg',
        'https://cdn/e.jpg',
      ]);
      expect(urls.contains('https://cdn/logo.png'), isFalse);
      expect(urls.contains('https://cdn/f.jpg'), isFalse);
      expect(urls.length, EventGalleryUrls.maxPhotos);
    });

    test('never uses logoUrl; legacy images/photos after photoUrls', () {
      final urls = EventGalleryUrls.resolve({
        'logoUrl': 'https://cdn/logo.png',
        'photoUrls': ['https://cdn/p1.jpg'],
        'images': ['https://cdn/i1.jpg', 'https://cdn/p1.jpg'],
        'photos': ['https://cdn/ph1.jpg'],
      });
      expect(urls, [
        'https://cdn/p1.jpg',
        'https://cdn/i1.jpg',
        'https://cdn/ph1.jpg',
      ]);
    });

    test('single cover keeps gallery list non-empty', () {
      final urls = EventGalleryUrls.resolve({
        'coverUrl': 'https://cdn/only.jpg',
        'logoUrl': 'https://cdn/logo.png',
      });
      expect(urls, ['https://cdn/only.jpg']);
    });

    test('rejects non-https and empty map', () {
      expect(EventGalleryUrls.resolve({}), isEmpty);
      expect(
        EventGalleryUrls.resolve({
          'coverUrl': 'ftp://x/a.jpg',
          'photoUrls': ['not-a-url', '//cdn/x.jpg'],
        }),
        isEmpty,
      );
    });
  });
}
