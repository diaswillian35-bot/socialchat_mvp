import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../l10n/app_texts.dart';
import '../models/event_presentation.dart';
import '../services/app_notification_state.dart';
import '../services/event_attendance_service.dart';
import '../services/event_calendar_service.dart';
import '../services/event_directions_service.dart';
import '../services/event_comments_logic.dart';
import '../services/event_comments_service.dart';
import '../services/event_likes_service.dart';
import '../services/event_share_image_service.dart';
import '../services/event_view_service.dart';
import '../utils/event_gallery_urls.dart';
import '../widgets/events/event_detail_action_bar.dart';
import '../widgets/events/event_detail_light_header.dart';
import '../widgets/events/event_gallery_grid.dart';
import 'event_gallery_viewer_page.dart';
import 'public_profile_page.dart';

class EventDetailPage extends StatefulWidget {
  final String eventId;
  const EventDetailPage({super.key, required this.eventId});

  @override
  State<EventDetailPage> createState() => _EventDetailPageState();
}

class _EventDetailPageState extends State<EventDetailPage> {
  final _db = FirebaseFirestore.instance;
  final _scrollController = ScrollController();
  final _commentC = TextEditingController();
  final _replyC = TextEditingController();
  final _commentFocus = FocusNode();
  final _replyFocus = FocusNode();
  final _replyEditorKey = GlobalKey();
  final _viewRegistration = EventViewRegistrationGuard();

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _eventSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _commentsSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _attendeesSub;

  DocumentSnapshot<Map<String, dynamic>>? _eventSnap;
  Object? _eventError;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _commentDocs = const [];
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _attendeeDocs = const [];
  bool _eventLoading = true;
  bool _commentsReady = false;

  String? _replyToCommentId;
  String? _replyToName;
  String? _replyToText;
  String? _replyRootId;

  bool _attendanceBusy = false;
  bool _commentSending = false;
  bool _replySending = false;
  bool _viewKickoffScheduled = false;
  bool _eventLikeBusy = false;
  bool? _eventLiked; // null = ainda não carregado
  int? _optimisticEventLikes;
  bool? _optimisticEventLiked;
  bool _shareBusy = false;
  bool _calendarBusy = false;
  /// 0 Sobre · 1 Programação · 2 Atrações · 3 Galeria · 4 Localização
  int _detailTab = 0;
  /// Índice da foto selecionada na Galeria (após fechar o fullscreen).
  int _galleryIndex = 0;

  final Set<String> _likingCommentIds = <String>{};
  final Set<String> _deletingCommentIds = <String>{};
  final Map<String, _CommentLikeOpt> _commentLikeOpt = {};
  final Map<String, PendingEventComment> _pendingById = {};

  static const _bg = Colors.white;
  static const _text = Color(0xFF111827);
  static const _muted = Color(0xFF6B7280);
  static const _border = Color(0xFFE5E7EB);
  static const _remdyBlue = Color(0xFF313A5F);

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  DocumentReference<Map<String, dynamic>> get _eventRef =>
      _db.collection('events').doc(widget.eventId);

  @override
  void initState() {
    super.initState();
    AppNotificationState.instance.enterEvent(widget.eventId);
    _bindStreams();
    _loadLikedOnce();
  }

  void _bindStreams() {
    _eventSub = _eventRef.snapshots().listen(
      (snap) {
        if (!mounted) return;
        setState(() {
          _eventSnap = snap;
          _eventError = null;
          _eventLoading = false;
          if (!_eventLikeBusy && _optimisticEventLikes != null) {
            _optimisticEventLikes = null;
            _optimisticEventLiked = null;
          }
        });
      },
      onError: (e, _) {
        if (!mounted) return;
        setState(() {
          _eventError = e;
          _eventLoading = false;
        });
      },
    );

    _commentsSub = _eventRef
        .collection('comments')
        .orderBy('createdAt', descending: false)
        .limit(200)
        .snapshots()
        .listen(
      (snap) {
        if (!mounted) return;
        setState(() {
          _commentDocs = snap.docs;
          _commentsReady = true;
          // Remove pending confirmados no servidor.
          for (final doc in snap.docs) {
            _pendingById.remove(doc.id);
          }
          // Fecha editor se o comentário respondido sumiu / foi soft-deleted.
          final replyId = _replyToCommentId;
          if (replyId != null) {
            final stillThere = snap.docs.any((d) {
              if (d.id != replyId) return false;
              return d.data()['isDeleted'] != true;
            });
            if (!stillThere) {
              _replyToCommentId = null;
              _replyToName = null;
              _replyToText = null;
              _replyRootId = null;
              _replyC.clear();
            }
          }
        });
      },
      onError: (e, st) {
        if (kDebugMode) {
          debugPrint('event comments stream error: $e\n$st');
        }
        if (!mounted) return;
        setState(() => _commentsReady = true);
      },
    );

    _attendeesSub = _eventRef
        .collection('attendees')
        .limit(15)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      setState(() => _attendeeDocs = snap.docs);
    });
  }

  Future<void> _loadLikedOnce() async {
    final uid = _uid;
    if (uid == null) {
      if (mounted) setState(() => _eventLiked = false);
      return;
    }
    try {
      final liked = await EventLikesService.hasLiked(eventId: widget.eventId);
      if (!mounted) return;
      setState(() => _eventLiked = liked);
    } catch (e, st) {
      if (kDebugMode) debugPrint('hasLiked error: $e\n$st');
      if (!mounted) return;
      setState(() => _eventLiked = false);
    }
  }

  @override
  void dispose() {
    AppNotificationState.instance.leaveEvent(widget.eventId);
    _eventSub?.cancel();
    _commentsSub?.cancel();
    _attendeesSub?.cancel();
    _scrollController.dispose();
    _commentC.dispose();
    _replyC.dispose();
    _commentFocus.dispose();
    _replyFocus.dispose();
    super.dispose();
  }

  String _flagEmoji(String code) {
    final upper = code.trim().toUpperCase();
    if (upper.length != 2) return '🏳️';
    final int first = upper.codeUnitAt(0) - 0x41 + 0x1F1E6;
    final int second = upper.codeUnitAt(1) - 0x41 + 0x1F1E6;
    return String.fromCharCodes([first, second]);
  }

  String _fmtDate(Timestamp? ts) {
    if (ts == null) return AppTexts.t('events_no_date');
    final d = ts.toDate();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year} • ${two(d.hour)}:${two(d.minute)}';
  }

  Future<void> _openDirections(EventPresentation event) async {
    if (!EventDirectionsService.hasValidDestination(
      lat: event.lat,
      lng: event.lng,
      place: event.placeName,
      address: event.address,
      city: event.city,
      state: event.stateName,
      country: event.countryCode,
    )) {
      if (mounted) _snack('events_directions_unavailable');
      return;
    }
    final ok = await EventDirectionsService.open(
      lat: event.lat,
      lng: event.lng,
      place: event.placeName,
      address: event.address,
      city: event.city,
      state: event.stateName,
      country: event.countryCode,
    );
    if (!ok && mounted) {
      _snack('events_directions_unavailable');
    }
  }

  // Preservado para reativação futura da ação Calendário (fora da UI atual).
  // ignore: unused_element
  Future<void> _confirmAddToCalendar(EventPresentation event) async {
    if (_calendarBusy) return;
    if (event.startAt == null) {
      _snack('events_calendar_no_date');
      return;
    }
    if (await EventCalendarService.wasAdded(event.id)) {
      if (!mounted) return;
      _snack('events_calendar_already_added');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppTexts.t('events_calendar_confirm_title')),
        content: Text(AppTexts.t('events_calendar_confirm_message')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(AppTexts.t('event_detail_cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(AppTexts.t('events_calendar_confirm_add')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _calendarBusy = true);
    try {
      final lang = Localizations.localeOf(context).languageCode;
      final result = await EventCalendarService.shareIcs(
        eventId: event.id,
        title: event.title,
        start: event.startAt!,
        end: event.endAt,
        location: [
          event.venueLine(),
          event.locationLine(lang),
        ].where((e) => e.trim().isNotEmpty).join(' • '),
        description: event.description,
        url: 'https://remdy.app/e/${event.id}',
      );
      if (!mounted) return;
      if (result == EventCalendarResult.alreadyAdded) {
        _snack('events_calendar_already_added');
      } else if (result == EventCalendarResult.shared) {
        _snack('events_calendar_added');
      } else if (result == EventCalendarResult.permissionDenied) {
        _snack('events_calendar_permission_denied');
      } else if (result == EventCalendarResult.failed) {
        _snack('events_calendar_error');
      }
    } catch (e, st) {
      if (kDebugMode) debugPrint('calendar: $e\n$st');
      if (!mounted) return;
      _snack('events_calendar_error');
    } finally {
      if (mounted) setState(() => _calendarBusy = false);
    }
  }

  Widget _buildActionBar({
    required EventPresentation event,
    required bool liked,
    required bool cancelled,
    required bool closed,
  }) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _uid == null
          ? null
          : _eventRef.collection('attendees').doc(_uid).snapshots(),
      builder: (context, snap) {
        final joined = snap.data?.exists == true;
        final canJoin = _uid != null && !closed;
        final canLeave = _uid != null && joined && !cancelled;
        // Calendário / Como chegar: params preservados, fora da UI da faixa.
        return EventDetailActionBar(
          favoriteLabel: AppTexts.t('events_action_favorite'),
          participateLabel: joined
              ? AppTexts.t('events_action_participating')
              : AppTexts.t('events_action_participate'),
          shareLabel: AppTexts.t('events_action_share'),
          calendarLabel: AppTexts.t('events_action_calendar'),
          directionsLabel: AppTexts.t('events_action_directions'),
          favorited: liked,
          participating: joined,
          favoriteBusy: _eventLikeBusy,
          participateBusy: _attendanceBusy,
          shareBusy: _shareBusy,
          calendarBusy: _calendarBusy,
          directionsEnabled: false,
          onFavorite: (_uid == null) ? null : _toggleEventLike,
          onParticipate: joined
              ? (canLeave ? _leaveEvent : null)
              : (canJoin ? _joinEvent : null),
          onShare: _shareBusy ? null : () => _shareEvent(event),
          onCalendar: null,
          onDirections: null,
        );
      },
    );
  }

  Future<void> _joinEvent() async {
    final uid = _uid;
    if (uid == null) {
      _snack('event_detail_login_required');
      return;
    }
    if (_attendanceBusy) return;
    setState(() => _attendanceBusy = true);
    try {
      final result = await EventAttendanceService.joinEvent(
        eventId: widget.eventId,
      );
      if (!mounted) return;
      _snack(
        result['alreadyJoined'] == true
            ? 'event_detail_already_joined'
            : 'event_detail_join_success',
      );
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      _snack(EventAttendanceService.joinErrorKey(e));
    } catch (e, st) {
      if (kDebugMode) debugPrint('joinEvent: $e\n$st');
      if (!mounted) return;
      _snack('event_detail_join_error');
    } finally {
      if (mounted) setState(() => _attendanceBusy = false);
    }
  }

  Future<void> _leaveEvent() async {
    if (_uid == null || _attendanceBusy) return;
    setState(() => _attendanceBusy = true);
    try {
      await EventAttendanceService.leaveEvent(eventId: widget.eventId);
      if (!mounted) return;
      _snack('event_detail_leave_success');
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      _snack(EventAttendanceService.leaveErrorKey(e));
    } catch (e, st) {
      if (kDebugMode) debugPrint('leaveEvent: $e\n$st');
      if (!mounted) return;
      _snack('event_detail_leave_error');
    } finally {
      if (mounted) setState(() => _attendanceBusy = false);
    }
  }

  void _snack(String key) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppTexts.t(key))),
    );
  }

  Future<void> _shareEvent(EventPresentation event) async {
    if (_shareBusy) return;
    setState(() => _shareBusy = true);
    try {
      final lang = Localizations.localeOf(context).languageCode;
      await EventShareImageService.shareEvent(
        context: context,
        event: event,
        languageCode: lang,
      );
    } catch (e, st) {
      // Último recurso: link HTTPS puro (serviço já tenta fallback interno).
      debugPrint('shareEvent root cause: $e\n$st');
      try {
        final link = 'https://remdy.app/e/${event.id}';
        await Share.share(
          '${event.title}\n${AppTexts.t('events_share_text')}\n$link',
          subject: event.title,
        );
      } catch (e2, st2) {
        debugPrint('shareEvent link fallback failed: $e2\n$st2');
        if (!mounted) return;
        _snack('events_share_error');
      }
    } finally {
      if (mounted) setState(() => _shareBusy = false);
    }
  }

  Future<void> _toggleEventLike() async {
    final uid = _uid;
    if (uid == null) {
      _snack('event_detail_login_required');
      return;
    }
    if (EventCommentsLogic.shouldIgnoreTap(busy: _eventLikeBusy)) return;

    final data = _eventSnap?.data();
    if (data == null) return;
    if (!EventLikesService.eventAllowsLike(data)) {
      _snack('event_like_unavailable');
      return;
    }

    final currentlyLiked =
        _optimisticEventLiked ?? _eventLiked ?? false;
    final currentCount = _optimisticEventLikes ??
        EventLikesService.asInt(data['likesCount']);
    final next = EventLikeOptimisticState(
      liked: currentlyLiked,
      likesCount: currentCount,
    ).toggle();

    setState(() {
      _eventLikeBusy = true;
      _optimisticEventLiked = next.liked;
      _optimisticEventLikes = next.likesCount;
      _eventLiked = next.liked;
    });

    try {
      final result = await EventLikesService.setLiked(
        eventId: widget.eventId,
        desiredLiked: next.liked,
      );
      if (!mounted) return;
      setState(() {
        _eventLiked = result['liked'] == true;
        _optimisticEventLiked = _eventLiked;
        _optimisticEventLikes = EventLikesService.asInt(
          result['likesCount'],
          next.likesCount,
        );
        _eventLikeBusy = false;
      });
    } on FirebaseFunctionsException catch (e) {
      if (kDebugMode) debugPrint('toggleEventLike CF: ${e.code} ${e.message}');
      if (!mounted) return;
      setState(() {
        _eventLiked = currentlyLiked;
        _optimisticEventLiked = currentlyLiked;
        _optimisticEventLikes = currentCount;
        _eventLikeBusy = false;
      });
      _snack(EventLikesService.errorKey(e));
    } catch (e, st) {
      if (kDebugMode) debugPrint('toggleEventLike: $e\n$st');
      if (!mounted) return;
      setState(() {
        _eventLiked = currentlyLiked;
        _optimisticEventLiked = currentlyLiked;
        _optimisticEventLikes = currentCount;
        _eventLikeBusy = false;
      });
      _snack('event_like_error');
    }
  }

  Future<void> _toggleCommentLike(String commentId, {required bool isLiked, required int likesCount}) async {
    final uid = _uid;
    if (uid == null) {
      _snack('event_detail_login_required');
      return;
    }
    if (_likingCommentIds.contains(commentId)) return;

    final nextLiked = !isLiked;
    final nextCount = EventCommentsLogic.applyLikeDelta(
      currentCount: likesCount,
      currentlyLiked: isLiked,
      wantLiked: nextLiked,
    );

    setState(() {
      _likingCommentIds.add(commentId);
      _commentLikeOpt[commentId] =
          _CommentLikeOpt(liked: nextLiked, likesCount: nextCount);
    });

    try {
      final result = await EventCommentsService.toggleLike(
        eventId: widget.eventId,
        commentId: commentId,
      );
      if (!mounted) return;
      setState(() {
        _commentLikeOpt[commentId] = _CommentLikeOpt(
          liked: result['liked'] == true,
          likesCount: EventCommentsService.asInt(
            result['likesCount'],
            nextCount,
          ),
        );
      });
    } on FirebaseFunctionsException catch (e) {
      if (kDebugMode) {
        debugPrint('toggleCommentLike CF: ${e.code} ${e.message}');
      }
      if (!mounted) return;
      setState(() {
        _commentLikeOpt[commentId] =
            _CommentLikeOpt(liked: isLiked, likesCount: likesCount);
      });
      _snack(EventCommentsService.likeErrorKey(e));
    } catch (e, st) {
      if (kDebugMode) debugPrint('toggleCommentLike: $e\n$st');
      if (!mounted) return;
      setState(() {
        _commentLikeOpt[commentId] =
            _CommentLikeOpt(liked: isLiked, likesCount: likesCount);
      });
      _snack('event_comment_like_error');
    } finally {
      if (mounted) {
        setState(() => _likingCommentIds.remove(commentId));
      }
    }
  }

  Future<void> _deleteComment(String commentId) async {
    final uid = _uid;
    if (uid == null) return;
    if (_deletingCommentIds.contains(commentId)) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(AppTexts.t('event_detail_delete_comment_title')),
        content: Text(AppTexts.t('event_detail_delete_comment_message')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(AppTexts.t('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              AppTexts.t('delete'),
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _deletingCommentIds.add(commentId));
    try {
      await EventCommentsService.deleteComment(
        eventId: widget.eventId,
        commentId: commentId,
      );
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      _snack(EventCommentsService.deleteErrorKey(e));
    } catch (e, st) {
      if (kDebugMode) debugPrint('deleteComment: $e\n$st');
      if (!mounted) return;
      _snack('event_comment_delete_error');
    } finally {
      if (mounted) setState(() => _deletingCommentIds.remove(commentId));
    }
  }

  void _openReply({
    required String commentId,
    required String name,
    required String text,
    required String? rootCommentId,
    required String? replyToCommentId,
  }) {
    final root = EventCommentsLogic.resolveRootCommentId(
      replyToCommentId: commentId,
      parentReplyToCommentId: replyToCommentId,
      parentRootCommentId: rootCommentId,
    );
    setState(() {
      _replyToCommentId = commentId;
      _replyToName = name;
      _replyToText = text;
      _replyRootId = root.isEmpty ? commentId : root;
      _replyC.clear();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _replyFocus.requestFocus();
      final ctx = _replyEditorKey.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          alignment: 0.85,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _cancelReply() {
    setState(() {
      _replyToCommentId = null;
      _replyToName = null;
      _replyToText = null;
      _replyRootId = null;
      _replyC.clear();
    });
  }

  Future<void> _sendRootComment() async {
    final err = EventCommentsLogic.validateCommentText(_commentC.text);
    if (err == 'empty') return;
    if (err == 'too_long') {
      _snack('event_comment_too_long');
      return;
    }
    if (_commentSending) return;
    final uid = _uid;
    if (uid == null) {
      _snack('event_detail_login_required');
      return;
    }

    final text = _commentC.text.trim();
    final commentId =
        EventCommentsService.allocateCommentId(eventId: widget.eventId);
    final requestId = EventCommentsService.newRequestId();
    final createdAt = DateTime.now();

    setState(() {
      _commentSending = true;
      _pendingById[commentId] = PendingEventComment(
        commentId: commentId,
        requestId: requestId,
        text: text,
        clientCreatedAt: createdAt,
      );
      _commentC.clear();
    });

    await _submitPending(commentId);
  }

  Future<void> _sendReply() async {
    final err = EventCommentsLogic.validateCommentText(_replyC.text);
    if (err == 'empty') return;
    if (err == 'too_long') {
      _snack('event_comment_too_long');
      return;
    }
    if (_replySending) return;
    final uid = _uid;
    if (uid == null) {
      _snack('event_detail_login_required');
      return;
    }
    final parentId = _replyToCommentId;
    if (parentId == null) return;

    final text = _replyC.text.trim();
    final commentId =
        EventCommentsService.allocateCommentId(eventId: widget.eventId);
    final requestId = EventCommentsService.newRequestId();
    final createdAt = DateTime.now();

    setState(() {
      _replySending = true;
      _pendingById[commentId] = PendingEventComment(
        commentId: commentId,
        requestId: requestId,
        text: text,
        clientCreatedAt: createdAt,
        replyToCommentId: parentId,
        replyToName: _replyToName,
        replyToText: _replyToText,
        rootCommentId: _replyRootId ?? parentId,
      );
    });

    final ok = await _submitPending(commentId);
    if (!mounted) return;
    if (ok) {
      setState(() {
        _replyC.clear();
        _replyToCommentId = null;
        _replyToName = null;
        _replyToText = null;
        _replyRootId = null;
        _replySending = false;
      });
    } else {
      setState(() => _replySending = false);
    }
  }

  Future<bool> _submitPending(String commentId) async {
    final pending = _pendingById[commentId];
    if (pending == null) return false;

    setState(() {
      pending.status = PendingEventCommentStatus.sending;
      if (pending.replyToCommentId == null) {
        _commentSending = true;
      }
    });

    try {
      final result = await EventCommentsService.createComment(
        eventId: widget.eventId,
        text: pending.text,
        requestId: pending.requestId,
        commentId: pending.commentId,
        replyToCommentId: pending.replyToCommentId,
        clientCreatedAt: pending.clientCreatedAt,
      );
      if (!mounted) return false;
      final serverId = (result['commentId'] ?? commentId).toString();
      setState(() {
        if (serverId != commentId) {
          final moved = _pendingById.remove(commentId);
          if (moved != null) {
            _pendingById[serverId] = moved;
          }
        }
        // Mantém pending até o stream trazer o doc (evita flash).
        if (pending.replyToCommentId == null) {
          _commentSending = false;
        }
      });
      return true;
    } on FirebaseFunctionsException catch (e) {
      if (kDebugMode) {
        debugPrint('createComment CF: ${e.code} ${e.message}');
      }
      if (!mounted) return false;
      setState(() {
        pending.status = PendingEventCommentStatus.failed;
        if (pending.replyToCommentId == null) {
          _commentSending = false;
        }
      });
      _snack(EventCommentsService.createErrorKey(e));
      return false;
    } catch (e, st) {
      if (kDebugMode) debugPrint('createComment: $e\n$st');
      if (!mounted) return false;
      setState(() {
        pending.status = PendingEventCommentStatus.failed;
        if (pending.replyToCommentId == null) {
          _commentSending = false;
        }
      });
      _snack('event_comment_publish_error');
      return false;
    }
  }

  List<_CommentRow> _buildRows() {
    final remote = <_CommentRow>[];
    for (final doc in _commentDocs) {
      final data = doc.data();
      if (data['isDeleted'] == true) continue;
      remote.add(_CommentRow.fromRemote(doc.id, data));
    }

    final pendingRows = _pendingById.values
        .where((p) => !_commentDocs.any((d) => d.id == p.commentId))
        .map(_CommentRow.fromPending)
        .toList();

    final all = [...remote, ...pendingRows];
    return EventCommentsLogic.orderThread<_CommentRow>(
      items: all,
      idOf: (c) => c.id,
      createdAtOf: (c) => c.sortAt,
      rootOf: (c) => c.rootCommentId,
      replyToOf: (c) => c.replyToCommentId,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_eventLoading && _eventSnap == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_eventError != null && _eventSnap == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            AppTexts.t('event_detail_load_error'),
            textAlign: TextAlign.center,
            style: const TextStyle(color: _muted, fontWeight: FontWeight.w700),
          ),
        ),
      );
    }
    if (_eventSnap == null || !_eventSnap!.exists) {
      return Center(
        child: Text(
          AppTexts.t('event_detail_not_found'),
          style: const TextStyle(color: _muted, fontWeight: FontWeight.w700),
        ),
      );
    }

    final data = _eventSnap!.data()!;
    if (_uid != null && !_viewKickoffScheduled) {
      _viewKickoffScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _viewRegistration.registerOnce(
          eventId: widget.eventId,
          source: 'mobile_app',
        );
      });
    }

    // Cover/gallery/localização via EventPresentation (mesmo contrato de Maps).
    final event = EventPresentation.fromMap(widget.eventId, data);
    final title = event.title;
    final category = event.category;
    final city = event.city;
    final state = event.stateName;
    final place = event.placeName.isNotEmpty
        ? event.placeName
        : (event.address.isNotEmpty ? event.address : '');
    final cc = event.countryCode;
    final startAt = event.startAt == null
        ? null
        : Timestamp.fromDate(event.startAt!);
    final desc = event.description;
    final createdBy = event.createdBy;
    final isEventOwner = _uid == createdBy;
    final attendees = event.attendeesCount;
    final status = event.status;
    final cancelled = event.isCancelled;
    final ended = status == 'ended' ||
        status == 'finished' ||
        status == 'closed' ||
        status == 'completed';
    final closed = cancelled || ended;
    final likesCount = _optimisticEventLikes ??
        EventLikesService.asInt(data['likesCount']);
    final liked = _optimisticEventLiked ?? _eventLiked ?? false;

    final galleryUrls = EventGalleryUrls.resolve(data);
    final lang = Localizations.localeOf(context).languageCode;
    final priceText = event.displayPrice();

    // Abas só com conteúdo
    final tabDefs = <_DetailTabDef>[
      const _DetailTabDef(0, 'events_tab_about', Icons.info_outline_rounded),
      if (event.hasSchedule)
        const _DetailTabDef(1, 'events_tab_schedule', Icons.view_agenda_outlined),
      if (event.hasAttractions)
        const _DetailTabDef(2, 'events_tab_attractions', Icons.star_outline_rounded),
      if (galleryUrls.isNotEmpty)
        const _DetailTabDef(3, 'events_tab_gallery', Icons.photo_library_outlined),
      // Aba Localização oculta na UI; _buildLocationPane / dados preservados.
    ];
    final effectiveTab = tabDefs.any((t) => t.id == _detailTab)
        ? _detailTab
        : (tabDefs.isNotEmpty ? tabDefs.first.id : 0);

    final commentRows = _buildRows();
    final visibleCount =
        commentRows.where((c) => !c.isPending || c.pendingFailed).length +
            commentRows.where((c) => c.isPending && !c.pendingFailed).length;

    return ListView(
      key: PageStorageKey<String>('event_detail_${widget.eventId}'),
      controller: _scrollController,
      padding: EdgeInsets.zero,
      children: [
        _buildDiscoverHero(
          event: event,
          liked: liked,
          likesCount: likesCount,
          cancelled: cancelled,
          languageCode: lang,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: _buildQuickInfo(
            event: event,
            attendees: attendees,
            priceText: priceText,
          ),
        ),
        const SizedBox(height: 12),
        _buildActionBar(
          event: event,
          liked: liked,
          cancelled: cancelled,
          closed: closed,
        ),
        if (tabDefs.length > 1)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
            child: _buildDetailTabs(tabDefs),
          ),
        // Hero replaces legacy top carousel; gallery lives in tab.
        if (effectiveTab == 3)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: EventGalleryGrid(
              urls: galleryUrls,
              selectedIndex: _galleryIndex,
              onPhotoTap: (index) => _openGalleryViewer(galleryUrls, index),
            ),
          ),
        if (effectiveTab == 1)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: _buildTextListPane(
              title: AppTexts.t('events_tab_schedule'),
              items: event.scheduleItems,
            ),
          ),
        if (effectiveTab == 2)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: _buildTextListPane(
              title: AppTexts.t('events_tab_attractions'),
              items: event.attractions,
            ),
          ),
        if (effectiveTab == 4)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: _buildLocationPane(
              event: event,
              place: place,
              city: city,
            ),
          ),
        if (effectiveTab == 0)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
          child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(_flagEmoji(cc),
                      style: const TextStyle(fontSize: 18)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: _text,
                      ),
                    ),
                  ),
                  _EventLikeButton(
                    liked: liked,
                    likesCount: likesCount,
                    busy: _eventLikeBusy,
                    enabled: !cancelled && _uid != null,
                    onTap: _toggleEventLike,
                  ),
                ],
              ),
              if (cancelled) ...[
                const SizedBox(height: 8),
                Text(
                  AppTexts.t('event_cancelled'),
                  style: const TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              _InfoRow(icon: Icons.schedule_rounded, text: _fmtDate(startAt)),
              if (category.isNotEmpty)
                _InfoRow(icon: Icons.category_rounded, text: category),
              if (city.isNotEmpty)
                _InfoRow(
                  icon: Icons.location_city_rounded,
                  text: state.isNotEmpty
                      ? '${_InfoRow.capitalize(city)}, $state'
                      : _InfoRow.capitalize(city),
                ),
              _InfoRow(
                icon: Icons.place_rounded,
                text: place.isEmpty
                    ? AppTexts.t('event_detail_place_tbd')
                    : place,
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _openDirections(event),
                  icon: const Icon(Icons.map_rounded),
                  label: Text(
                    AppTexts.t('event_detail_directions'),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _remdyBlue,
                    side: const BorderSide(color: _border),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              _InfoRow(
                icon: Icons.people_alt_rounded,
                text:
                    '${attendees.toString()} ${AppTexts.t('event_detail_attending')}',
              ),
              const SizedBox(height: 10),
              if (_attendeeDocs.isNotEmpty)
                SizedBox(
                  height: 42,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _attendeeDocs.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final attendeeData = _attendeeDocs[index].data();
                      final photoUrl =
                          (attendeeData['photoUrl'] ?? '').toString();
                      final name =
                          (attendeeData['name'] ?? 'Usuário').toString();
                      return GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => PublicProfilePage(
                                userUid: _attendeeDocs[index].id,
                              ),
                            ),
                          );
                        },
                        child: CircleAvatar(
                          radius: 20,
                          backgroundImage:
                              photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
                          child: photoUrl.isEmpty
                              ? Text(name.isNotEmpty ? name[0].toUpperCase() : '?')
                              : null,
                        ),
                      );
                    },
                  ),
                ),
              if (desc.trim().isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(
                  AppTexts.t('event_detail_about'),
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  desc,
                  style: const TextStyle(
                    color: Color(0xFF374151),
                    height: 1.35,
                  ),
                ),
              ],
              const SizedBox(height: 14),
              StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: _uid == null
                    ? const Stream.empty()
                    : _eventRef.collection('attendees').doc(_uid).snapshots(),
                builder: (context, snap) {
                  final joined = snap.data?.exists == true;
                  final disabled = (_uid == null) || _attendanceBusy || cancelled;
                  return SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: disabled
                          ? null
                          : (joined ? _leaveEvent : _joinEvent),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: joined ? Colors.grey : _remdyBlue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: _attendanceBusy
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              _uid == null
                                  ? AppTexts.t('event_detail_login_to_join')
                                  : (joined
                                      ? AppTexts.t('event_detail_leave')
                                      : AppTexts.t('event_detail_join')),
                              style: const TextStyle(fontWeight: FontWeight.w900),
                            ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 20),
              Text(
                visibleCount == 0
                    ? AppTexts.t('event_detail_comments')
                    : '${AppTexts.t('event_detail_comments')} ($visibleCount)',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              if (!cancelled) ...[
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _commentC,
                        focusNode: _commentFocus,
                        decoration: InputDecoration(
                          hintText: AppTexts.t('event_write_message'),
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        maxLength: EventCommentsService.maxCommentLength,
                        buildCounter: (
                          context, {
                          required currentLength,
                          required isFocused,
                          maxLength,
                        }) =>
                            null,
                        onSubmitted: (_) {
                          if (!_commentSending) _sendRootComment();
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    IconButton(
                      onPressed: _commentSending ? null : _sendRootComment,
                      icon: _commentSending
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2.2),
                            )
                          : const Icon(Icons.send),
                      tooltip: AppTexts.t('event_send'),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              if (!_commentsReady && commentRows.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.2),
                    ),
                  ),
                )
              else if (commentRows.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    AppTexts.t('event_detail_first_comment'),
                    style: const TextStyle(
                      color: _muted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                )
              else
                ...commentRows.map((row) {
                  final isReply = (row.replyToCommentId ?? '').isNotEmpty ||
                      (row.rootCommentId ?? '').isNotEmpty;
                  final opt = _commentLikeOpt[row.id];
                  final likedBy = row.likedBy;
                  final isLiked = opt?.liked ??
                      (_uid != null && likedBy.contains(_uid));
                  final likesCount =
                      opt?.likesCount ?? row.likesCount;
                  final liking = _likingCommentIds.contains(row.id);
                  final showReplyEditor = _replyToCommentId == row.id;

                  return KeyedSubtree(
                    key: ValueKey('event_comment_${widget.eventId}_${row.id}'),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: EdgeInsets.only(
                            left: isReply ? 28 : 0,
                            bottom: 12,
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              CircleAvatar(
                                radius: 18,
                                backgroundImage: row.photoUrl.isNotEmpty
                                    ? NetworkImage(row.photoUrl)
                                    : null,
                                child: row.photoUrl.isEmpty
                                    ? Text(
                                        row.name.isNotEmpty
                                            ? row.name[0].toUpperCase()
                                            : '?',
                                      )
                                    : null,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF8FAFC),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        row.name,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        _timeAgo(row.sortAt),
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: _muted,
                                        ),
                                      ),
                                      if ((row.replyToName ?? '')
                                          .isNotEmpty) ...[
                                        const SizedBox(height: 6),
                                        Container(
                                          width: double.infinity,
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFEDEFF3),
                                            borderRadius:
                                                BorderRadius.circular(10),
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                '${AppTexts.t('event_detail_replying_to')} ${row.replyToName}',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 12,
                                                  color: _remdyBlue,
                                                ),
                                              ),
                                              if ((row.replyToText ?? '')
                                                  .isNotEmpty) ...[
                                                const SizedBox(height: 2),
                                                Text(
                                                  row.replyToText!,
                                                  maxLines: 2,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    fontSize: 12,
                                                    color: _muted,
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                      ],
                                      const SizedBox(height: 6),
                                      Text(row.text),
                                      if (row.isPending) ...[
                                        const SizedBox(height: 6),
                                        Text(
                                          row.pendingFailed
                                              ? AppTexts.t(
                                                  'event_comment_send_failed')
                                              : AppTexts.t('event_sending'),
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: row.pendingFailed
                                                ? Colors.red
                                                : _muted,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        if (row.pendingFailed)
                                          TextButton(
                                            onPressed: () =>
                                                _submitPending(row.id),
                                            child: Text(
                                              AppTexts.t('event_try_again'),
                                            ),
                                          ),
                                      ],
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          InkWell(
                                            onTap: (liking ||
                                                    row.isPending ||
                                                    cancelled)
                                                ? null
                                                : () => _toggleCommentLike(
                                                      row.id,
                                                      isLiked: isLiked,
                                                      likesCount: likesCount,
                                                    ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  isLiked
                                                      ? Icons.favorite
                                                      : Icons.favorite_border,
                                                  size: 18,
                                                  color: isLiked
                                                      ? Colors.red
                                                      : _muted,
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  '$likesCount',
                                                  style: TextStyle(
                                                    color: isLiked
                                                        ? Colors.red
                                                        : _muted,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 14),
                                          if (!row.isPending && !cancelled)
                                            GestureDetector(
                                              onTap: () => _openReply(
                                                commentId: row.id,
                                                name: row.name,
                                                text: row.text,
                                                rootCommentId:
                                                    row.rootCommentId,
                                                replyToCommentId:
                                                    row.replyToCommentId,
                                              ),
                                              child: Text(
                                                AppTexts.t(
                                                    'event_detail_reply'),
                                                style: const TextStyle(
                                                  color: _remdyBlue,
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 13,
                                                ),
                                              ),
                                            ),
                                          const Spacer(),
                                          if (!row.isPending &&
                                              (row.uid == _uid ||
                                                  isEventOwner))
                                            GestureDetector(
                                              onTap: () =>
                                                  _deleteComment(row.id),
                                              child: const Icon(
                                                Icons.delete_outline,
                                                size: 18,
                                                color: _muted,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (showReplyEditor)
                          Padding(
                            key: _replyEditorKey,
                            padding: EdgeInsets.only(
                              left: isReply ? 28 : 0,
                              bottom: 14,
                            ),
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF3F4F6),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: _border),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${AppTexts.t('event_detail_replying_to')} ${_replyToName ?? ''}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  TextField(
                                    controller: _replyC,
                                    focusNode: _replyFocus,
                                    decoration: InputDecoration(
                                      hintText:
                                          AppTexts.t('event_write_message'),
                                      filled: true,
                                      fillColor: Colors.white,
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide.none,
                                      ),
                                    ),
                                    maxLength:
                                        EventCommentsService.maxCommentLength,
                                    buildCounter: (
                                      context, {
                                      required currentLength,
                                      required isFocused,
                                      maxLength,
                                    }) =>
                                        null,
                                    minLines: 1,
                                    maxLines: 4,
                                  ),
                                  Row(
                                    children: [
                                      TextButton(
                                        onPressed:
                                            _replySending ? null : _cancelReply,
                                        child: Text(AppTexts.t('event_cancel')),
                                      ),
                                      const Spacer(),
                                      ElevatedButton(
                                        onPressed: _replySending
                                            ? null
                                            : _sendReply,
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: _remdyBlue,
                                          foregroundColor: Colors.white,
                                        ),
                                        child: _replySending
                                            ? const SizedBox(
                                                width: 18,
                                                height: 18,
                                                child:
                                                    CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  color: Colors.white,
                                                ),
                                              )
                                            : Text(AppTexts.t('event_send')),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                }),
            ],
          ),
        ),
        ),
      ],
    );
  }

  Widget _buildDiscoverHero({
    required EventPresentation event,
    required bool liked,
    required int likesCount,
    required bool cancelled,
    required String languageCode,
  }) {
    // Capa: coverUrl / photoUrls — nunca logoUrl como fill do hero.
    final coverUrl = event.coverUrl.trim().isNotEmpty
        ? event.coverUrl.trim()
        : (event.photoUrls.isNotEmpty ? event.photoUrls.first.trim() : '');

    return EventDetailLightHeader(
      title: event.title,
      locationLine: event.locationLine(languageCode),
      dateLine: event.fullDateLabel(),
      confirmed: event.isConfirmed,
      cancelled: cancelled,
      liked: liked,
      confirmedLabel: AppTexts.t('events_confirmed_badge'),
      cancelledLabel: AppTexts.t('event_cancelled'),
      coverImageUrl: coverUrl.isEmpty ? null : coverUrl,
      onBack: () => Navigator.maybePop(context),
      // Compartilhar permanece só na faixa de ações (ícone do hero oculto).
      onShare: null,
      onLike: (cancelled || _uid == null || _eventLikeBusy)
          ? null
          : _toggleEventLike,
      pageBackground: _bg,
    );
  }

  Widget _buildQuickInfo({
    required EventPresentation event,
    required int attendees,
    required String? priceText,
  }) {
    final venue = event.venueLine();
    return Row(
      children: [
        Expanded(
          child: _QuickInfoTile(
            icon: Icons.people_alt_outlined,
            text: '$attendees ${AppTexts.t('event_detail_attending')}',
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _QuickInfoTile(
            icon: Icons.place_outlined,
            text: venue.isEmpty ? AppTexts.t('event_detail_place_tbd') : venue,
          ),
        ),
        if (priceText != null) ...[
          const SizedBox(width: 8),
          Expanded(
            child: _QuickInfoTile(
              icon: Icons.confirmation_number_outlined,
              text: priceText,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildDetailTabs(List<_DetailTabDef> tabs) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final tab in tabs)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: ChoiceChip(
                selected: _detailTab == tab.id,
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(tab.icon, size: 16),
                    const SizedBox(width: 6),
                    Text(AppTexts.t(tab.key)),
                  ],
                ),
                selectedColor: _remdyBlue.withValues(alpha: 0.15),
                labelStyle: TextStyle(
                  color: _detailTab == tab.id ? _remdyBlue : _muted,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
                onSelected: (_) {
                  if (_detailTab == tab.id) return;
                  setState(() => _detailTab = tab.id);
                },
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _openGalleryViewer(List<String> urls, int index) async {
    if (urls.isEmpty) return;
    final start = index.clamp(0, urls.length - 1);
    final result = await EventGalleryViewerPage.open(
      context,
      urls: urls,
      initialIndex: start,
    );
    if (!mounted) return;
    // Mantém aba Galeria + índice; não recria a página nem mexe no scroll.
    setState(() {
      _detailTab = 3;
      _galleryIndex = (result ?? start).clamp(0, urls.length - 1);
    });
  }

  Widget _buildTextListPane({required String title, required List<String> items}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: _remdyBlue)),
        const SizedBox(height: 8),
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('•  ', style: TextStyle(fontWeight: FontWeight.w800)),
                Expanded(child: Text(item, style: const TextStyle(height: 1.35))),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildLocationPane({
    required EventPresentation event,
    required String place,
    required String city,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          AppTexts.t('events_tab_location'),
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: _remdyBlue),
        ),
        const SizedBox(height: 8),
        Text(
          event.venueLine().isEmpty ? AppTexts.t('event_detail_place_tbd') : event.venueLine(),
          style: const TextStyle(height: 1.35, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => _openDirections(event),
          icon: const Icon(Icons.map_rounded),
          label: Text(
            AppTexts.t('event_detail_directions'),
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: _remdyBlue,
            side: const BorderSide(color: _border),
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
      ],
    );
  }
}

class _QuickInfoTile extends StatelessWidget {
  const _QuickInfoTile({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F8),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Icon(icon, color: const Color(0xFF313A5F), size: 20),
          const SizedBox(height: 6),
          Text(
            text,
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Color(0xFF374151),
              height: 1.25,
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailTabDef {
  const _DetailTabDef(this.id, this.key, this.icon);
  final int id;
  final String key;
  final IconData icon;
}

class _CommentLikeOpt {
  const _CommentLikeOpt({required this.liked, required this.likesCount});
  final bool liked;
  final int likesCount;
}

class _CommentRow {
  _CommentRow({
    required this.id,
    required this.uid,
    required this.name,
    required this.photoUrl,
    required this.text,
    required this.sortAt,
    required this.likesCount,
    required this.likedBy,
    this.replyToCommentId,
    this.replyToName,
    this.replyToText,
    this.rootCommentId,
    this.isPending = false,
    this.pendingFailed = false,
  });

  final String id;
  final String uid;
  final String name;
  final String photoUrl;
  final String text;
  final DateTime? sortAt;
  final int likesCount;
  final List<String> likedBy;
  final String? replyToCommentId;
  final String? replyToName;
  final String? replyToText;
  final String? rootCommentId;
  final bool isPending;
  final bool pendingFailed;

  factory _CommentRow.fromRemote(String id, Map<String, dynamic> data) {
    DateTime? sortAt;
    final createdAt = data['createdAt'];
    final clientCreatedAt = data['clientCreatedAt'];
    if (createdAt is Timestamp) {
      sortAt = createdAt.toDate();
    } else if (clientCreatedAt is Timestamp) {
      sortAt = clientCreatedAt.toDate();
    }
    return _CommentRow(
      id: id,
      uid: (data['uid'] ?? '').toString(),
      name: (data['name'] ?? AppTexts.t('event_detail_user')).toString(),
      photoUrl: (data['photoUrl'] ?? '').toString(),
      text: (data['text'] ?? '').toString(),
      sortAt: sortAt,
      likesCount: EventCommentsService.asInt(data['likesCount']),
      likedBy: EventCommentsService.asUidList(data['likedBy']),
      replyToCommentId: _optString(data['replyToCommentId']),
      replyToName: _optString(data['replyToName']),
      replyToText: _optString(data['replyToText']),
      rootCommentId: _optString(data['rootCommentId']),
    );
  }

  static String? _optString(dynamic value) {
    if (value == null) return null;
    final s = value.toString().trim();
    return s.isEmpty ? null : s;
  }

  factory _CommentRow.fromPending(PendingEventComment p) {
    return _CommentRow(
      id: p.commentId,
      uid: FirebaseAuth.instance.currentUser?.uid ?? '',
      name: FirebaseAuth.instance.currentUser?.displayName ??
          AppTexts.t('event_detail_user'),
      photoUrl: FirebaseAuth.instance.currentUser?.photoURL ?? '',
      text: p.text,
      sortAt: p.clientCreatedAt,
      likesCount: 0,
      likedBy: const [],
      replyToCommentId: p.replyToCommentId,
      replyToName: p.replyToName,
      replyToText: p.replyToText,
      rootCommentId: p.rootCommentId,
      isPending: true,
      pendingFailed: p.status == PendingEventCommentStatus.failed,
    );
  }
}

class _EventLikeButton extends StatelessWidget {
  const _EventLikeButton({
    required this.liked,
    required this.likesCount,
    required this.busy,
    required this.enabled,
    required this.onTap,
  });

  final bool liked;
  final int likesCount;
  final bool busy;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: liked ? AppTexts.t('event_unlike') : AppTexts.t('event_like'),
      child: InkWell(
        onTap: (!enabled || busy) ? null : onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                liked ? Icons.favorite : Icons.favorite_border,
                color: liked ? Colors.red : _EventDetailPageState._muted,
                size: 22,
              ),
              const SizedBox(width: 4),
              Text(
                '$likesCount',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: liked ? Colors.red : _EventDetailPageState._muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _timeAgo(DateTime? date) {
  final t = AppTexts.current;
  if (date == null) return t.get('event_sending');
  final diff = DateTime.now().difference(date);
  if (diff.inSeconds < 60) return t.get('event_detail_now');
  if (diff.inMinutes < 60) {
    return '${diff.inMinutes} ${t.get('event_detail_minutes_ago')}';
  }
  if (diff.inHours < 24) {
    return '${diff.inHours} ${t.get('event_detail_hours_ago')}';
  }
  return '${diff.inDays} ${t.get('event_detail_days_ago')}';
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InfoRow({required this.icon, required this.text});

  static const Color _remdyBlue = Color(0xFF313A5F);

  static String capitalize(String value) {
    if (value.isEmpty) return value;
    return value
        .split(' ')
        .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: _remdyBlue),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: Color(0xFF374151),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
