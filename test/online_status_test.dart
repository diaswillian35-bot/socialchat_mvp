import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/services/online_status.dart';

void main() {
  final now = DateTime(2026, 7, 25, 12, 0, 0);

  Map<String, dynamic> user({
    required String uid,
    required bool isOnline,
    Duration ago = Duration.zero,
  }) {
    return {
      'uid': uid,
      'isOnline': isOnline,
      'lastSeenAt': Timestamp.fromDate(now.subtract(ago)),
    };
  }

  group('OnlineStatus', () {
    test('um usuário ativo = 1 online', () {
      final n = OnlineStatus.countUniqueOnline(
        docs: [user(uid: 'willian', isOnline: true)],
        now: now,
        idOf: (d) => d['uid'] as String,
      );
      expect(n, 1);
      expect(
        OnlineStatus.formatOnlineCount(count: n, onlineWord: 'online'),
        '1 online',
      );
    });

    test('Willian + testador ativos = 2 online', () {
      final n = OnlineStatus.countUniqueOnline(
        docs: [
          user(uid: 'willian', isOnline: true),
          user(uid: 'tester', isOnline: true),
        ],
        now: now,
        idOf: (d) => d['uid'] as String,
        onlyUids: {'willian', 'tester'},
      );
      expect(n, 2);
      expect(
        OnlineStatus.formatOnlineCount(count: n, onlineWord: 'online'),
        '2 online',
      );
    });

    test('mesmo UID em duas sessões = conta uma vez', () {
      final n = OnlineStatus.countUniqueOnline(
        docs: [
          user(uid: 'willian', isOnline: true),
          user(
              uid: 'willian', isOnline: true, ago: const Duration(seconds: 10)),
        ],
        now: now,
        idOf: (d) => d['uid'] as String,
      );
      expect(n, 1);
    });

    test('uma sessão fecha, outra continua = usuário permanece online', () {
      // Agregado publicUsers ainda isOnline=true enquanto outra sessão viva.
      expect(
        OnlineStatus.isOnline(
          user(uid: 'willian', isOnline: true),
          now,
        ),
        isTrue,
      );
    });

    test('heartbeat expirado = offline', () {
      expect(
        OnlineStatus.isOnline(
          user(
            uid: 'willian',
            isOnline: true,
            ago: const Duration(seconds: 200),
          ),
          now,
        ),
        isFalse,
      );
    });

    test('background = offline (isOnline false)', () {
      expect(
        OnlineStatus.isOnline(
          user(uid: 'willian', isOnline: false, ago: Duration.zero),
          now,
        ),
        isFalse,
      );
    });

    test('retorno ao foreground = online', () {
      expect(
        OnlineStatus.isOnline(
          user(uid: 'willian', isOnline: true, ago: const Duration(seconds: 5)),
          now,
        ),
        isTrue,
      );
    });

    test('logout = offline', () {
      expect(
        OnlineStatus.isOnline(
          {'uid': 'willian', 'isOnline': false},
          now,
        ),
        isFalse,
      );
    });

    test('membro removido/banido não entra no contador', () {
      final n = OnlineStatus.countUniqueOnline(
        docs: [
          user(uid: 'willian', isOnline: true),
          user(uid: 'banned', isOnline: true),
          user(uid: 'removed', isOnline: true),
        ],
        now: now,
        idOf: (d) => d['uid'] as String,
        onlyUids: {'willian', 'tester'}, // removed already out of members
        excludeUids: {'banned'},
      );
      expect(n, 1);
    });

    test('bolinha usa a mesma regra do contador', () {
      final data = user(uid: 'x', isOnline: true);
      expect(OnlineStatus.isOnline(data, now), isTrue);
      expect(
        OnlineStatus.countUniqueOnline(
          docs: [data],
          now: now,
          idOf: (d) => d['uid'] as String,
        ),
        1,
      );
    });

    test('horário do servidor e tolerância de rede', () {
      // lastSeen no futuro (skew) ainda conta como online.
      final future = {
        'uid': 'x',
        'isOnline': true,
        'lastSeenAt': Timestamp.fromDate(now.add(const Duration(seconds: 20))),
      };
      expect(OnlineStatus.isOnline(future, now), isTrue);

      // Dentro da janela + skew.
      final edge = user(
        uid: 'x',
        isOnline: true,
        ago: OnlineStatus.onlineWindow +
            OnlineStatus.clockSkewTolerance -
            const Duration(seconds: 1),
      );
      expect(OnlineStatus.isOnline(edge, now), isTrue);
    });

    test('nenhum timer duplicado — API pura sem side effects', () {
      // Contagem repetida com mesmos docs é idempotente.
      final docs = [
        user(uid: 'a', isOnline: true),
        user(uid: 'b', isOnline: true),
      ];
      expect(
        OnlineStatus.countUniqueOnline(
          docs: docs,
          now: now,
          idOf: (d) => d['uid'] as String,
        ),
        OnlineStatus.countUniqueOnline(
          docs: docs,
          now: now,
          idOf: (d) => d['uid'] as String,
        ),
      );
    });

    test(
        'botão voltar não encerra regra — inactive não muda isOnline nos dados',
        () {
      // A regra de UI não depende de inactive; dados ainda online.
      final data = user(uid: 'a', isOnline: true);
      expect(OnlineStatus.isOnline(data, now), isTrue);
    });

    test('querySince cobre janela + lookback', () {
      final since = OnlineStatus.querySince(now).toDate();
      expect(
        now.difference(since),
        OnlineStatus.onlineWindow + OnlineStatus.queryLookbackExtra,
      );
    });
  });
}
