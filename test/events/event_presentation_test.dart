import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/models/event_presentation.dart';
import 'package:socialchat_mvp/services/iso_country_names.dart';

void main() {
  test('locationLine uses ISO country name, not hardcoded country', () {
    final e = EventPresentation.fromMap('1', {
      'title': 'T',
      'city': 'paris',
      'stateName': 'IDF',
      'countryCode': 'fr',
      'isActive': true,
      'status': 'approved',
    });
    final line = e.locationLine('en');
    expect(line.contains('Paris'), isTrue);
    expect(line.toLowerCase().contains('brazil'), isFalse);
    expect(line.contains(IsoCountryNames.displayName('fr', 'en')), isTrue);
  });

  test('old event without cover still builds', () {
    final e = EventPresentation.fromMap('old', {
      'title': 'Legacy',
      'startAt': null,
    });
    expect(e.primaryImageUrl, isEmpty);
    expect(e.hasGallery, isFalse);
    expect(e.hasSchedule, isFalse);
  });
}
