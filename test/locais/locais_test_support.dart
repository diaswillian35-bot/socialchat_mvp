import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/features/locais/data/place_repository.dart';
import 'package:socialchat_mvp/features/locais/locais_feature_flag.dart';
import 'package:socialchat_mvp/features/locais/locais_strings.dart';
import 'package:socialchat_mvp/features/locais/ui/locais_list_page.dart';

DateTime locaisDemoClock() => DateTime(2026, 10, 14, 15);

Future<void> pumpLocais(
  WidgetTester tester,
  Widget page, {
  Size size = const Size(390, 844),
  double textScale = 1,
  bool enabled = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  LocaisFeatureFlag.debugOverride = enabled;
  LocaisStrings.debugLocale = const Locale('pt', 'BR');
  addTearDown(LocaisFeatureFlag.resetDebugOverride);
  addTearDown(LocaisStrings.resetDebugLocale);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: page,
    ),
  );
}

DemoPlaceRepository demoRepository({
  Duration latency = Duration.zero,
  Object? failure,
}) {
  return DemoPlaceRepository(latency: latency, failure: failure);
}

LocaisListPage demoList({Duration latency = Duration.zero, Object? failure}) {
  return LocaisListPage(
    repository: demoRepository(latency: latency, failure: failure),
    clock: locaisDemoClock,
  );
}
