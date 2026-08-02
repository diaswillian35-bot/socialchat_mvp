import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socialchat_mvp/services/event_calendar_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('wasAdded / markAdded local only', () async {
    expect(await EventCalendarService.wasAdded('evt_1'), isFalse);
    await EventCalendarService.markAdded('evt_1');
    expect(await EventCalendarService.wasAdded('evt_1'), isTrue);
    expect(await EventCalendarService.wasAdded('evt_2'), isFalse);
  });

  test('shareIcs returns alreadyAdded without sharing again', () async {
    await EventCalendarService.markAdded('evt_dup');
    final result = await EventCalendarService.shareIcs(
      eventId: 'evt_dup',
      title: 'ExpoCampo',
      start: DateTime.utc(2027, 3, 10, 14),
      end: DateTime.utc(2027, 3, 14, 22),
      location: 'Campo Mourão',
      description: 'Feira',
      url: 'https://remdy.app/e/evt_dup',
    );
    expect(result, EventCalendarResult.alreadyAdded);
  });
}
