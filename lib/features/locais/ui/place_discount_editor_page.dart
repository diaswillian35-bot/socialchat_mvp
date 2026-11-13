import 'package:flutter/material.dart';

import '../../../l10n/app_texts.dart';
import '../../../services/functions_error_text.dart';
import '../data/place_discount_service.dart';
import '../models/place_discount.dart';
import 'locais_layout.dart';

/// Seletor do dono ("Selo de desconto") e, com [partnership], o do admin.
class PlaceDiscountEditorPage extends StatefulWidget {
  const PlaceDiscountEditorPage({
    super.key,
    required this.placeId,
    required this.placeName,
    this.placeStatus = '',
    this.initial,
    this.partnership = false,
  });

  final String placeId;
  final String placeName;
  final String placeStatus;
  final PlaceDiscount? initial;
  final bool partnership;

  static Future<bool?> open(
    BuildContext context, {
    required String placeId,
    required String placeName,
    String placeStatus = '',
    PlaceDiscount? initial,
    bool partnership = false,
  }) {
    return Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => PlaceDiscountEditorPage(
          placeId: placeId,
          placeName: placeName,
          placeStatus: placeStatus,
          initial: initial,
          partnership: partnership,
        ),
      ),
    );
  }

  @override
  State<PlaceDiscountEditorPage> createState() =>
      _PlaceDiscountEditorPageState();
}

class _PlaceDiscountEditorPageState extends State<PlaceDiscountEditorPage> {
  late bool _enabled;
  late int _percent;
  DateTime? _until;
  late String _coveredBy;
  bool _saving = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    _enabled = i?.enabled ?? true;
    _percent = i?.percent ?? 10;
    _until = i?.validUntil;
    _coveredBy =
        i != null && PlaceDiscount.coveredByValues.contains(i.coveredBy)
            ? i.coveredBy
            : (widget.partnership ? 'shared' : 'place');
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    if (widget.initial != null) {
      setState(() => _loading = false);
      return;
    }
    try {
      final loaded = await PlaceDiscountService.load(widget.placeId);
      if (!mounted) return;
      if (loaded != null) {
        setState(() {
          _enabled = loaded.enabled;
          _percent = loaded.percent;
          _until = loaded.validUntil;
          if (PlaceDiscount.coveredByValues.contains(loaded.coveredBy)) {
            _coveredBy = loaded.coveredBy;
          }
          _loading = false;
        });
        return;
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final last = today.add(const Duration(days: PlaceDiscount.maxDays));
    final picked = await showDatePicker(
      context: context,
      initialDate: _until?.toLocal() ?? last,
      firstDate: today,
      lastDate: last,
    );
    if (picked != null && mounted) setState(() => _until = picked);
  }

  Future<void> _save() async {
    if (_until == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppTexts.t('fn_error_discount_date_required'))),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      if (widget.partnership) {
        await PlaceDiscountService.setPartnershipDiscount(
          placeId: widget.placeId,
          percent: _percent,
          validUntil: _until!,
          enabled: _enabled,
          coveredBy: _coveredBy,
        );
      } else {
        await PlaceDiscountService.setOwnerDiscount(
          placeId: widget.placeId,
          percent: _percent,
          validUntil: _until!,
          enabled: _enabled,
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppTexts.t('place_discount_saved'))),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(functionsErrorText(e, fallbackKey: 'place_discount_error')),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexts.t;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: LocaisColors.text,
        title: Text(
          t(widget.partnership
              ? 'place_discount_admin_title'
              : 'place_discount_title'),
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                Text(
                  [
                    widget.placeName,
                    if (widget.placeStatus.isNotEmpty) widget.placeStatus,
                  ].join(' · '),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: LocaisColors.muted,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: LocaisColors.border),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          t('place_discount_show'),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: LocaisColors.text,
                          ),
                        ),
                      ),
                      Switch.adaptive(
                        value: _enabled,
                        activeTrackColor: LocaisColors.navy,
                        activeThumbColor: Colors.white,
                        onChanged: (v) => setState(() => _enabled = v),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  t('place_discount_percent_label'),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: LocaisColors.muted,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final p in PlaceDiscount.percents)
                      _chip('$p%', selected: _percent == p, onTap: () {
                        setState(() => _percent = p);
                      }),
                  ],
                ),
                const SizedBox(height: 18),
                Text(
                  t('place_discount_valid_until'),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: LocaisColors.muted,
                  ),
                ),
                const SizedBox(height: 8),
                InkWell(
                  key: const Key('place_discount_date'),
                  onTap: _pickDate,
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: LocaisColors.border),
                    ),
                    child: Text(
                      _until == null
                          ? t('place_discount_pick_date')
                          : PlaceDiscount.formatDate(_until!),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: LocaisColors.text,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  t('place_discount_help'),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                    color: LocaisColors.muted,
                  ),
                ),
                if (widget.partnership) ...[
                  const SizedBox(height: 18),
                  Text(
                    t('place_discount_covered_by'),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: LocaisColors.muted,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final c in PlaceDiscount.coveredByValues)
                        _chip(
                          t('place_discount_covered_$c'),
                          selected: _coveredBy == c,
                          onTap: () => setState(() => _coveredBy = c),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 18),
                Text(
                  t('place_discount_condition_label'),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: LocaisColors.muted,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  t('place_discount_condition'),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                    color: LocaisColors.muted,
                  ),
                ),
                const SizedBox(height: 18),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: LocaisColors.navy,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(48),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : Text(t('place_discount_save')),
                ),
              ],
            ),
    );
  }

  Widget _chip(String label,
      {required bool selected, required VoidCallback onTap}) {
    return Material(
      color: selected ? LocaisColors.navy : Colors.white,
      shape: StadiumBorder(
        side: BorderSide(
          color: selected ? LocaisColors.navy : LocaisColors.border,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: selected ? Colors.white : LocaisColors.navy,
            ),
          ),
        ),
      ),
    );
  }
}
