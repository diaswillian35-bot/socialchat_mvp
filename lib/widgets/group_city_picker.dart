import 'package:flutter/material.dart';

import '../l10n/app_texts.dart';
import '../services/group_create_flow.dart';
import '../services/group_places_client.dart';
import '../widgets/remdy_keyboard_caps.dart';
import '../widgets/required_field.dart';

/// City suggestion sheet shared by create and edit.
/// Returns the tapped place. Dismissing without a tap changes nothing.
Future<GroupCityCandidate?> showGroupCityPicker({
  required BuildContext context,
  required String countryIso2,
  String initialText = '',
}) {
  return showModalBottomSheet<GroupCityCandidate>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      return _GroupCityPicker(
        countryIso2: countryIso2,
        initialText: initialText,
      );
    },
  );
}

class _GroupCityPicker extends StatefulWidget {
  const _GroupCityPicker({
    required this.countryIso2,
    required this.initialText,
  });

  final String countryIso2;
  final String initialText;

  @override
  State<_GroupCityPicker> createState() => _GroupCityPickerState();
}

class _GroupCityPickerState extends State<_GroupCityPicker> {
  late final TextEditingController _searchC =
      TextEditingController(text: widget.initialText);
  List<GroupCityCandidate> _results = const [];
  bool _loading = false;
  bool _searched = false;

  @override
  void dispose() {
    _searchC.dispose();
    super.dispose();
  }

  Future<void> _runSearch(String value) async {
    if (value.trim().length < 2) {
      setState(() {
        _results = const [];
        _loading = false;
        _searched = false;
      });
      return;
    }
    setState(() => _loading = true);
    final found = await GroupPlacesClient.search(
      apiKey: GroupPlacesClient.apiKey,
      countryIso2: widget.countryIso2,
      input: value,
    );
    if (!mounted) return;
    setState(() {
      _results = found;
      _loading = false;
      _searched = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final pending = _searched && !_loading && _results.isEmpty;
    return SafeArea(
      child: Container(
        height: MediaQuery.of(context).size.height * 0.78,
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          children: [
            Text(
              AppTexts.t('create_group_choose_city'),
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: Color(0xFF111827),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _searchC,
              autofocus: true,
              textCapitalization: RemdyKeyboardCaps.none,
              onChanged: _runSearch,
              decoration: RequiredFieldChrome.apply(
                pending: pending,
                base: InputDecoration(
                  hintText: AppTexts.t('create_group_search_city'),
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
            if (pending)
              RequiredPendingNotice(
                message: AppTexts.t('group_create_city_invalid'),
                pendingLabel: AppTexts.t('field_pending'),
              ),
            const SizedBox(height: 12),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      itemCount: _results.length,
                      itemBuilder: (context, index) {
                        final item = _results[index];
                        return ListTile(
                          title: Text(item.display),
                          onTap: () => Navigator.pop(context, item),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
