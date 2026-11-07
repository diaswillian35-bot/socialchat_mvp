import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:socialchat_mvp/features/locais/data/place_repository.dart';
import 'package:socialchat_mvp/features/locais/data/demo_places.dart';
import 'package:socialchat_mvp/features/locais/models/place_listing.dart';
import 'package:socialchat_mvp/features/locais/ui/locais_deep_link_page.dart';
import 'package:socialchat_mvp/features/locais/locais_feature_flag.dart';
import 'locais/locais_test_support.dart';
import 'package:socialchat_mvp/services/remdy_deep_link_parser.dart';
import 'package:socialchat_mvp/features/locais/logic/place_share_link.dart';

class _CountingRepository extends PlaceRepository {
  int catalogReads = 0;
  int idReads = 0;
  String? lastId;
  @override
  Future<List<PlaceListing>> fetchCatalog() async {
    catalogReads++;
    throw StateError('A public ID route must not scan the catalog');
  }

  @override
  Future<PlaceListing?> fetchById(String id) async {
    idReads++;
    lastId = id;
    return DemoPlaces.all.first;
  }
}

void main() {
  tearDown(LocaisFeatureFlag.resetDebugOverride);
  testWidgets(
      'ID route fetches only that doc, and native share contains its public URL',
      (tester) async {
    final repository = _CountingRepository();
    MethodCall? shared;
    const channel = MethodChannel('dev.fluttercommunity.plus/share');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      shared = call;
      return 'success';
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    await pumpLocais(
        tester,
        LocaisDeepLinkPage(
            placeId: 'hPGFEU4iQbDJXItOwQhV', repository: repository));
    await tester.pumpAndSettle();
    expect(repository.catalogReads, 0);
    expect(repository.idReads, 1);
    expect(repository.lastId, 'hPGFEU4iQbDJXItOwQhV');
    await tester.tap(find.byIcon(Icons.ios_share_rounded));
    await tester.pumpAndSettle();
    expect(shared?.method, 'share');
    // Demo repository returns the demo place; sharing uses the displayed place ID.
    expect((shared?.arguments as Map)['text'],
        contains(PlaceShareLink.url(DemoPlaces.all.first.id)));
    expect((shared?.arguments as Map)['subject'], DemoPlaces.all.first.name);
  });
  test('stable share link preserves Firestore ID case and round trips', () {
    const id = 'hPGFEU4iQbDJXItOwQhV';
    final url = PlaceShareLink.url(id);
    expect(url, 'https://remdy.app/l/$id');
    final parsed = RemdyDeepLinkParser.parse(Uri.parse(url));
    expect(parsed.kind, RemdyDeepLinkKind.place);
    expect(parsed.placeId, id);
    expect(parsed.placeSlug, isNull);
    expect(RemdyDeepLinkParser.parse(Uri.parse('remdy://l/$id')).placeId, id);
  });
  test('reject malformed IDs, unrelated hosts and nested routes', () {
    for (final id in ['', '../x', 'a/b', '<script>']) {
      expect(() => PlaceShareLink.url(id), throwsArgumentError);
    }
    for (final url in [
      'https://evil.test/l/id',
      'https://remdy.app/l/',
      'https://remdy.app/l/a/b',
      'https://remdy.app/l/a%2Fb'
    ]) {
      expect(RemdyDeepLinkParser.parse(Uri.parse(url)).kind,
          RemdyDeepLinkKind.none);
    }
  });
  test('legacy route stays available', () {
    final parsed = RemdyDeepLinkParser.parse(
        Uri.parse('https://remdy.app/locais/on/toronto/john-burger'));
    expect(parsed.kind, RemdyDeepLinkKind.place);
    expect(parsed.placeSlug, 'john-burger');
    expect(parsed.placeId, isNull);
  });
  test('share text and error exist in all 5 catalogs', () {
    for (final lang in ['pt-BR', 'pt-PT', 'en', 'es', 'fr']) {
      final data =
          jsonDecode(File('lib/l10n/$lang.json').readAsStringSync()) as Map;
      expect(data['places_share_text'], isNotEmpty);
      expect(data['places_share_error'], isNotEmpty);
    }
  });
}
