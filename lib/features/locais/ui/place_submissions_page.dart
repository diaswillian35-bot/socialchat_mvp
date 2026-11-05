import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../../../l10n/app_texts.dart';
import '../data/place_submission_service.dart';
import '../locais_strings.dart';
import '../models/place_listing.dart';
import 'place_editor_page.dart';

/// "Meus locais" (dono) ou "Locais em análise" (Modo administrador).
/// Reusa ListTile + folha de ações no mesmo padrão do Menu/denúncia.
class PlaceSubmissionsPage extends StatefulWidget {
  const PlaceSubmissionsPage({
    super.key,
    required this.adminPending,
    this.loader,
  });

  final bool adminPending;

  /// Somente testes/capturas: substitui a chamada às Functions.
  final Future<List<PlaceDraft>> Function()? loader;

  @override
  State<PlaceSubmissionsPage> createState() => _PlaceSubmissionsPageState();
}

class _PlaceSubmissionsPageState extends State<PlaceSubmissionsPage> {
  static const Color _bg = Colors.white;
  static const Color _text = Color(0xFF111827);
  static const Color _muted = Color(0xFF6B7280);

  late Future<List<PlaceDraft>> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    final loader = widget.loader;
    _future = loader != null
        ? loader()
        : widget.adminPending
            ? PlaceSubmissionService.listPending()
            : PlaceSubmissionService.listMine();
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'approved':
      case 'published':
        return AppTexts.t('place_status_approved');
      case 'rejected':
        return AppTexts.t('place_status_rejected');
      default:
        return AppTexts.t('place_status_pending');
    }
  }

  Future<void> _open(PlaceDraft p) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => PlaceEditorPage(
          placeId: p.id,
          adminReview: widget.adminPending,
        ),
      ),
    );
    if (changed == true && mounted) setState(_reload);
  }

  Future<void> _moderate(PlaceDraft p, {required bool approve}) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await PlaceSubmissionService.moderate(p.id, approve: approve);
      messenger.showSnackBar(SnackBar(
        content: Text(AppTexts.t(
          approve ? 'place_approved_snack' : 'place_rejected_snack',
        )),
      ));
      if (mounted) setState(_reload);
    } on FirebaseFunctionsException catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text(AppTexts.t(
          e.message == 'photo_required'
              ? 'place_err_photo'
              : 'place_submit_error',
        )),
      ));
    }
  }

  void _actions(PlaceDraft p) {
    final t = AppTexts.t;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.storefront),
              title: Text(p.name),
              subtitle: Text(p.cityDisplay),
            ),
            ListTile(
              leading: const Icon(Icons.edit),
              title: Text(t('place_view_edit')),
              onTap: () {
                Navigator.pop(sheet);
                _open(p);
              },
            ),
            ListTile(
              key: const Key('place_approve'),
              leading: const Icon(Icons.check_circle, color: Color(0xFF16A34A)),
              title: Text(t('place_approve')),
              onTap: () {
                Navigator.pop(sheet);
                _moderate(p, approve: true);
              },
            ),
            ListTile(
              key: const Key('place_reject'),
              leading: const Icon(Icons.cancel, color: Color(0xFFB91C1C)),
              title: Text(t('place_reject')),
              onTap: () {
                Navigator.pop(sheet);
                _moderate(p, approve: false);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexts.t;
    final strings = LocaisStrings.of(context);
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        title: Text(
          t(widget.adminPending ? 'place_pending_title' : 'place_mine_title'),
        ),
      ),
      body: FutureBuilder<List<PlaceDraft>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text(t('place_submit_error')));
          }
          final items = snap.data ?? const [];
          if (items.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  t(widget.adminPending
                      ? 'place_pending_empty'
                      : 'place_mine_empty'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: _muted),
                ),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async {
              setState(_reload);
              await _future;
            },
            child: ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final p = items[i];
                final category =
                    strings.categoryName(PlaceCategory.parse(p.category));
                return ListTile(
                  leading: p.coverUrl.isNotEmpty
                      ? CircleAvatar(backgroundImage: NetworkImage(p.coverUrl))
                      : const CircleAvatar(child: Icon(Icons.storefront)),
                  title: Text(
                    p.name,
                    style: const TextStyle(
                      color: _text,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  subtitle: Text(
                    '$category · ${p.cityDisplay} · ${_statusLabel(p.status)}',
                  ),
                  onTap: () => widget.adminPending ? _actions(p) : _open(p),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
