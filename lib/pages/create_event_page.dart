import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../l10n/app_texts.dart';
import '../models/event_editorial_draft.dart';
import '../services/event_editorial_draft_store.dart';
import '../services/event_image_storage.dart';
import '../services/event_management_service.dart';
import '../utils/event_timezone.dart';
import '../widgets/events/event_editorial_wizard.dart';

class CreateEventPage extends StatefulWidget {
  const CreateEventPage({super.key});

  @override
  State<CreateEventPage> createState() => _CreateEventPageState();
}

class _CreateEventPageState extends State<CreateEventPage> {
  static const Color _remdyNavy = Color(0xFF313A5F);

  EventEditorialDraft? _draft;
  bool _loading = true;

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  @override
  void initState() {
    super.initState();
    _loadDraft();
  }

  Future<void> _loadDraft() async {
    final uid = _uid;
    EventEditorialDraft draft = EventEditorialDraft(
      eventTimeZone: EventTimezone.suggestedZones.first,
    );
    if (uid != null) {
      final saved = await EventEditorialDraftStore.load(uid);
      if (saved != null) draft = saved;
    }
    if (!mounted) return;
    setState(() {
      _draft = draft;
      _loading = false;
    });
  }

  Future<void> _onDraftChanged(EventEditorialDraft draft) async {
    final uid = _uid;
    if (uid == null) return;
    await EventEditorialDraftStore.save(uid, draft);
  }

  Future<void> _onSubmit(EventEditorialDraft draft) async {
    final uid = _uid;
    if (uid == null) return;

    String? createdEventId;
    final uploadedPhotos = <String>[];
    String? uploadedLogo;

    try {
      final payload = draft.toCreateCallablePayload();
      // Fotos sobem depois; create sem URLs locais.
      payload.remove('coverUrl');
      payload.remove('photoUrls');
      payload.remove('logoUrl');

      final created = await EventManagementService.createEvent(
        title: draft.title.trim(),
        description: draft.description.trim(),
        category: draft.category,
        startAt: draft.startAtUtc(),
        endAt: draft.endAtUtc(),
        eventTimeZone: draft.eventTimeZone,
        city: draft.city.trim(),
        cityKey: draft.cityKey.trim().isNotEmpty
            ? draft.cityKey.trim()
            : draft.city.trim().toLowerCase(),
        stateName: draft.stateName,
        placeName: draft.placeName.trim(),
        address: draft.address,
        placeDisplay: draft.placeDisplay.isNotEmpty
            ? draft.placeDisplay
            : draft.placeName.trim(),
        countryCode: draft.countryCode.trim().toLowerCase(),
        regionKey: draft.regionKey,
        scope: draft.scope.isNotEmpty ? draft.scope : 'city',
        lat: draft.lat,
        lng: draft.lng,
        sponsorInterested: draft.sponsorInterested,
        extraFields: payload,
      );

      final eventId = (created['eventId'] ?? '').toString();
      if (eventId.isEmpty) throw StateError('missing_event_id');
      createdEventId = eventId;

      // Ordem: pending paths; capa marcada primeiro se possível.
      final paths = [...draft.pendingPhotoPaths];
      if (draft.pendingCoverPath.isNotEmpty &&
          paths.contains(draft.pendingCoverPath)) {
        paths.remove(draft.pendingCoverPath);
        paths.insert(0, draft.pendingCoverPath);
      }

      for (var i = 0; i < paths.length; i++) {
        final path = paths[i];
        final fileName =
            '${DateTime.now().millisecondsSinceEpoch}_$i.jpg';
        final url = await EventImageStorage.uploadJpegXFile(
          eventId: eventId,
          file: XFile(path),
          fileName: fileName,
        );
        uploadedPhotos.add(url);
      }

      if (draft.pendingLogoPath.isNotEmpty) {
        uploadedLogo = await EventImageStorage.uploadJpegXFile(
          eventId: eventId,
          file: XFile(draft.pendingLogoPath),
          fileName: '${DateTime.now().millisecondsSinceEpoch}_logo.jpg',
        );
      }

      final mediaExtras = <String, dynamic>{};
      if (uploadedPhotos.isNotEmpty) {
        mediaExtras['photoUrls'] = uploadedPhotos;
        mediaExtras['coverUrl'] = uploadedPhotos.first;
      }
      if (uploadedLogo != null && uploadedLogo.isNotEmpty) {
        mediaExtras['logoUrl'] = uploadedLogo;
      }
      // Reenvia editorial completo + mídia (exceto timestamps já no create).
      final updateExtras = draft.toUpdateCallablePayload(full: true)
        ..remove('startAtMs')
        ..remove('endAtMs');
      updateExtras.addAll(mediaExtras);

      if (mediaExtras.isNotEmpty || updateExtras.isNotEmpty) {
        await EventManagementService.updateEvent(
          eventId: eventId,
          coverUrl: mediaExtras['coverUrl'] as String?,
          photoUrls: mediaExtras['photoUrls'] as List<String>?,
          extraFields: updateExtras,
        );
      }

      await EventEditorialDraftStore.clear(uid);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppTexts.t('create_event_success'))),
      );
      Navigator.pop(context);
    } on FirebaseFunctionsException catch (e) {
      if (createdEventId != null) {
        await EventManagementService.abortIncompleteEvent(
          eventId: createdEventId,
          reason: 'functions_${e.code}',
        );
        for (final url in uploadedPhotos) {
          await EventImageStorage.deleteByUrl(url);
        }
        if (uploadedLogo != null) {
          await EventImageStorage.deleteByUrl(uploadedLogo);
        }
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppTexts.t(
              createdEventId == null
                  ? EventManagementService.createErrorKey(e)
                  : EventManagementService.updateErrorKey(e),
            ),
          ),
        ),
      );
    } on FirebaseException catch (e) {
      if (createdEventId != null) {
        await EventManagementService.abortIncompleteEvent(
          eventId: createdEventId,
          reason: 'firebase_${e.plugin}_${e.code}',
        );
        for (final url in uploadedPhotos) {
          await EventImageStorage.deleteByUrl(url);
        }
        if (uploadedLogo != null) {
          await EventImageStorage.deleteByUrl(uploadedLogo);
        }
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppTexts.t('create_event_error'))),
      );
    } catch (_) {
      if (createdEventId != null) {
        await EventManagementService.abortIncompleteEvent(
          eventId: createdEventId,
          reason: 'unexpected',
        );
        for (final url in uploadedPhotos) {
          await EventImageStorage.deleteByUrl(url);
        }
        if (uploadedLogo != null) {
          await EventImageStorage.deleteByUrl(uploadedLogo);
        }
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppTexts.t('create_event_error'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _draft == null) {
      return const Scaffold(
        backgroundColor: Color(0xFFF6F7FB),
        body: Center(
          child: CircularProgressIndicator(color: _remdyNavy),
        ),
      );
    }

    return EventEditorialWizard(
      initial: _draft!,
      isEdit: false,
      onDraftChanged: _onDraftChanged,
      onSubmit: _onSubmit,
      onCancel: () => Navigator.of(context).maybePop(),
    );
  }
}
