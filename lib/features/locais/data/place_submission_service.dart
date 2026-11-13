import 'dart:math';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

import '../logic/place_hours_logic.dart';
import '../models/place_listing.dart';

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
    List<PlaceHours>? hours,
    this.pendingCoverPath,
  })  : hours = hours ?? <PlaceHours>[],
        photoUrls = photoUrls ?? <String>[],
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

  /// Horário por dia (1 = segunda … 7 = domingo). Vazio = sem horário.
  List<PlaceHours> hours;
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

  /// "Logo / Capa" escolhida no aparelho, ainda não enviada.
  String? pendingCoverPath;

  /// No editor a capa fica fora da grade: tira o [coverUrl] de [photoUrls].
  /// Capa que não está nas fotos é descartada (o backend faria o mesmo).
  void extractCover() {
    if (coverUrl.isNotEmpty && photoUrls.contains(coverUrl)) {
      photoUrls.remove(coverUrl);
    } else {
      coverUrl = '';
    }
  }

  bool get hasCover => coverUrl.isNotEmpty || pendingCoverPath != null;

  /// Fotos contando a capa (limite de [maxPhotos] e foto obrigatória).
  int get photoCount =>
      (hasCover ? 1 : 0) + photoUrls.length + pendingPhotoPaths.length;

  /// `photoUrls`/`coverUrl` finais: capa primeiro, sem duplicar, até 6.
  Map<String, dynamic> mediaFields(List<String> uploaded,
      {String? uploadedCover}) {
    final cover = uploadedCover ?? coverUrl;
    final photos = <String>[];
    for (final u in [if (cover.isNotEmpty) cover, ...photoUrls, ...uploaded]) {
      if (u.isNotEmpty && !photos.contains(u)) photos.add(u);
    }
    final kept = photos.take(maxPhotos).toList();
    return {
      'photoUrls': kept,
      'coverUrl': kept.isEmpty ? '' : kept.first,
    };
  }

  static const List<String> categories = [
    'restaurant',
    'bar',
    'cafe',
    'hotel',
    'pousada',
    'nightclub',
  ];

  static const int maxPhotos = 6;

  /// Fuso IANA do local, derivado de país/estado/cidade.
  String? get timeZone =>
      PlaceHoursLogic.zoneFor(countryCode, stateName, cityName);

  /// `hoursNote` enviado: gerado do horário estruturado (o backend atual só
  /// guarda esse texto); sem horário estruturado, mantém o texto antigo.
  String noteFor(String Function(int) dayName) => hours.isNotEmpty
      ? PlaceHoursLogic.toNote(hours, dayName)
      : hoursNote.trim();

  bool get hasCity =>
      cityName.trim().isNotEmpty && latitude != null && longitude != null;

  /// Passo "Localização": só delivery exige só a cidade.
  bool get locationValid => deliveryOnly ? cityName.trim().isNotEmpty : hasCity;

  /// Campos de texto (sem mídia) para create/update.
  Map<String, dynamic> toFields({String Function(int)? dayName}) => {
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
        'hoursNote': noteFor(dayName ?? _ptDay),
        'hours': PlaceHoursLogic.toJson(hours),
        'timeZone': timeZone ?? '',
        'phone': phone.trim(),
        'whatsapp': whatsapp.trim(),
        'websiteUrl': websiteUrl.trim(),
        'menuUrl': menuUrl.trim(),
      };

  static String _ptDay(int d) =>
      const ['Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom'][(d - 1) % 7];

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
      hours: PlaceHoursLogic.fromJson(m['hours']) ??
          PlaceHoursLogic.parseLegacy(s(m['hoursNote'])) ??
          <PlaceHours>[],
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
    final uploaded = <String>[];
    for (final p in draft.pendingPhotoPaths) {
      uploaded.add(await _upload(id, 'photos', p));
    }
    final coverPath = draft.pendingCoverPath;
    final uploadedCover =
        coverPath == null ? null : await _upload(id, 'photos', coverPath);
    final menu = [...draft.menuPhotoUrls];
    for (final p in draft.pendingMenuPaths) {
      menu.add(await _upload(id, 'menu', p));
    }
    await _call('updateMyPlace', {
      ...draft.toFields(),
      'placeId': id,
      ...draft.mediaFields(uploaded, uploadedCover: uploadedCover),
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

  static Future<void> deletePlace(String placeId) =>
      _call('deletePlace', {'placeId': placeId});
}
