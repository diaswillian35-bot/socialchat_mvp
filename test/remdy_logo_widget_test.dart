import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/widgets/remdy_logo.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('RemdyLogo matches Events height and fits Home AppBar',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(
            toolbarHeight: 88,
            centerTitle: true,
            leading: const Icon(Icons.menu_rounded),
            title: const RemdyLogo(),
            actions: [
              TextButton(onPressed: () {}, child: const Text('Remi')),
              const Padding(
                padding: EdgeInsets.only(right: 14),
                child: CircleAvatar(radius: 18),
              ),
            ],
          ),
          body: const Center(child: RemdyLogo()),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(RemdyLogo), findsNWidgets(2));

    final images = tester.widgetList<Image>(find.byType(Image)).toList();
    expect(images.length, 2);
    for (final image in images) {
      expect(image.height, RemdyLogo.defaultHeight);
      expect((image.image as AssetImage).assetName, RemdyLogo.assetPath);
    }

    // Simulate larger text scale (a11y) — logo height stays fixed like Events.
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
        child: MaterialApp(
          home: Scaffold(
            appBar: AppBar(
              toolbarHeight: 88,
              centerTitle: true,
              title: const RemdyLogo(),
            ),
            body: const SizedBox.shrink(),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
