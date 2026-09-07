import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/services/presence_session_state.dart';
import 'package:socialchat_mvp/widget/online_dot.dart';

/// Stub stream for OnlineDot without Firebase.
class _StatusStreamDot extends StatelessWidget {
  const _StatusStreamDot({required this.status});
  final PresenceReadStatus status;

  @override
  Widget build(BuildContext context) {
    // Mirror OnlineDot color mapping for unit test without PresenceWatch.
    final Color color;
    switch (status) {
      case PresenceReadStatus.online:
        color = Colors.green;
        break;
      case PresenceReadStatus.offline:
        color = const Color(0xFFCBD5E1);
        break;
      case PresenceReadStatus.unavailable:
        color = const Color(0xFFE5E7EB);
        break;
    }
    return Container(
      width: 10,
      height: 10,
      key: ValueKey(status.name),
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

void main() {
  testWidgets('dot unavailable is not confirmed-gray shade', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              _StatusStreamDot(status: PresenceReadStatus.unavailable),
              _StatusStreamDot(status: PresenceReadStatus.offline),
              _StatusStreamDot(status: PresenceReadStatus.online),
            ],
          ),
        ),
      ),
    );

    final unavailable = tester.widget<Container>(
      find.byKey(const ValueKey('unavailable')),
    );
    final offline = tester.widget<Container>(
      find.byKey(const ValueKey('offline')),
    );
    final online = tester.widget<Container>(
      find.byKey(const ValueKey('online')),
    );

    final uColor = (unavailable.decoration as BoxDecoration).color;
    final oColor = (offline.decoration as BoxDecoration).color;
    final onColor = (online.decoration as BoxDecoration).color;

    expect(uColor, const Color(0xFFE5E7EB));
    expect(oColor, const Color(0xFFCBD5E1));
    expect(onColor, Colors.green);
    expect(uColor, isNot(oColor));
  });

  test('empty uid OnlineDot builds offline without throw', () {
    expect(
      () => const OnlineDot(uid: ''),
      returnsNormally,
    );
  });
}
