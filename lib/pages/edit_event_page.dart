import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../l10n/app_texts.dart';
import '../models/event_editorial_draft.dart';
import '../services/event_image_storage.dart';
import '../services/event_management_service.dart';
import '../widgets/events/event_editorial_wizard.dart';

class EditEventPage extends StatefulWidget {
  final String eventId;

  const EditEventPage({
    super.key,
    required this.eventId,
  });

  @override
  State<EditEventPage> createState() => _EditEventPageState();
}

class _EditEventPageState extends State<EditEventPage> {
  static const Color _remdyNavy = Color(0xFF313A5F);

  EventEditorialDraft? _draft;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadEvent();
  }

  Future<void> _loadEvent() async {
    final doc = await FirebaseFirestore.instance
        .collection('events')
        .doc(widget.eventId)
        .get();

    if (!doc.exists) {
      if (!mounted) return;
      Navigator.pop(context);
      return;
    }

    final data = doc.data()!;
    final hasPending = data['hasPendingChanges'] == true;
    final pendingRaw = data['pendingChanges'];
    final pending = (hasPending &&
            pendingRaw is Map &&
            pendingRaw.isNotEmpty)
        ? Map<String, dynamic>.from(pendingRaw)
        : <String, dynamic>{};

    final merged = <String, dynamic>{...data, ...pending};
    final draft = EventEditorialDraft.fromEventMap(merged);

    if (!mounted) return;
    setState(() {
      _draft = draft;
      _loading = false;
    });
  }

  Future<EventEditorialDraft> _uploadPendingMedia(
    EventEditorialDraft draft,
  ) async {
    var next = draft;
    final uploaded = <String>[...draft.photoUrls];

    final paths = [...draft.pendingPhotoPaths];
    if (draft.pendingCoverPath.isNotEmpty &&
        paths.contains(draft.pendingCoverPath)) {
      paths.remove(draft.pendingCoverPath);
      paths.insert(0, draft.pendingCoverPath);
    }

    String newCover = draft.coverUrl;
    for (var i = 0; i < paths.length; i++) {
      final path = paths[i];
      final fileName =
          '${DateTime.now().millisecondsSinceEpoch}_edit_$i.jpg';
      final url = await EventImageStorage.uploadJpegXFile(
        eventId: widget.eventId,
        file: XFile(path),
        fileName: fileName,
      );
      uploaded.add(url);
      if (draft.pendingCoverPath == path || newCover.isEmpty) {
        newCover = url;
      }
    }

    var logoUrl = draft.logoUrl;
    if (draft.pendingLogoPath.isNotEmpty) {
      logoUrl = await EventImageStorage.uploadJpegXFile(
        eventId: widget.eventId,
        file: XFile(draft.pendingLogoPath),
        fileName: '${DateTime.now().millisecondsSinceEpoch}_logo.jpg',
      );
    }

    next = next.copyWith(
      photoUrls: uploaded.take(5).toList(),
      coverUrl: newCover,
      logoUrl: logoUrl,
      pendingPhotoPaths: const [],
      pendingCoverPath: '',
      pendingLogoPath: '',
    );
    return next;
  }

  Future<void> _onSubmit(EventEditorialDraft draft) async {
    try {
      final withMedia = await _uploadPendingMedia(draft);
      final extras = withMedia.toUpdateCallablePayload(full: true);

      final result = await EventManagementService.updateEvent(
        eventId: widget.eventId,
        title: withMedia.title.trim(),
        description: withMedia.description.trim(),
        category: withMedia.category,
        startAt: withMedia.startAtUtc(),
        endAt: withMedia.endAtUtc(),
        eventTimeZone: withMedia.eventTimeZone,
        city: withMedia.city.trim(),
        cityKey: withMedia.cityKey.trim().isNotEmpty
            ? withMedia.cityKey.trim()
            : withMedia.city.trim().toLowerCase(),
        stateName: withMedia.stateName,
        placeName: withMedia.placeName.trim(),
        address: withMedia.address,
        placeDisplay: withMedia.placeDisplay.isNotEmpty
            ? withMedia.placeDisplay
            : withMedia.placeName.trim(),
        countryCode: withMedia.countryCode.trim().toLowerCase(),
        regionKey: withMedia.regionKey,
        scope: withMedia.scope.isNotEmpty ? withMedia.scope : 'city',
        lat: withMedia.lat,
        lng: withMedia.lng,
        sponsorInterested: withMedia.sponsorInterested,
        coverUrl: withMedia.coverUrl,
        photoUrls: withMedia.photoUrls,
        extraFields: extras,
      );

      if (!mounted) return;

      final updateMode = (result['updateMode'] ?? '').toString();
      final messageKey = updateMode == 'pending_changes'
          ? 'event_changes_sent_for_review'
          : 'event_sent_for_approval';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppTexts.t(messageKey))),
      );
      Navigator.pop(context);
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppTexts.t(EventManagementService.updateErrorKey(e))),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppTexts.t('event_changes_update_error'))),
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
      isEdit: true,
      onSubmit: _onSubmit,
      onCancel: () => Navigator.of(context).maybePop(),
    );
  }
}
