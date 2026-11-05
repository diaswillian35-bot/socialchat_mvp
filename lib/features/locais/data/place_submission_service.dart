import 'dart:math';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

/// Rascunho do formulário "Adicionar local".
class PlaceDraft {
  PlaceDraft({
    this.id = '',
    this.name = '',
    this.category = 'restaurant',
    this.description = '',
    this.addressLine = '',
    this.cityName = '',
    this.stateName = '',
    this.countryCode = 'BR',
    this.cityDisplay = '',
    this.latitude,
    this.longitude,
    this.deliveryOnly = false,
    this.deliveryArea = '',
    this.hoursNote = '',
    this.phone = '',
    this.whatsapp = '',
    this.websiteUrl = '',
    this.menuUrl = '',
    List<String>? photoUrls,
    this.coverUrl = '',
    List<String>? menuPhotoUrls,
    this.status = '',
    List<String>? pendingPhotoPaths,
    List<String>? pendingMenuPaths,
  })  : photoUrls = photoUrls ?? <String>[],
        menuPhotoUrls = menuPhotoUrls ?? <String>[],
        pendingPhotoPaths = pendingPhotoPaths ?? <String>[],
        pendingMenuPaths = pendingMenuPaths ?? <String>[];

  String id;
  String name;
  String category;
  String description;
  String addressLine;
  String cityName;
  String stateName;
  String countryCode;
  String cityDisplay;
  double? latitude;
  double? longitude;

  /// "Só delivery": sem espaço físico; endereço e mapa opcionais.
  bool deliveryOnly;
  String deliveryArea;
  String hoursNote;
  String phone;
  String whatsapp;
  String websiteUrl;
  String menuUrl;
  List<String> photoUrls;
  String coverUrl;
  List<String> menuPhotoUrls;
  String status;
  List<String> pendingPhotoPaths;
  List<String> pendingMenuPaths;

  static const List<String> categories = [
    'restaurant',
    'bar',
    'cafe',
    'hotel',
    'pousada',
    'nightclub',
  ];

  static const int maxPhotos = 6;

  bool get hasCity =>
      cityName.trim().isNotEmpty && latitude != null && longitude != null;

  /// Passo "Localização": só delivery exige só a cidade.
  bool get locationValid => deliveryOnly ? cityName.trim().isNotEmpty : hasCity;

  /// Campos de texto (sem mídia) para create/update.
  Map<String, dynamic> toFields() => {
        'name': name.trim(),
        'category': category,
        'description': description.trim(),
        'addressLine': addressLine.trim(),
        'cityName': cityName.trim(),
        'stateName': stateName.trim(),
        'countryCode': countryCode.trim().toUpperCase(),
        'latitude': latitude,
        'longitude': longitude,
        'deliveryOnly': deliveryOnly,
        'deliveryArea': deliveryOnly ? deliveryArea.trim() : '',
        'hoursNote': hoursNote.trim(),
        'phone': phone.trim(),
        'whatsapp': whatsapp.trim(),
        'websiteUrl': websiteUrl.trim(),
        'menuUrl': menuUrl.trim(),
      };

  factory PlaceDraft.fromSummary(Map<String, dynamic> m) {
    double? d(Object? v) => v is num ? v.toDouble() : null;
    List<String> l(Object? v) =>
        v is List ? v.map((e) => e.toString()).toList() : <String>[];
    String s(Object? v) => (v ?? '').toString();
    final city = s(m['cityName']);
    final state = s(m['stateName']);
    return PlaceDraft(
      id: s(m['id']),
      name: s(m['name']),
      category: categories.contains(s(m['category']))
          ? s(m['category'])
          : 'restaurant',
      description: s(m['description']),
      addressLine: s(m['addressLine']),
      cityName: city,
      stateName: state,
      countryCode: s(m['countryCode']).isEmpty ? 'BR' : s(m['countryCode']),
      cityDisplay: state.isEmpty ? city : '$city, $state',
      latitude: d(m['latitude']),
      longitude: d(m['longitude']),
      deliveryOnly: m['deliveryOnly'] == true,
      deliveryArea: s(m['deliveryArea']),
      hoursNote: s(m['hoursNote']),
      phone: s(m['phone']),
      whatsapp: s(m['whatsapp']),
      websiteUrl: s(m['websiteUrl']),
      menuUrl: s(m['menuUrl']),
      photoUrls: l(m['photoUrls']),
      coverUrl: s(m['coverUrl']),
      menuPhotoUrls: l(m['menuPhotoUrls']),
      status: s(m['status']),
    );
  }
}

/// Callables do "Adicionar local" + upload de fotos no Storage
/// (`places/{placeId}/photos|menu/{32hex}.jpg`, como as Storage Rules exigem).
class PlaceSubmissionService {
  PlaceSubmissionService._();

  static FirebaseFunctions get _fn =>
      FirebaseFunctions.instanceFor(region: 'us-central1');

  static Future<Map<String, dynamic>> _call(
    String name,
    Map<String, dynamic> data,
  ) async {
    final res = await _fn.httpsCallable(name).call(data);
    final raw = res.data;
    return raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
  }

  static String randomHex32([Random? random]) {
    final r = random ?? Random.secure();
    const hex = '0123456789abcdef';
    return List.generate(32, (_) => hex[r.nextInt(16)]).join();
  }

  static Future<String> _upload(
      String placeId, String folder, String path) async {
    final ref = FirebaseStorage.instance
        .ref()
        .child('places')
        .child(placeId)
        .child(folder)
        .child('${randomHex32()}.jpg');
    final bytes = await XFile(path).readAsBytes();
    await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
    return ref.getDownloadURL();
  }

  /// Cria (se novo) e envia mídia. Retorna o id do local.
  static Future<String> save(PlaceDraft draft) async {
    var id = draft.id;
    if (id.isEmpty) {
      final created = await _call('submitPlace', draft.toFields());
      id = (created['placeId'] ?? '').toString();
      if (id.isEmpty) throw StateError('missing_place_id');
      draft.id = id;
    }
    final photos = [...draft.photoUrls];
    for (final p in draft.pendingPhotoPaths) {
      photos.add(await _upload(id, 'photos', p));
    }
    final menu = [...draft.menuPhotoUrls];
    for (final p in draft.pendingMenuPaths) {
      menu.add(await _upload(id, 'menu', p));
    }
    var cover = draft.coverUrl;
    if (!photos.contains(cover)) cover = photos.isNotEmpty ? photos.first : '';
    await _call('updateMyPlace', {
      ...draft.toFields(),
      'placeId': id,
      'photoUrls': photos,
      'coverUrl': cover,
      'menuPhotoUrls': menu,
    });
    return id;
  }

  static Future<PlaceDraft?> load(String placeId) async {
    final res = await _call('getMyPlace', {'placeId': placeId});
    final p = res['place'];
    if (p is! Map) return null;
    return PlaceDraft.fromSummary(Map<String, dynamic>.from(p));
  }

  static Future<List<PlaceDraft>> _list(String name) async {
    final res = await _call(name, {});
    final raw = res['places'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((m) => PlaceDraft.fromSummary(Map<String, dynamic>.from(m)))
        .toList();
  }

  static Future<List<PlaceDraft>> listMine() => _list('listMyPlaces');

  static Future<List<PlaceDraft>> listPending() => _list('listPendingPlaces');

  /// [reason]: motivo da recusa (gravado em places.moderationReason e
  /// enviado no push ao dono). O painel web exige; o app pode omitir.
  static Future<void> moderate(String placeId,
          {required bool approve, String? reason}) =>
      _call('moderatePlace', {
        'placeId': placeId,
        'decision': approve ? 'approve' : 'reject',
        if (!approve && (reason ?? '').trim().isNotEmpty)
          'reason': reason!.trim(),
      });
}
