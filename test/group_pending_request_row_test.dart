import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/widgets/group_pending_request_row.dart';

void main() {
  testWidgets('pending request: name max 2 lines, actions on Wrap row',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: GroupPendingRequestRow(
            userName: 'Willian Dias Gonçalves da Silva Extra Long Name',
            avatar: SizedBox(width: 42, height: 42),
            rejectLabel: 'Rejeitar solicitação',
            approveLabel: 'Aprovar solicitação',
            onReject: _noop,
            onApprove: _noop,
          ),
        ),
      ),
    );

    final nameFinder = find.textContaining('Willian Dias');
    expect(nameFinder, findsOneWidget);
    final nameText = tester.widget<Text>(nameFinder);
    expect(nameText.maxLines, 2);
    expect(nameText.overflow, TextOverflow.ellipsis);

    expect(find.byType(Wrap), findsOneWidget);
    expect(find.text('Rejeitar solicitação'), findsOneWidget);
    expect(find.text('Aprovar solicitação'), findsOneWidget);

    // Sem overflow reportado pelo framework.
    expect(tester.takeException(), isNull);
  });

  testWidgets('short accented name still renders on narrow width',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(300, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: GroupPendingRequestRow(
            userName: 'José Antônio',
            avatar: SizedBox(width: 42, height: 42),
            rejectLabel: 'Rejeitar solicitação',
            approveLabel: 'Aprovar solicitação',
            onReject: _noop,
            onApprove: _noop,
          ),
        ),
      ),
    );

    expect(find.text('José Antônio'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

void _noop() {}
